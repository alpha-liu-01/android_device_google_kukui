/*
 * PID 1 until Android init. Load usb-storage, wait for the USB disk,
 * copy kmsg onto pmOS_boot, then exec Android's init.
 *
 * One child reads kmsg. Another writes the file and fsyncs. The reader
 * must not fsync: the same USB stick is busy during format, and a stalled
 * fsync used to stop consuming the ring. There is no watchdog feeder.
 *
 * pmOS_boot has a journal. Force power-off used to corrupt the ext2
 * bitmap, the writer stalled, and the printk ring dropped the abort.
 * The previous boot's log is renamed to kukui-phase3.log.prev.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

struct linux_dirent64 {
    unsigned long long d_ino;
    long long d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

#define RELEASE "6.18.28-mt81-kukui2"
#define USB_STORAGE "/lib/modules/" RELEASE "/usb-storage.ko"
#define LOG_PATH "/bootlog/kukui-phase3.log"
#define LOG_PREV "/bootlog/kukui-phase3.log.prev"
/* sysfs is mounted here, not on /sys. /sys stays empty until Android init. */
#define SYSFS "/kukui-sys"

static void write_all(int fd, const char *buf, size_t len) {
    while (len) {
        ssize_t n = write(fd, buf, len);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return;
        }
        buf += n;
        len -= (size_t)n;
    }
}

static void kmsg(const char *text) {
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        write_all(fd, text, strlen(text));
        close(fd);
    }
}

static int read_file(const char *path, char *buf, size_t len) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    ssize_t n;
    if (fd < 0)
        return -1;
    n = read(fd, buf, len - 1);
    close(fd);
    if (n < 0)
        return -1;
    buf[n] = 0;
    return 0;
}

static int name_is_target(const char *name) {
#ifdef KUKUI_EMMC
    /* mmcblk0p1, not the whole disk mmcblk0. */
    return strncmp(name, "mmcblk", 6) == 0 && strchr(name, 'p') != NULL;
#else
    return strncmp(name, "sd", 2) == 0 && strchr(name, 'p') == NULL &&
           strlen(name) > 3;
#endif
}

#ifdef KUKUI_EMMC
static int on_emmc(const char *name) {
    char path[160], link[512];
    ssize_t n;

    snprintf(path, sizeof(path), SYSFS "/class/block/%s", name);
    n = readlink(path, link, sizeof(link) - 1);
    if (n < 0)
        return 0;
    link[n] = 0;
    return strstr(link, "11230000.mmc") != NULL;
}
#endif

static int find_part(const char *partname, char *out, size_t outlen) {
    char buf[4096];
    char want[80];
    int dirfd = open(SYSFS "/class/block", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dirfd < 0)
        return -1;
    snprintf(want, sizeof(want), "PARTNAME=%s", partname);
    for (;;) {
        ssize_t n = syscall(SYS_getdents64, dirfd, buf, sizeof(buf));
        ssize_t off;
        if (n <= 0)
            break;
        for (off = 0; off < n;) {
            struct linux_dirent64 *ent = (struct linux_dirent64 *)(buf + off);
            char path[160], got[512];
            char *hit;
            off += ent->d_reclen;
            if (ent->d_name[0] == '.')
                continue;
            if (!name_is_target(ent->d_name))
                continue;
#ifdef KUKUI_EMMC
            if (!on_emmc(ent->d_name))
                continue;
#endif
            snprintf(path, sizeof(path), SYSFS "/class/block/%s/partition", ent->d_name);
            if (access(path, F_OK) != 0)
                continue;
            snprintf(path, sizeof(path), SYSFS "/class/block/%s/uevent", ent->d_name);
            if (read_file(path, got, sizeof(got)) != 0)
                continue;
            hit = strstr(got, want);
            if (hit == NULL)
                continue;
            hit += strlen(want);
            if (*hit != '\n' && *hit != '\0')
                continue;
            snprintf(out, outlen, "/dev/%s", ent->d_name);
            close(dirfd);
            return 0;
        }
    }
    close(dirfd);
    return -1;
}

#ifndef KUKUI_EMMC
static int load_usb_storage(void) {
    int fd;
    if (access(SYSFS "/module/usb_storage", F_OK) == 0)
        return 0;
    fd = open(USB_STORAGE, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    if (syscall(SYS_finit_module, fd, "", 0) != 0) {
        close(fd);
        return -1;
    }
    close(fd);
    return 0;
}
#endif

/* Keep the previous boot. A new boot used to truncate the only copy
 * before any new line was durable. */
static void rotate_log(void) {
    unlink(LOG_PREV);
    if (rename(LOG_PATH, LOG_PREV) != 0 && errno != ENOENT)
        kmsg("kukui-android phase3 log rotate failed\n");
}

static void fsync_dir(const char *path) {
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd >= 0) {
        fsync(fd);
        close(fd);
    }
}

/* Writer only. A stalled fsync must not stop the kmsg reader. */
static void write_log(int pipefd, int logfd) {
    char buf[4096];
    for (;;) {
        ssize_t n = read(pipefd, buf, sizeof(buf));
        if (n > 0) {
            write_all(logfd, buf, (size_t)n);
            fsync(logfd);
        } else if (n == 0) {
            sleep(1);
        } else if (errno != EINTR) {
            sleep(1);
        }
    }
}

/* Reader only. Drain /proc/kmsg into the pipe and never touch the disk. */
static void read_kmsg(int kfd, int pipefd) {
    char buf[4096];
    struct pollfd pfd;

    pfd.fd = kfd;
    pfd.events = POLLIN;
    for (;;) {
        int pr = poll(&pfd, 1, 1000);
        if (pr < 0) {
            if (errno != EINTR)
                sleep(1);
            continue;
        }
        if (pr == 0)
            continue;
        for (;;) {
            ssize_t n = read(kfd, buf, sizeof(buf));
            if (n > 0)
                write_all(pipefd, buf, (size_t)n);
            else
                break;
        }
    }
}

int main(void) {
    char boot[64], super[64];
    int waited, kfd, logfd, pipes[2], reader, writer;
    const char *header = "kukui-android phase3\n";

    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mkdir("/kukui-proc", 0755);
    mkdir("/kukui-sys", 0755);
    mkdir("/bootlog", 0755);
    mount("proc", "/kukui-proc", "proc", 0, NULL);
    mount("sysfs", "/kukui-sys", "sysfs", 0, NULL);
    kmsg("kukui-android phase3\n");

#ifndef KUKUI_EMMC
    if (load_usb_storage() != 0)
        kmsg("kukui-android phase3 usb-storage load failed\n");
#else
    kmsg("kukui-android phase3 emmc\n");
#endif

    boot[0] = super[0] = 0;
    for (waited = 0; waited < 45; waited++) {
        if (boot[0] == 0)
            find_part("pmOS_boot", boot, sizeof(boot));
        if (super[0] == 0)
            find_part("super", super, sizeof(super));
        if (boot[0] && super[0])
            break;
        sleep(1);
    }
    if (boot[0] == 0 || super[0] == 0) {
        kmsg(boot[0] == 0 ? "kukui-android phase3 no boot partition\n"
                          : "kukui-android phase3 no super partition\n");
        for (;;)
            sleep(3600);
    }

    if (mount(boot, "/bootlog", "ext4", 0, NULL) != 0)
        kmsg("kukui-android phase3 bootlog mount failed\n");
    rotate_log();
    fsync_dir("/bootlog");
    logfd = open(LOG_PATH, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (logfd >= 0) {
        write_all(logfd, header, strlen(header));
        fsync(logfd);
        fsync_dir("/bootlog");
    }

    kfd = open("/kukui-proc/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (kfd >= 0 && logfd >= 0 && pipe(pipes) == 0) {
        /* Default pipe-max-size is 1 MiB. A journal commit on a slow
         * stick can take longer than that once logcat is also in kmsg. */
        {
            int pmax = open("/kukui-proc/sys/fs/pipe-max-size", O_WRONLY | O_CLOEXEC);
            if (pmax >= 0) {
                write_all(pmax, "4194304", 7);
                close(pmax);
            }
        }
        if (fcntl(pipes[0], F_SETPIPE_SZ, 4 << 20) < 0 ||
            fcntl(pipes[1], F_SETPIPE_SZ, 4 << 20) < 0)
            kmsg("kukui-android phase3 pipe size unchanged\n");
        reader = fork();
        if (reader == 0) {
            close(pipes[0]);
            close(logfd);
            read_kmsg(kfd, pipes[1]);
            for (;;)
                sleep(3600);
        }
        writer = fork();
        if (writer == 0) {
            close(pipes[1]);
            close(kfd);
            write_log(pipes[0], logfd);
            for (;;)
                sleep(3600);
        }
        close(pipes[0]);
        close(pipes[1]);
        if (reader < 0 || writer < 0)
            kmsg("kukui-android phase3 log fork failed\n");
    }
    if (kfd >= 0)
        close(kfd);
    if (logfd >= 0)
        close(logfd);

    umount2("/bootlog", MNT_DETACH);
    umount2("/kukui-proc", MNT_DETACH);
    umount2("/kukui-sys", MNT_DETACH);
    umount2("/dev", MNT_DETACH);
    {
        char *args[] = {"/init.android", NULL};
        sync();
        execv("/init.android", args);
    }
    kmsg("kukui-android phase3 exec init failed\n");
    for (;;)
        sleep(3600);
}
