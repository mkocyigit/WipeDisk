// libntfs-3g'yi Swift'e acan semsiye baslik.
//
// ntfs-3g basliklari HAVE_CONFIG_H bekler ve kendi tam sayi takma adlarini
// (s64, u32 …) tanimlar; buradan tek noktadan iceri alinirlar.
#ifndef WD_NTFS_H
#define WD_NTFS_H

#include <ntfs-3g/volume.h>
#include <ntfs-3g/inode.h>
#include <ntfs-3g/attrib.h>
#include <ntfs-3g/dir.h>
#include <ntfs-3g/misc.h>
#include <ntfs-3g/security.h>

/// Bir dizin girdisini Swift'e tasiyan duz kayit.
///
/// `ntfs_readdir` degisken imzali bir geri cagirma kullaniyor ve Swift C
/// degisken parametreli fonksiyonlari cagiramiyor; toplama isi C tarafinda
/// yapilip sonuc bu yapiyla veriliyor.
typedef struct {
    char     name[768];   // UTF-8, sonu sifirli
    uint64_t inode;
    int      isDirectory;
} wd_ntfs_dirent;

/// Dizini okur ve girdileri cagiranin tamponuna doldurur.
/// Donen deger yazilan girdi sayisi, hata durumunda -1.
int wd_ntfs_readdir(ntfs_inode *dir, wd_ntfs_dirent *out, int capacity);

#endif /* WD_NTFS_H */

/* --- FSKit destekli aygit katmani ------------------------------------------
 *
 * Sandbox'li bir FSKit uzantisi /dev/diskNsM'i dogrudan acamaz; FSKit bunun
 * yerine FSBlockDeviceResource uzerinden okuma/yazma sunar. libntfs-3g'nin
 * takilabilir aygit katmani sayesinde kutuphanenin butun G/C'si oraya
 * yonlendirilebiliyor — boylece aygit acma yetkisi hic gerekmiyor.
 */

typedef struct {
    void *ctx;   /* Swift tarafindaki birim nesnesi */
    long long (*pread)(void *ctx, void *buf, long long count, long long offset);
    long long (*pwrite)(void *ctx, const void *buf, long long count, long long offset);
    int       (*sync)(void *ctx);
    long long (*size)(void *ctx);
} wd_ntfs_io;

/// Verilen geri cagirmalari kullanan bir ntfs aygiti olusturur.
/// Basarisizlikta NULL doner. Aygit `ntfs_device_free` ile birakilir.
struct ntfs_device *wd_ntfs_device_new(const char *name, const wd_ntfs_io *io);

/// `NInoSetDirty` bir makro oldugundan Swift'ten cagrilamaz.
void wd_ntfs_mark_dirty(ntfs_inode *ni);
