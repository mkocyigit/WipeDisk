#include "include/wd_disk_shim.h"

#include <sys/ioctl.h>
#include <sys/disk.h>

int wd_block_size(int fd, uint32_t *out) {
    return ioctl(fd, DKIOCGETBLOCKSIZE, out);
}

int wd_block_count(int fd, uint64_t *out) {
    return ioctl(fd, DKIOCGETBLOCKCOUNT, out);
}

int wd_is_writable(int fd, uint32_t *out) {
    return ioctl(fd, DKIOCISWRITABLE, out);
}
