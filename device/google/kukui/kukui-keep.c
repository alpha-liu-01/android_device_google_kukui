/*
 * PID 1 until Android init. Load usb-storage, wait until the boot and
 * super partitions are visible, then exec Android's init.
 *
 * There is no watchdog feeder. kmsg is not copied onto pmOS_boot.
 *
 * A child feeds /kukui-wifi-reprobe.sh to sh after Android has mounted
 * vendor. The first ath10k probe can time out while userdata is being
 * written, and nothing else retries it. The script lives in this
 * ramdisk; FreeRamdisk removes the file before the retry would run.
 */
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
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
/* sysfs is mounted here, not on /sys. /sys stays empty until Android init. */
#define SYSFS "/kukui-sys"
#define WIFI_SCRIPT "/kukui-wifi-reprobe.sh"
#define WIFI_SCRIPT_MAX (64 * 1024)

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

static int read_alloc(const char *path, char **out, size_t *out_len) {
    int fd;
    struct stat st;
    char *buf;
    size_t got = 0;

    *out = NULL;
    *out_len = 0;
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    if (fstat(fd, &st) != 0 || st.st_size <= 0 ||
        st.st_size > WIFI_SCRIPT_MAX) {
        close(fd);
        return -1;
    }
    buf = malloc((size_t)st.st_size);
    if (!buf) {
        close(fd);
        return -1;
    }
    while (got < (size_t)st.st_size) {
        ssize_t n = read(fd, buf + got, (size_t)st.st_size - got);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            free(buf);
            close(fd);
            return -1;
        }
        if (n == 0)
            break;
        got += (size_t)n;
    }
    close(fd);
    if (got != (size_t)st.st_size) {
        free(buf);
        return -1;
    }
    *out = buf;
    *out_len = got;
    return 0;
}

/* First-stage init already has /system mounted, so /system/bin/sh exists
 * before switch_root. Chrooting then leaves this child on the ramdisk
 * that second stage abandons. /proc/1/exe is resolved from this child's
 * root, so after switch_root it is not the plain /system/bin/init path.
 * The argument vector is not a path: second stage is the "second_stage"
 * argument. Android init then unshares its mount namespace, so /vendor
 * is not visible here even after /proc/1/root/system/bin/sh opens.
 * Join that namespace before chroot. procfd is the /kukui-proc mount
 * and stays usable after the parent detaches it. */
static int argv_has(int procfd, const char *arg) {
    char buf[160];
    int fd;
    ssize_t n, i;
    size_t alen;

    fd = openat(procfd, "1/cmdline", O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    n = read(fd, buf, sizeof(buf));
    close(fd);
    if (n <= 0)
        return 0;
    alen = strlen(arg);
    i = 0;
    while (i < n) {
        size_t len = 0;
        while (i + (ssize_t)len < n && buf[i + (ssize_t)len] != '\0')
            len++;
        if (len == alen && memcmp(buf + i, arg, alen) == 0)
            return 1;
        i += (ssize_t)len + 1;
    }
    return 0;
}

static int second_stage(int procfd) {
    return argv_has(procfd, "second_stage");
}

static int join_pid1_mnt(int procfd) {
    int fd, rc;

    fd = openat(procfd, "1/ns/mnt", O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    rc = syscall(SYS_setns, fd, CLONE_NEWNS);
    close(fd);
    return rc;
}

static int enter_android_root(int procfd, int kfd) {
    int waited, joined = 0;

    for (waited = 0; waited < 600; waited++) {
        int shfd, kofd, rootfd;
        if (!second_stage(procfd)) {
            sleep(1);
            continue;
        }
        if (!joined) {
            if (join_pid1_mnt(procfd) != 0) {
                sleep(1);
                continue;
            }
            joined = 1;
            if (kfd >= 0) {
                const char *msg = "kukui-android phase3 wifi mnt\n";
                write_all(kfd, msg, strlen(msg));
            }
        }
        shfd = openat(procfd, "1/root/system/bin/sh", O_RDONLY | O_CLOEXEC);
        kofd = openat(procfd, "1/root/vendor/lib/modules/ath10k_sdio.ko",
                      O_RDONLY | O_CLOEXEC);
        if (shfd >= 0 && kofd >= 0) {
            close(shfd);
            close(kofd);
            rootfd = openat(procfd, "1/root", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
            if (rootfd >= 0 && fchdir(rootfd) == 0 && chroot(".") == 0) {
                close(rootfd);
                return 0;
            }
            if (rootfd >= 0)
                close(rootfd);
        } else {
            if (shfd >= 0)
                close(shfd);
            if (kofd >= 0)
                close(kofd);
        }
        sleep(1);
    }
    return -1;
}

/* Runs after the parent has exec'd Android init. The script bytes are
 * already in memory, because the ramdisk file is gone by then. */
static void wifi_child(char *script, size_t len, int procfd, int kfd) {
    int fd, waited, sp[2], sh;

    for (fd = 3; fd < 64; fd++) {
        if (fd != procfd && fd != kfd)
            close(fd);
    }
    if (enter_android_root(procfd, kfd) != 0) {
        if (kfd >= 0) {
            const char *msg = "kukui-android phase3 wifi root timeout\n";
            write_all(kfd, msg, strlen(msg));
        }
        _exit(0);
    }
    close(procfd);
    if (kfd >= 0) {
        const char *msg = "kukui-android phase3 wifi root\n";
        write_all(kfd, msg, strlen(msg));
        close(kfd);
    }
    kmsg("kukui-android phase3 wifi root\n");
    for (waited = 0; waited < 120; waited++) {
        if (access("/vendor/lib/modules/ath10k_sdio.ko", R_OK) == 0 &&
            access("/dev/kmsg", W_OK) == 0)
            break;
        sleep(1);
    }
    if (pipe(sp) != 0)
        _exit(0);
    sh = fork();
    if (sh < 0)
        _exit(0);
    if (sh == 0) {
        if (dup2(sp[0], STDIN_FILENO) < 0)
            _exit(1);
        if (sp[0] != STDIN_FILENO)
            close(sp[0]);
        close(sp[1]);
        /* /system/bin/sh needs /system/bin/linker64, a symlink into the
         * runtime APEX. That mount is not up at the chroot, so one exec
         * returns ENOENT and the script never starts. */
        for (waited = 0; waited < 180; waited++) {
            execl("/system/bin/sh", "sh", "-", (char *)NULL);
            if (waited == 0) {
                char msg[64];
                snprintf(msg, sizeof(msg),
                         "kukui-android phase3 wifi sh %d\n", errno);
                kmsg(msg);
            }
            sleep(1);
        }
        kmsg("kukui-android phase3 wifi sh timeout\n");
        _exit(1);
    }
    close(sp[0]);
    write_all(sp[1], script, len);
    close(sp[1]);
    _exit(0);
}

static void start_wifi_reprobe(void) {
    char *script = NULL;
    size_t len = 0;
    int procfd, kfd;
    pid_t child;

    if (read_alloc(WIFI_SCRIPT, &script, &len) != 0) {
        kmsg("kukui-android phase3 no wifi reprobe script\n");
        return;
    }
    procfd = open("/kukui-proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (procfd < 0) {
        free(script);
        kmsg("kukui-android phase3 wifi proc failed\n");
        return;
    }
    /* Opened before the parent detaches /dev, so a timeout can still be logged. */
    kfd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    child = fork();
    if (child < 0) {
        close(procfd);
        if (kfd >= 0)
            close(kfd);
        free(script);
        kmsg("kukui-android phase3 wifi fork failed\n");
        return;
    }
    if (child == 0)
        wifi_child(script, len, procfd, kfd);
    close(procfd);
    if (kfd >= 0)
        close(kfd);
    free(script);
}

int main(void) {
    char boot[64], super[64];
    int waited;

    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mkdir("/kukui-proc", 0755);
    mkdir("/kukui-sys", 0755);
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

    start_wifi_reprobe();

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
