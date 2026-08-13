#ifndef WD_DISK_SHIM_H
#define WD_DISK_SHIM_H

#include <stdint.h>

/// Aygitin mantiksal blok boyutu (bayt). Basarida 0, hatada -1 (errno dolu).
int wd_block_size(int fd, uint32_t *out);

/// Aygittaki toplam blok sayisi. Basarida 0, hatada -1 (errno dolu).
int wd_block_count(int fd, uint64_t *out);

/// Aygit yazilabilir mi (donanim yazma korumasi vb.). Basarida 0, hatada -1.
int wd_is_writable(int fd, uint32_t *out);

#endif /* WD_DISK_SHIM_H */
