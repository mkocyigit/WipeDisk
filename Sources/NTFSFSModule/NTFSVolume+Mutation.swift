import Foundation
import FSKit
import CNTFS

/// Dizin listeleme, olusturma, silme ve yeniden adlandirma.
@available(macOS 15.4, *)
extension NTFSVolume {

    /// UTF-8 adi NTFS'in UTF-16 gosterimine cevirir.
    /// Donen tampon `ntfs_ucsfree` ile birakilmalidir.
    static func toUnicode(_ name: String) -> (UnsafeMutablePointer<ntfschar>, UInt8)? {
        var buffer: UnsafeMutablePointer<ntfschar>?
        let length = name.withCString { ntfs_mbstoucs($0, &buffer) }
        guard length > 0, length <= 255, let buffer else { return nil }
        return (buffer, UInt8(length))
    }

    // MARK: - Dizin listeleme

    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker,
        replyHandler reply: @escaping (FSDirectoryVerifier, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let inode = (directory as? NTFSItem)?.inode else {
                reply(verifier, fs_errorForPOSIXError(EINVAL))
                return
            }

            // libntfs-3g dizini bir seferde okur; FSKit ise cerezle sayfa sayfa
            // ister. Girdiler toplanip cerezin gosterdigi yerden paketleniyor.
            let capacity = 4096
            let entries = UnsafeMutablePointer<wd_ntfs_dirent>.allocate(capacity: capacity)
            defer { entries.deallocate() }

            let count = wd_ntfs_readdir(inode, entries, Int32(capacity))
            guard count >= 0 else {
                reply(verifier, fs_errorForPOSIXError(EIO))
                return
            }

            var index = Int(cookie.rawValue)
            while index < Int(count) {
                let entry = entries[index]
                let name = withUnsafePointer(to: entry.name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 768) {
                        String(cString: $0)
                    }
                }
                index += 1

                let packed = packer.packEntry(
                    name: FSFileName(string: name),
                    itemType: entry.isDirectory != 0 ? .directory : .file,
                    itemID: FSItem.Identifier(rawValue: entry.inode) ?? .invalid,
                    nextCookie: FSDirectoryCookie(rawValue: UInt64(index)),
                    attributes: nil
                )
                // Paketleyici dolduysa kalanlar bir sonraki cagrida gelir.
                if !packed { break }
            }

            reply(verifier, nil)
        }
    }

    // MARK: - Olusturma

    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest,
        replyHandler reply: @escaping (FSItem?, FSFileName?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let parent = (directory as? NTFSItem)?.inode,
                  let text = name.string,
                  let (unicode, length) = Self.toUnicode(text)
            else {
                reply(nil, nil, fs_errorForPOSIXError(EINVAL))
                return
            }
            defer { ntfs_ucsfree(unicode) }

            // ntfs_create yalnizca dosya ve dizin uretir; digerleri desteklenmiyor.
            let mode: mode_t
            switch type {
            case .file: mode = S_IFREG
            case .directory: mode = S_IFDIR
            default:
                reply(nil, nil, fs_errorForPOSIXError(ENOTSUP))
                return
            }

            guard let inode = ntfs_create(parent, 0, unicode, length, mode) else {
                reply(nil, nil, fs_errorForPOSIXError(errno))
                return
            }

            let item = NTFSItem(
                inodeNumber: inode.pointee.mft_no,
                isDirectory: type == .directory,
                inode: inode
            )
            reply(item, name, nil)
        }
    }

    func createSymbolicLink(
        named name: FSFileName,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest,
        linkContents contents: FSFileName,
        replyHandler reply: @escaping (FSItem?, FSFileName?, Error?) -> Void
    ) {
        // NTFS sembolik baglari reparse noktasi olarak tutar; Windows semantigiyle
        // birebir uyumlu yazmak ayri bir is, simdilik desteklenmiyor.
        reply(nil, nil, fs_errorForPOSIXError(ENOTSUP))
    }

    func readSymbolicLink(
        _ item: FSItem,
        replyHandler reply: @escaping (FSFileName?, Error?) -> Void
    ) {
        reply(nil, fs_errorForPOSIXError(ENOTSUP))
    }

    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem,
        replyHandler reply: @escaping (FSFileName?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let source = (item as? NTFSItem)?.inode,
                  let parent = (directory as? NTFSItem)?.inode,
                  let text = name.string,
                  let (unicode, length) = Self.toUnicode(text)
            else {
                reply(nil, fs_errorForPOSIXError(EINVAL))
                return
            }
            defer { ntfs_ucsfree(unicode) }

            guard ntfs_link(source, parent, unicode, length) == 0 else {
                reply(nil, fs_errorForPOSIXError(errno))
                return
            }
            reply(name, nil)
        }
    }

    // MARK: - Silme ve yeniden adlandirma

    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem,
        replyHandler reply: @escaping (Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let volume = self.volume,
                  let target = item as? NTFSItem,
                  let inode = target.inode,
                  let parent = (directory as? NTFSItem)?.inode,
                  let text = name.string,
                  let (unicode, length) = Self.toUnicode(text)
            else {
                reply(fs_errorForPOSIXError(EINVAL))
                return
            }
            defer { ntfs_ucsfree(unicode) }

            // ntfs_delete basarili olursa inode'u kendisi kapatir; cift
            // kapatmayi onlemek icin isaretci burada birakiliyor.
            let result = ntfs_delete(volume, nil, inode, parent, unicode, length)
            if result == 0 {
                target.inode = nil
                reply(nil)
            } else {
                reply(fs_errorForPOSIXError(errno))
            }
        }
    }

    func renameItem(
        _ item: FSItem,
        inDirectory sourceDirectory: FSItem,
        named sourceName: FSFileName,
        to destinationName: FSFileName,
        inDirectory destinationDirectory: FSItem,
        overItem: FSItem?,
        replyHandler reply: @escaping (FSFileName?, Error?) -> Void
    ) {
        NTFSFileSystem.queue.async {
            guard let volume = self.volume,
                  let source = item as? NTFSItem,
                  let inode = source.inode,
                  let sourceParent = (sourceDirectory as? NTFSItem)?.inode,
                  let destinationParent = (destinationDirectory as? NTFSItem)?.inode,
                  let oldText = sourceName.string,
                  let newText = destinationName.string,
                  let (oldUnicode, oldLength) = Self.toUnicode(oldText),
                  let (newUnicode, newLength) = Self.toUnicode(newText)
            else {
                reply(nil, fs_errorForPOSIXError(EINVAL))
                return
            }
            defer {
                ntfs_ucsfree(oldUnicode)
                ntfs_ucsfree(newUnicode)
            }

            // NTFS'te yeniden adlandirma ayri bir islem degil: yeni ad baglanir,
            // eski bag kaldirilir. Sira onemli — once baglanir ki dosya
            // arada erisilemez kalmasin.
            guard ntfs_link(inode, destinationParent, newUnicode, newLength) == 0 else {
                reply(nil, fs_errorForPOSIXError(errno))
                return
            }
            let removed = ntfs_delete(volume, nil, inode, sourceParent, oldUnicode, oldLength)
            guard removed == 0 else {
                reply(nil, fs_errorForPOSIXError(errno))
                return
            }
            // ntfs_delete inode'u kapatti; cagiran taraf yeni adla yeniden acar.
            source.inode = nil
            reply(destinationName, nil)
        }
    }
}
