#include "include/wd_ntfs.h"
#include <string.h>
#include <stdlib.h>

typedef struct {
    wd_ntfs_dirent *out;
    int capacity;
    int count;
} wd_collect;

/// `ntfs_readdir`in cagirdigi filldir. UTF-16 adi UTF-8'e cevirip kaydeder.
static int wd_fill(void *dirent, const ntfschar *name, const int name_len,
                   const int name_type, const s64 pos, const MFT_REF mref,
                   const unsigned dt_type)
{
    (void)pos;
    wd_collect *ctx = (wd_collect *)dirent;

    // DOS kisa adlari atlanir; ayni girdi uzun adiyla zaten geliyor.
    if (name_type == FILE_NAME_DOS) return 0;
    if (ctx->count >= ctx->capacity) return -1;

    char *utf8 = NULL;
    int len = ntfs_ucstombs(name, name_len, &utf8, 0);
    if (len < 0 || utf8 == NULL) return 0;

    wd_ntfs_dirent *slot = &ctx->out[ctx->count];
    if ((size_t)len >= sizeof(slot->name)) {
        free(utf8);
        return 0;
    }
    memcpy(slot->name, utf8, (size_t)len);
    slot->name[len] = '\0';
    slot->inode = (uint64_t)MREF(mref);
    slot->isDirectory = (dt_type == NTFS_DT_DIR);
    ctx->count++;

    free(utf8);
    return 0;
}

int wd_ntfs_readdir(ntfs_inode *dir, wd_ntfs_dirent *out, int capacity)
{
    if (dir == NULL || out == NULL || capacity <= 0) return -1;

    wd_collect ctx = { .out = out, .capacity = capacity, .count = 0 };
    s64 pos = 0;
    if (ntfs_readdir(dir, &pos, &ctx, wd_fill) != 0) return -1;
    return ctx.count;
}

/* --- FSKit destekli aygit katmani --------------------------------------- */

#include <ntfs-3g/device.h>
#include <errno.h>
#include <sys/stat.h>

typedef struct {
    wd_ntfs_io io;
    long long  position;
} wd_dev_state;

static wd_dev_state *wd_state(struct ntfs_device *dev)
{
    return (wd_dev_state *)dev->d_private;
}

static int wd_dev_open(struct ntfs_device *dev, int flags)
{
    (void)flags;
    /* Kaynak FSKit tarafindan zaten acilmis durumda; burada yalnizca
       aygit "acik" olarak isaretlenir. */
    NDevSetOpen(dev);
    return 0;
}

static int wd_dev_close(struct ntfs_device *dev)
{
    NDevClearOpen(dev);
    return 0;
}

static s64 wd_dev_seek(struct ntfs_device *dev, s64 offset, int whence)
{
    wd_dev_state *st = wd_state(dev);
    long long base;

    switch (whence) {
    case SEEK_SET: base = 0; break;
    case SEEK_CUR: base = st->position; break;
    case SEEK_END: base = st->io.size(st->io.ctx); break;
    default: errno = EINVAL; return -1;
    }
    if (base + offset < 0) { errno = EINVAL; return -1; }
    st->position = base + offset;
    return st->position;
}

static s64 wd_dev_pread(struct ntfs_device *dev, void *buf, s64 count, s64 offset)
{
    wd_dev_state *st = wd_state(dev);
    return st->io.pread(st->io.ctx, buf, count, offset);
}

static s64 wd_dev_pwrite(struct ntfs_device *dev, const void *buf, s64 count, s64 offset)
{
    wd_dev_state *st = wd_state(dev);
    return st->io.pwrite(st->io.ctx, buf, count, offset);
}

static s64 wd_dev_read(struct ntfs_device *dev, void *buf, s64 count)
{
    wd_dev_state *st = wd_state(dev);
    s64 got = wd_dev_pread(dev, buf, count, st->position);
    if (got > 0) st->position += got;
    return got;
}

static s64 wd_dev_write(struct ntfs_device *dev, const void *buf, s64 count)
{
    wd_dev_state *st = wd_state(dev);
    s64 put = wd_dev_pwrite(dev, buf, count, st->position);
    if (put > 0) st->position += put;
    return put;
}

static int wd_dev_sync(struct ntfs_device *dev)
{
    wd_dev_state *st = wd_state(dev);
    return st->io.sync(st->io.ctx);
}

static int wd_dev_stat(struct ntfs_device *dev, struct stat *buf)
{
    wd_dev_state *st = wd_state(dev);
    memset(buf, 0, sizeof(*buf));
    buf->st_mode = S_IFBLK;
    buf->st_size = st->io.size(st->io.ctx);
    buf->st_blksize = 512;
    return 0;
}

static int wd_dev_ioctl(struct ntfs_device *dev, unsigned long request, void *argp)
{
    (void)dev; (void)request; (void)argp;
    /* Blok aygiti ioctl'leri FSKit uzerinden gerekmiyor; libntfs-3g bu
       cagrilarin basarisiz olmasini tolere ediyor. */
    errno = ENOTTY;
    return -1;
}

static struct ntfs_device_operations wd_dev_ops = {
    .open   = wd_dev_open,
    .close  = wd_dev_close,
    .seek   = wd_dev_seek,
    .read   = wd_dev_read,
    .write  = wd_dev_write,
    .pread  = wd_dev_pread,
    .pwrite = wd_dev_pwrite,
    .sync   = wd_dev_sync,
    .stat   = wd_dev_stat,
    .ioctl  = wd_dev_ioctl,
};

struct ntfs_device *wd_ntfs_device_new(const char *name, const wd_ntfs_io *io)
{
    if (name == NULL || io == NULL) { errno = EINVAL; return NULL; }

    wd_dev_state *st = calloc(1, sizeof(wd_dev_state));
    if (st == NULL) { errno = ENOMEM; return NULL; }
    st->io = *io;
    st->position = 0;

    struct ntfs_device *dev = ntfs_device_alloc(name, 0, &wd_dev_ops, st);
    if (dev == NULL) { free(st); return NULL; }
    return dev;
}

void wd_ntfs_mark_dirty(ntfs_inode *ni)
{
    if (ni != NULL) NInoSetDirty(ni);
}
