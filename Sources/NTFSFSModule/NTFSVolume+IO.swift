import Foundation
import FSKit
import CNTFS

/// Dosya iceriginin okunmasi ve yazilmasi.
///
/// NTFS'te dosya icerigi, inode'un adsiz `$DATA` oznitelididir. libntfs-3g bu
/// oznitelik uzerinde konum bazli okuma/yazma sunar; sikistirilmis ve seyrek
/// dosyalari da kendisi ele alir.
@available(macOS 15.4, *)
extension NTFSVolume: FSVolume.ReadWriteOperations {

    /// Bir ogenin adsiz $DATA oznitelidini acar.
    private func openData(
        _ item: FSItem
    ) -> UnsafeMutablePointer<ntfs_attr>? {
        guard let inode = (item as? NTFSItem)?.inode else { return nil }
        return ntfs_attr_open(inode, AT_DATA, nil, 0)
    }

    func read(
        from item: FSItem,
        at offset: off_t,
        length: Int,
        into buffer: FSMutableFileDataBuffer,
        replyHandler reply: @escaping (Int, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let attribute = self.openData(item) else {
                reply(0, fs_errorForPOSIXError(EIO))
                return
            }
            defer { ntfs_attr_close(attribute) }

            let read = buffer.withUnsafeMutableBytes { raw -> Int64 in
                let count = Swift.min(length, raw.count)
                return ntfs_attr_pread(
                    attribute, Int64(offset), Int64(count), raw.baseAddress
                )
            }

            if read < 0 {
                reply(0, fs_errorForPOSIXError(errno))
            } else {
                reply(Int(read), nil)
            }
        }
    }

    func write(
        contents: Data,
        to item: FSItem,
        at offset: off_t,
        replyHandler reply: @escaping (Int, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let ntfsItem = item as? NTFSItem,
                  let attribute = self.openData(item)
            else {
                reply(0, fs_errorForPOSIXError(EIO))
                return
            }
            defer { ntfs_attr_close(attribute) }

            let written = contents.withUnsafeBytes { raw -> Int64 in
                ntfs_attr_pwrite(
                    attribute, Int64(offset), Int64(raw.count), raw.baseAddress
                )
            }

            if written < 0 {
                reply(0, fs_errorForPOSIXError(errno))
                return
            }
            // Boyut ve zaman damgasi degistigi icin inode kirli isaretlenir;
            // gercek yazma senkronizasyonda diske iner.
            if let inode = ntfsItem.inode {
                wd_ntfs_mark_dirty(inode)
            }
            reply(Int(written), nil)
        }
    }
}

/// Ac/kapat. libntfs-3g bir dosyayi "acik tutma" kavramina sahip degil —
/// inode zaten `lookupItem` sirasinda aciliyor ve `reclaimItem`e kadar duruyor.
/// Bu yuzden burada yapilacak is, yazma kipinde salt okunur birimi reddetmek.
@available(macOS 15.4, *)
extension NTFSVolume: FSVolume.OpenCloseOperations {

    func openItem(
        _ item: FSItem,
        modes: FSVolume.OpenModes,
        replyHandler reply: @escaping (Error?) -> Void
    ) {
        if modes.contains(.write), !device.isWritable {
            reply(fs_errorForPOSIXError(EROFS))
            return
        }
        reply(nil)
    }

    func closeItem(
        _ item: FSItem,
        modes: FSVolume.OpenModes,
        replyHandler reply: @escaping (Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            // Yazma bitmis olabilir; inode'u diske indir.
            if let inode = (item as? NTFSItem)?.inode {
                ntfs_inode_sync(inode)
            }
            reply(nil)
        }
    }
}
