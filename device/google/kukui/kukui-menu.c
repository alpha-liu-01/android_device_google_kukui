/*
 * Depthcharge boots this as PID 1. Draw two choices on the panel and
 * Ask depthcharge to boot the selected kernel slot once. kexec on
 * this board leaves both systems on a black panel.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <linux/reboot.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define RELEASE "6.18.28-mt81-kukui2"
#define MODDIR "/lib/modules/" RELEASE

static void kmsg(const char *text) {
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        size_t len = strlen(text);
        while (len) {
            ssize_t n = write(fd, text, len);
            if (n < 0)
                break;
            text += n;
            len -= (size_t)n;
        }
        close(fd);
    }
}

static int load_module(const char *name) {
    char path[160];
    int fd;
    snprintf(path, sizeof(path), MODDIR "/%s", name);
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    if (syscall(__NR_finit_module, fd, "", 0) != 0 && errno != EEXIST) {
        close(fd);
        return -1;
    }
    close(fd);
    return 0;
}

static int read_text(const char *path, char *buf, size_t len) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    ssize_t n;
    if (fd < 0)
        return -1;
    n = read(fd, buf, len - 1);
    close(fd);
    if (n < 0)
        return -1;
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
        n--;
    buf[n] = 0;
    return 0;
}

static int find_emmc_part(const char *partname, char *out, size_t outlen) {
    char want[64];
    snprintf(want, sizeof(want), "PARTNAME=%s", partname);
    char dirpath[] = "/sys/class/block";
    int dfd = open(dirpath, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    char buf[4096];
    if (dfd < 0)
        return -1;
    for (;;) {
        ssize_t n = syscall(SYS_getdents64, dfd, buf, sizeof(buf));
        ssize_t off;
        if (n <= 0)
            break;
        for (off = 0; off < n;) {
            struct linux_dirent64 {
                unsigned long long d_ino;
                long long d_off;
                unsigned short d_reclen;
                unsigned char d_type;
                char d_name[];
            } *ent = (void *)(buf + off);
            char path[192], link[512], uevent[512];
            ssize_t ln;
            off += ent->d_reclen;
            if (ent->d_name[0] == '.')
                continue;
            snprintf(path, sizeof(path), "/sys/class/block/%s", ent->d_name);
            ln = readlink(path, link, sizeof(link) - 1);
            if (ln < 0)
                continue;
            link[ln] = 0;
            if (strstr(link, "11230000.mmc") == NULL)
                continue;
            snprintf(path, sizeof(path), "/sys/class/block/%s/uevent", ent->d_name);
            if (read_text(path, uevent, sizeof(uevent)) != 0)
                continue;
            if (strstr(uevent, want) == NULL)
                continue;
            snprintf(out, outlen, "/dev/%s", ent->d_name);
            close(dfd);
            return 0;
        }
    }
    close(dfd);
    return -1;
}

static void write_sysfs(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0)
        return;
    if (write(fd, text, strlen(text)) < 0)
        kmsg("kukui-menu sysfs write failed\n");
    close(fd);
}

/* fbcon rotates its text onto this same framebuffer and keeps the
 * keyboard. Graphics mode plus unbinding the VT stops both. */
static void quiet_console(void) {
    int fd;
    syscall(__NR_syslog, 8, NULL, 1);
    syscall(__NR_syslog, 6, NULL, 0);
    write_sysfs("/proc/sys/kernel/printk", "1 1 1 1\n");
    fd = open("/dev/tty0", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (fd < 0)
        fd = open("/dev/console", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (fd >= 0) {
        if (ioctl(fd, KDSETMODE, KD_GRAPHICS) != 0)
            kmsg("kukui-menu KD_GRAPHICS failed\n");
        close(fd);
    }
    write_sysfs("/sys/class/vtconsole/vtcon1/bind", "0");
    write_sysfs("/sys/class/vtconsole/vtcon0/bind", "0");
}

static void backlight(void) {
    int fd = open("/sys/class/backlight/backlight_lcd0/brightness", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        if (write(fd, "700", 3) < 0)
            kmsg("kukui-menu backlight write failed\n");
        close(fd);
    }
}

struct screen {
    int fd;
    uint32_t *pix;
    int xres;
    int yres;
    int stride;
    size_t maplen;
};

static int open_fb(struct screen *s) {
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    int i;
    memset(s, 0, sizeof(*s));
    for (i = 0; i < 30; i++) {
        s->fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
        if (s->fd >= 0)
            break;
        sleep(1);
    }
    if (s->fd < 0)
        return -1;
    if (ioctl(s->fd, FBIOGET_VSCREENINFO, &var) != 0 ||
        ioctl(s->fd, FBIOGET_FSCREENINFO, &fix) != 0)
        return -1;
    s->xres = (int)var.xres;
    s->yres = (int)var.yres;
    s->stride = (int)fix.line_length / 4;
    s->maplen = (size_t)fix.line_length * var.yres;
    s->pix = mmap(NULL, s->maplen, PROT_READ | PROT_WRITE, MAP_SHARED, s->fd, 0);
    if (s->pix == MAP_FAILED)
        return -1;
    return 0;
}

/* Logical landscape. The panel scans portrait, so rotate 90 degrees
 * clockwise into the framebuffer. */
static void put(struct screen *s, int lx, int ly, int lw, int lh, uint32_t color) {
    int x, y;
    int portrait = s->yres > s->xres;
    if (lx < 0 || ly < 0 || lx >= lw || ly >= lh)
        return;
    if (portrait) {
        x = ly * s->xres / lh;
        y = (lw - 1 - lx) * s->yres / lw;
    } else {
        x = lx * s->xres / lw;
        y = ly * s->yres / lh;
    }
    if (x >= 0 && y >= 0 && x < s->xres && y < s->yres)
        s->pix[y * s->stride + x] = color;
}

static void fill(struct screen *s, int x, int y, int w, int h, int lw, int lh, uint32_t color) {
    int yy, xx;
    for (yy = y; yy < y + h; yy++)
        for (xx = x; xx < x + w; xx++)
            put(s, xx, yy, lw, lh, color);
}

/* 5x7 glyphs for the two labels. */
static const uint8_t GLYPH_A[7] = {0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11};
static const uint8_t GLYPH_N[7] = {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11};
static const uint8_t GLYPH_D[7] = {0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e};
static const uint8_t GLYPH_R[7] = {0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11};
static const uint8_t GLYPH_O[7] = {0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e};
static const uint8_t GLYPH_I[7] = {0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x1f};
static const uint8_t GLYPH_L[7] = {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f};
static const uint8_t GLYPH_U[7] = {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e};
static const uint8_t GLYPH_X[7] = {0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11};
static const uint8_t GLYPH_C[7] = {0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e};
static const uint8_t GLYPH_E[7] = {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f};
static const uint8_t GLYPH_F[7] = {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10};
static const uint8_t GLYPH_G[7] = {0x0e, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0e};
static const uint8_t GLYPH_H[7] = {0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11};
static const uint8_t GLYPH_P[7] = {0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10};
static const uint8_t GLYPH_S[7] = {0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e};
static const uint8_t GLYPH_T[7] = {0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04};
static const uint8_t GLYPH_V[7] = {0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04};
static const uint8_t GLYPH_W[7] = {0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0a};
static const uint8_t GLYPH_PLUS[7] = {0x04, 0x04, 0x1f, 0x04, 0x04, 0x00, 0x00};
static const uint8_t GLYPH_MINUS[7] = {0x00, 0x00, 0x1f, 0x00, 0x00, 0x00, 0x00};

static const uint8_t *glyph_for(char c) {
    switch (c) {
    case 'A': return GLYPH_A;
    case 'C': return GLYPH_C;
    case 'D': return GLYPH_D;
    case 'E': return GLYPH_E;
    case 'F': return GLYPH_F;
    case 'G': return GLYPH_G;
    case 'H': return GLYPH_H;
    case 'I': return GLYPH_I;
    case 'L': return GLYPH_L;
    case 'N': return GLYPH_N;
    case 'O': return GLYPH_O;
    case 'P': return GLYPH_P;
    case 'R': return GLYPH_R;
    case 'S': return GLYPH_S;
    case 'T': return GLYPH_T;
    case 'U': return GLYPH_U;
    case 'V': return GLYPH_V;
    case 'W': return GLYPH_W;
    case 'X': return GLYPH_X;
    case '+': return GLYPH_PLUS;
    case '-': return GLYPH_MINUS;
    default: return NULL;
    }
}

static void glyph(struct screen *s, int x, int y, int scale, int lw, int lh,
                  const uint8_t *rows, uint32_t color);

static void text(struct screen *s, int x, int y, int scale, const char *str, uint32_t color) {
    int step = scale * 6;
    for (; *str; str++, x += step) {
        const uint8_t *rows = glyph_for(*str);
        if (rows)
            glyph(s, x, y, scale, 1920, 1200, rows, color);
    }
}

static void glyph(struct screen *s, int x, int y, int scale, int lw, int lh,
                  const uint8_t *rows, uint32_t color) {
    int row, col;
    for (row = 0; row < 7; row++) {
        for (col = 0; col < 5; col++) {
            if (rows[row] & (1 << (4 - col)))
                fill(s, x + col * scale, y + row * scale, scale, scale, lw, lh, color);
        }
    }
}

static void fill_native(struct screen *s, uint32_t color) {
    int y, x;
    for (y = 0; y < s->yres; y++) {
        uint32_t *row = s->pix + (size_t)y * (size_t)s->stride;
        for (x = 0; x < s->xres; x++)
            row[x] = color;
    }
}

static void draw(struct screen *s, int selected) {
    const int lw = 1920, lh = 1200;
    const uint8_t *android[] = {GLYPH_A, GLYPH_N, GLYPH_D, GLYPH_R, GLYPH_O, GLYPH_I, GLYPH_D};
    const uint8_t *linuxg[] = {GLYPH_L, GLYPH_I, GLYPH_N, GLYPH_U, GLYPH_X};
    int i;
    uint32_t bg = 0xff1a202c;
    uint32_t on = 0xff2b6cb0;
    uint32_t off = 0xff2d3748;
    uint32_t fg = 0xfff7fafc;
    fill_native(s, bg);
    fill(s, 160, 180, 740, 840, lw, lh, selected == 0 ? on : off);
    fill(s, 1020, 180, 740, 840, lw, lh, selected == 1 ? on : off);
    for (i = 0; i < 7; i++)
        glyph(s, 250 + i * 90, 520, 12, lw, lh, android[i], fg);
    for (i = 0; i < 5; i++)
        glyph(s, 1180 + i * 90, 520, 12, lw, lh, linuxg[i], fg);
    text(s, 400, 760, 10, "VOL+", fg);
    text(s, 1260, 760, 10, "VOL-", fg);
    text(s, 350, 1080, 7, "TOUCH OR PRESS AGAIN OR POWER", fg);
}

static int touch_logical(struct screen *s, int px, int py, int *lx, int *ly) {
    if (s->yres > s->xres) {
        *lx = (s->yres - 1 - py) * 1920 / s->yres;
        *ly = px * 1200 / s->xres;
    } else {
        *lx = px * 1920 / s->xres;
        *ly = py * 1200 / s->yres;
    }
    return *lx >= 0 && *ly >= 0;
}

static int choice_at(int lx, int ly) {
    if (ly < 180 || ly > 1020)
        return -1;
    if (lx >= 160 && lx < 900)
        return 0;
    if (lx >= 1020 && lx < 1760)
        return 1;
    return -1;
}

struct pointer {
    int fd;
    int xmin, xmax, ymin, ymax;
    int x, y;
    int down;
};

static int map_axis(int v, int min, int max, int length) {
    if (max <= min || length <= 1)
        return v;
    if (v < min)
        v = min;
    if (v > max)
        v = max;
    return (int)((long)(v - min) * (length - 1) / (max - min));
}

static void read_axis(int fd, int code, int *min, int *max) {
    struct input_absinfo abs;
    if (ioctl(fd, EVIOCGABS(code), &abs) != 0)
        return;
    if (abs.maximum <= abs.minimum)
        return;
    *min = abs.minimum;
    *max = abs.maximum;
}

/* evdev nodes show up after i2c-hid and the dock keyboard probe.
 * Grabbing the device keeps the VT from echoing the same keys. */
static void scan_inputs(struct pointer *ps, int *n) {
    int i;
    for (i = 0; i < 64; i++) {
        char path[64];
        int fd, idx;
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
        if (fd < 0)
            continue;
        for (idx = 0; idx < *n; idx++) {
            struct stat a, b;
            if (fstat(fd, &a) == 0 && fstat(ps[idx].fd, &b) == 0 &&
                a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
                close(fd);
                fd = -1;
                break;
            }
        }
        if (fd < 0)
            continue;
        if (*n >= 32) {
            close(fd);
            break;
        }
        memset(&ps[*n], 0, sizeof(ps[*n]));
        ps[*n].fd = fd;
        read_axis(fd, ABS_MT_POSITION_X, &ps[*n].xmin, &ps[*n].xmax);
        if (ps[*n].xmax <= ps[*n].xmin)
            read_axis(fd, ABS_X, &ps[*n].xmin, &ps[*n].xmax);
        read_axis(fd, ABS_MT_POSITION_Y, &ps[*n].ymin, &ps[*n].ymax);
        if (ps[*n].ymax <= ps[*n].ymin)
            read_axis(fd, ABS_Y, &ps[*n].ymin, &ps[*n].ymax);
        if (ioctl(fd, EVIOCGRAB, 1) != 0)
            kmsg("kukui-menu grab failed\n");
        (*n)++;
    }
}

/* kexec on this board reaches neither Android nor Linux: the panel
 * stays black and the backlight stays off. Depthcharge already boots
 * both kernel slots. Hand it a one-shot priority instead. The chosen
 * slot is priority 15, tries 1, not successful, so firmware consumes
 * the try as it jumps. The menu drops to priority 14 and stays
 * successful, which is what the next power-on boots. */
static uint32_t crc32_le(const void *data, size_t len) {
    static uint32_t table[256];
    static int ready;
    const uint8_t *p = data;
    uint32_t c = 0xffffffffu;
    size_t i;
    if (!ready) {
        for (i = 0; i < 256; i++) {
            uint32_t v = (uint32_t)i;
            int b;
            for (b = 0; b < 8; b++)
                v = (v & 1u) ? (0xedb88320u ^ (v >> 1)) : (v >> 1);
            table[i] = v;
        }
        ready = 1;
    }
    for (i = 0; i < len; i++)
        c = table[(c ^ p[i]) & 0xffu] ^ (c >> 8);
    return c ^ 0xffffffffu;
}

static void attr_bit(uint8_t *entry, int bit, int on) {
    uint64_t attr;
    memcpy(&attr, entry + 48, sizeof(attr));
    if (on)
        attr |= (uint64_t)1 << bit;
    else
        attr &= ~((uint64_t)1 << bit);
    memcpy(entry + 48, &attr, sizeof(attr));
}

static int entry_named(const uint8_t *entry, const char *name) {
    size_t i;
    for (i = 0; name[i]; i++) {
        uint16_t c;
        if (i >= 36)
            return 0;
        memcpy(&c, entry + 56 + i * 2, sizeof(c));
        if (c != (uint8_t)name[i])
            return 0;
    }
    {
        uint16_t end;
        memcpy(&end, entry + 56 + i * 2, sizeof(end));
        return end == 0;
    }
}

static void stamp_header(uint8_t *sector, uint32_t entry_crc) {
    uint32_t header_size, crc;
    memcpy(&header_size, sector + 12, sizeof(header_size));
    if (header_size < 92 || header_size > 512)
        header_size = 92;
    memcpy(sector + 88, &entry_crc, sizeof(entry_crc));
    memset(sector + 16, 0, 4);
    crc = crc32_le(sector, header_size);
    memcpy(sector + 16, &crc, sizeof(crc));
}

static int boot_slot(const char *target) {
    uint8_t primary[512], backup[512];
    uint8_t *entries = NULL;
    uint32_t entry_count, entry_size, entry_crc, header_size;
    uint64_t alt_lba, entry_lba, backup_entry_lba;
    int fd = -1, rc = -1, logical;
    char link[256];
    ssize_t n;
    uint32_t i;
    int target_at = -1, menu_at = -1;
    n = readlink("/sys/class/block/mmcblk0", link, sizeof(link) - 1);
    if (n < 0)
        return -1;
    link[n] = 0;
    if (strstr(link, "11230000.mmc") == NULL)
        return -1;
    logical = 0;
    {
        char text[16];
        if (read_text("/sys/class/block/mmcblk0/queue/logical_block_size", text, sizeof(text)) == 0)
            logical = atoi(text);
    }
    if (logical != 512)
        return -1;
    fd = open("/dev/mmcblk0", O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return -1;
    if (pread(fd, primary, sizeof(primary), 512) != (ssize_t)sizeof(primary))
        goto out;
    if (memcmp(primary, "EFI PART", 8) != 0)
        goto out;
    {
        uint8_t copy[512];
        uint32_t stored, calc;
        memcpy(copy, primary, sizeof(copy));
        memcpy(&stored, copy + 16, sizeof(stored));
        memcpy(&header_size, copy + 12, sizeof(header_size));
        if (header_size < 92 || header_size > 512)
            goto out;
        memset(copy + 16, 0, 4);
        calc = crc32_le(copy, header_size);
        if (calc != stored)
            goto out;
    }
    memcpy(&header_size, primary + 12, sizeof(header_size));
    memcpy(&alt_lba, primary + 32, sizeof(alt_lba));
    memcpy(&entry_lba, primary + 72, sizeof(entry_lba));
    memcpy(&entry_count, primary + 80, sizeof(entry_count));
    memcpy(&entry_size, primary + 84, sizeof(entry_size));
    memcpy(&entry_crc, primary + 88, sizeof(entry_crc));
    if (header_size != 92 || entry_size != 128 || entry_count < 5 || entry_count > 128)
        goto out;
    if (entry_lba != 2)
        goto out;
    entries = malloc((size_t)entry_count * entry_size);
    if (!entries)
        goto out;
    if (pread(fd, entries, (size_t)entry_count * entry_size, (off_t)entry_lba * 512) !=
        (ssize_t)((size_t)entry_count * entry_size))
        goto out;
    if (crc32_le(entries, (size_t)entry_count * entry_size) != entry_crc)
        goto out;
    if (pread(fd, backup, sizeof(backup), (off_t)alt_lba * 512) != (ssize_t)sizeof(backup))
        goto out;
    if (memcmp(backup, "EFI PART", 8) != 0)
        goto out;
    {
        uint8_t copy[512];
        uint32_t stored, calc, bsize;
        memcpy(copy, backup, sizeof(copy));
        memcpy(&stored, copy + 16, sizeof(stored));
        memcpy(&bsize, copy + 12, sizeof(bsize));
        if (bsize != header_size)
            goto out;
        memset(copy + 16, 0, 4);
        calc = crc32_le(copy, bsize);
        if (calc != stored)
            goto out;
    }
    memcpy(&backup_entry_lba, backup + 72, sizeof(backup_entry_lba));
    if (backup_entry_lba == entry_lba ||
        backup_entry_lba * 512 + (uint64_t)entry_count * entry_size != alt_lba * 512)
        goto out;
    for (i = 0; i < entry_count; i++) {
        uint8_t *entry = entries + (size_t)i * entry_size;
        if (entry_named(entry, target))
            target_at = (int)i;
        else if (entry_named(entry, "menu_kernel"))
            menu_at = (int)i;
    }
    if (target_at < 0 || menu_at < 0 || target_at == menu_at)
        goto out;
    for (i = 48; i <= 51; i++)
        attr_bit(entries + (size_t)target_at * entry_size, (int)i, 1);
    attr_bit(entries + (size_t)target_at * entry_size, 52, 1);
    attr_bit(entries + (size_t)target_at * entry_size, 53, 0);
    attr_bit(entries + (size_t)target_at * entry_size, 54, 0);
    attr_bit(entries + (size_t)target_at * entry_size, 55, 0);
    attr_bit(entries + (size_t)target_at * entry_size, 56, 0);
    attr_bit(entries + (size_t)menu_at * entry_size, 48, 0);
    attr_bit(entries + (size_t)menu_at * entry_size, 49, 1);
    attr_bit(entries + (size_t)menu_at * entry_size, 50, 1);
    attr_bit(entries + (size_t)menu_at * entry_size, 51, 1);
    for (i = 52; i <= 56; i++)
        attr_bit(entries + (size_t)menu_at * entry_size, (int)i, 1);
    entry_crc = crc32_le(entries, (size_t)entry_count * entry_size);
    if (pwrite(fd, entries, (size_t)entry_count * entry_size, (off_t)backup_entry_lba * 512) !=
        (ssize_t)((size_t)entry_count * entry_size))
        goto out;
    stamp_header(backup, entry_crc);
    if (pwrite(fd, backup, sizeof(backup), (off_t)alt_lba * 512) != (ssize_t)sizeof(backup))
        goto out;
    if (pwrite(fd, entries, (size_t)entry_count * entry_size, (off_t)entry_lba * 512) !=
        (ssize_t)((size_t)entry_count * entry_size))
        goto out;
    stamp_header(primary, entry_crc);
    if (pwrite(fd, primary, sizeof(primary), 512) != (ssize_t)sizeof(primary))
        goto out;
    if (fsync(fd) != 0)
        goto out;
    sync();
    close(fd);
    fd = -1;
    free(entries);
    entries = NULL;
    rc = (int)syscall(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
                      LINUX_REBOOT_CMD_RESTART, NULL);
    return rc == 0 ? 0 : -1;
out:
    if (fd >= 0)
        close(fd);
    free(entries);
    return rc;
}

static void touch_up(struct screen *screen, struct pointer *p, int *selected, int *got) {
    int px, py, lx, ly, choice;
    if (!p->down)
        return;
    p->down = 0;
    px = map_axis(p->x, p->xmin, p->xmax, screen->xres);
    py = map_axis(p->y, p->ymin, p->ymax, screen->yres);
    if (!touch_logical(screen, px, py, &lx, &ly))
        return;
    choice = choice_at(lx, ly);
    if (choice < 0)
        return;
    *selected = choice;
    *got = 1;
}

int main(void) {
    struct screen screen;
    struct pointer inputs[32];
    char part[80], boot[80], msg[80];
    int waited, ninputs = 0, i, selected = -1, ticks = 0;

    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    mkdir("/bootmenu", 0755);
    mkdir("/pmosboot", 0755);
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    kmsg("kukui-menu\n");
    quiet_console();
    load_module("evdev.ko");
    load_module("hid-multitouch.ko");
    load_module("hid-generic.ko");
    load_module("i2c-hid.ko");
    load_module("i2c-hid-of.ko");
    load_module("i2c-hid-of-goodix.ko");
    backlight();

    part[0] = 0;
    for (waited = 0; waited < 20 && part[0] == 0; waited++) {
        if (find_emmc_part("bootmenu", part, sizeof(part)) != 0)
            sleep(1);
    }
    if (part[0] == 0) {
        kmsg("kukui-menu no bootmenu partition\n");
        for (;;)
            sleep(3600);
    }
    if (mount(part, "/bootmenu", "ext4", MS_RDONLY, NULL) != 0) {
        kmsg("kukui-menu mount failed\n");
        for (;;)
            sleep(3600);
    }
    boot[0] = 0;
    if (find_emmc_part("pmOS_boot", boot, sizeof(boot)) != 0 ||
        mount(boot, "/pmosboot", "ext4", MS_RDONLY, NULL) != 0) {
        kmsg("kukui-menu no linux boot\n");
        for (;;)
            sleep(3600);
    }
    if (open_fb(&screen) != 0) {
        kmsg("kukui-menu no framebuffer\n");
        for (;;)
            sleep(3600);
    }
    snprintf(msg, sizeof(msg), "kukui-menu fb %dx%d\n", screen.xres, screen.yres);
    kmsg(msg);
    quiet_console();
    draw(&screen, selected);
    for (;;) {
        int got = 0;
        int before = ninputs;
        if ((ticks++ % 10) == 0)
            scan_inputs(inputs, &ninputs);
        if (ninputs != before) {
            snprintf(msg, sizeof(msg), "kukui-menu inputs %d\n", ninputs);
            kmsg(msg);
        }
        for (i = 0; i < ninputs; i++) {
            struct input_event ev;
            while (read(inputs[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
                if (ev.type == EV_KEY && ev.value == 1 && ev.code != BTN_TOUCH) {
                    /* Volume and power are on the chassis, via the EC.
                     * The dock keyboard is optional. A second press of the
                     * same volume key starts that system. */
                    if (ev.code == KEY_VOLUMEUP) {
                        if (selected == 0)
                            got = 1;
                        else
                            selected = 0;
                    } else if (ev.code == KEY_VOLUMEDOWN) {
                        if (selected == 1)
                            got = 1;
                        else
                            selected = 1;
                    } else if (ev.code == KEY_POWER || ev.code == KEY_ENTER ||
                               ev.code == KEY_KPENTER || ev.code == KEY_SPACE) {
                        if (selected < 0)
                            selected = 0;
                        else
                            got = 1;
                    } else if (ev.code == KEY_A || ev.code == KEY_LEFT ||
                               ev.code == KEY_1 || ev.code == KEY_UP)
                        selected = 0;
                    else if (ev.code == KEY_L || ev.code == KEY_RIGHT ||
                             ev.code == KEY_2 || ev.code == KEY_DOWN)
                        selected = 1;
                    else
                        continue;
                    draw(&screen, selected);
                } else if (ev.type == EV_ABS) {
                    if (ev.code == ABS_MT_POSITION_X || ev.code == ABS_X)
                        inputs[i].x = ev.value;
                    else if (ev.code == ABS_MT_POSITION_Y || ev.code == ABS_Y)
                        inputs[i].y = ev.value;
                    else if (ev.code == ABS_MT_TRACKING_ID && ev.value < 0)
                        touch_up(&screen, &inputs[i], &selected, &got);
                    else if (ev.code == ABS_MT_TRACKING_ID)
                        inputs[i].down = 1;
                } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
                    if (ev.value)
                        inputs[i].down = 1;
                    else
                        touch_up(&screen, &inputs[i], &selected, &got);
                }
            }
        }
        if (got && selected >= 0) {
            int rc;
            kmsg(selected == 0 ? "kukui-menu android\n" : "kukui-menu linux\n");
            draw(&screen, selected);
            rc = boot_slot(selected == 0 ? "android_kernel" : "pmOS_kernel");
            if (rc != 0) {
                int err = errno;
                snprintf(msg, sizeof(msg), "kukui-menu boot failed %d\n", err);
                kmsg(msg);
                text(&screen, 780, 980, 8, "FAILED", 0xffff6b6b);
            }
            got = 0;
        }
        usleep(20000);
    }
}
