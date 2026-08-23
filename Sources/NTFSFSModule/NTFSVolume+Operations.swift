import Foundation
import FSKit
import CNTFS

/// Birim islemleri. Butun cagrilar `NTFSFileSystem.queue` uzerinde sirlanir:
/// libntfs-3g yeniden girise kapalidir.
@available(macOS 15.4, *)
extension NTFSVolume: FSVolume.Operations {

    // MARK: - Yol sinirlari

    /// NTFS'te bir dosyaya baglanabilecek sabit bag sayisi 1024'tur.
    var maximumLinkCount: Int { 1024 }
    /// Dosya adi en fazla 255 UTF-16 birimi.
    var maximumNameLength: Int { 255 }
    /// NTFS POSIX sahipligi tasimadigindan sahiplik degisimi anlamsiz.
    var restrictsOwnershipChanges: Bool { true }
    /// Uzun adlar kirpilmaz; ENAMETOOLONG dondurulur.
    var truncatesLongNames: Bool { false }

    // MARK: - Yetenekler ve istatistik

    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = FSVolume.SupportedCapabilities()
        capabilities.supportsHardLinks = true
        capabilities.supportsSymbolicLinks = false      // Reparse noktalari sonraki asama.
        capabilities.supportsPersistentObjectIDs = true // MFT kayit numarasi kalicidir.
        capabilities.caseFormat = .insensitiveCasePreserving
        capabilities.supportsSparseFiles = true
        return capabilities
    }

    var volumeStatistics: FSStatFSResult {
        let stats = FSStatFSResult(fileSystemTypeName: "ntfs")
        guard let volume else { return stats }

        let clusterSize = Int(volume.pointee.cluster_size)
        stats.blockSize = clusterSize
        stats.ioSize = clusterSize
        stats.totalBlocks = UInt64(volume.pointee.nr_clusters)
        let free = ntfs_volume_get_free_space(volume) == 0
            ? UInt64(bitPattern: volume.pointee.free_clusters)
            : 0
        stats.availableBlocks = free
        stats.freeBlocks = free
        return stats
    }

    // MARK: - Yasam dongusu

    func mount(options: FSTaskOptions, replyHandler reply: @escaping (Error?) -> Void) {
        NTFSFileSystem.queue.async {
            do {
                // Salt okunur istegi FSKit'ten gelebilir; gelmezse okuma-yazma acilir.
                try self.openVolume(readOnly: !self.device.isWritable)
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    func unmount(replyHandler reply: @escaping () -> Void) {
        NTFSFileSystem.queue.async {
            self.closeVolume()
            reply()
        }
    }

    func activate(
        options: FSTaskOptions,
        replyHandler reply: @escaping (FSItem?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let volume = self.volume else {
                reply(nil, fs_errorForPOSIXError(EIO))
                return
            }
            guard let inode = ntfs_inode_open(volume, MFT_REF(NTFSItem.rootInodeNumber)) else {
                reply(nil, fs_errorForPOSIXError(EIO))
                return
            }
            let root = NTFSItem(
                inodeNumber: NTFSItem.rootInodeNumber,
                isDirectory: true,
                inode: inode
            )
            self.rootItem = root
            reply(root, nil)
        }
    }

    func deactivate(
        options: FSDeactivateOptions = [],
        replyHandler reply: @escaping (Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            self.rootItem?.closeInode()
            self.rootItem = nil
            reply(nil)
        }
    }

    func synchronize(flags: FSSyncFlags, replyHandler reply: @escaping (Error?) -> Void) {
        NTFSFileSystem.queue.async {
            guard let volume = self.volume else { reply(nil); return }
            // Once inode onbellekleri, sonra aygit.
            let result = ntfs_device_sync(volume.pointee.dev)
            reply(result == 0 ? nil : fs_errorForPOSIXError(EIO))
        }
    }

    // MARK: - Oznitelikler

    func getAttributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem,
        replyHandler reply: @escaping (FSItem.Attributes?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let ntfsItem = item as? NTFSItem, let inode = ntfsItem.inode else {
                reply(nil, fs_errorForPOSIXError(EINVAL))
                return
            }
            reply(self.makeAttributes(for: ntfsItem, inode: inode), nil)
        }
    }

    func setAttributes(
        _ newAttributes: FSItem.SetAttributesRequest,
        on item: FSItem,
        replyHandler reply: @escaping (FSItem.Attributes?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let ntfsItem = item as? NTFSItem, let inode = ntfsItem.inode else {
                reply(nil, fs_errorForPOSIXError(EINVAL))
                return
            }

            // NTFS'te izin/sahiplik POSIX anlamiyla tutulmuyor; boyut ve
            // zaman damgalari uygulanabilir olanlar.
            if newAttributes.isValid(.size) {
                guard let attr = ntfs_attr_open(inode, AT_DATA, nil, 0) else {
                    reply(nil, fs_errorForPOSIXError(EIO))
                    return
                }
                let result = ntfs_attr_truncate(attr, Int64(newAttributes.size))
                ntfs_attr_close(attr)
                if result != 0 {
                    reply(nil, fs_errorForPOSIXError(errno))
                    return
                }
            }
            if newAttributes.isValid(.modifyTime) {
                inode.pointee.last_data_change_time =
                    NTFSTime.fromTimespec(newAttributes.modifyTime)
            }
            if newAttributes.isValid(.accessTime) {
                inode.pointee.last_access_time = NTFSTime.fromTimespec(newAttributes.accessTime)
            }
            wd_ntfs_mark_dirty(inode)

            reply(self.makeAttributes(for: ntfsItem, inode: inode), nil)
        }
    }

    /// Bir inode'dan FSKit oznitelik nesnesi uretir.
    private func makeAttributes(
        for item: NTFSItem,
        inode: UnsafeMutablePointer<ntfs_inode>
    ) -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        attributes.fileID = FSItem.Identifier(rawValue: item.inodeNumber) ?? .invalid
        attributes.type = item.isDirectory ? .directory : .file
        // Bag sayisi MFT kaydinda tutulur, inode yapisinda degil.
        attributes.linkCount = inode.pointee.mrec.map { UInt32($0.pointee.link_count) } ?? 1
        attributes.size = UInt64(bitPattern: inode.pointee.data_size)
        attributes.allocSize = UInt64(bitPattern: inode.pointee.allocated_size)
        // NTFS POSIX izinleri tasimadigindan sabit, makul bir kip veriliyor.
        attributes.mode = item.isDirectory ? 0o040_777 : 0o100_666
        attributes.uid = 0
        attributes.gid = 0
        attributes.modifyTime = NTFSTime.toTimespec(inode.pointee.last_data_change_time)
        attributes.accessTime = NTFSTime.toTimespec(inode.pointee.last_access_time)
        attributes.changeTime = NTFSTime.toTimespec(inode.pointee.last_mft_change_time)
        attributes.birthTime = NTFSTime.toTimespec(inode.pointee.creation_time)
        return attributes
    }

    // MARK: - Arama ve geri birakma

    func lookupItem(
        named name: FSFileName,
        inDirectory directory: FSItem,
        replyHandler reply: @escaping (FSItem?, FSFileName?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let volume = self.volume,
                  let parent = (directory as? NTFSItem)?.inode,
                  let text = name.string
            else {
                reply(nil, nil, fs_errorForPOSIXError(EINVAL))
                return
            }

            let reference = ntfs_inode_lookup_by_mbsname(parent, text)
            guard reference != UInt64(bitPattern: -1) else {
                reply(nil, nil, fs_errorForPOSIXError(ENOENT))
                return
            }

            let number = reference & 0x0000_FFFF_FFFF_FFFF
            guard let inode = ntfs_inode_open(volume, MFT_REF(reference)) else {
                reply(nil, nil, fs_errorForPOSIXError(EIO))
                return
            }
            let isDirectory = (inode.pointee.mrec.pointee.flags.rawValue
                & MFT_RECORD_IS_DIRECTORY.rawValue) != 0

            reply(
                NTFSItem(inodeNumber: number, isDirectory: isDirectory, inode: inode),
                name,
                nil
            )
        }
    }

    func reclaimItem(_ item: FSItem, replyHandler reply: @escaping (Error?) -> Void) {
        NTFSFileSystem.queue.async {
            (item as? NTFSItem)?.closeInode()
            reply(nil)
        }
    }
}
