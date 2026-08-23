import Foundation
import FSKit
import CNTFS

/// Birimdeki tek bir dosya veya dizin.
///
/// FSKit, ogeleri kimlikleriyle degil nesne olarak tasiyor ve `reclaimItem`
/// cagrisina kadar canli tutuyor. Acik `ntfs_inode` isaretcisi burada saklanir;
/// libntfs-3g her islemde inode istedigi icin bu, tekrar tekrar acmayi onler.
@available(macOS 15.4, *)
final class NTFSItem: FSItem {

    /// NTFS'te dosya kimligi MFT kayit numarasidir.
    let inodeNumber: UInt64
    let isDirectory: Bool

    /// Acik inode. `reclaim` ile kapatilir.
    var inode: UnsafeMutablePointer<ntfs_inode>?

    init(inodeNumber: UInt64, isDirectory: Bool, inode: UnsafeMutablePointer<ntfs_inode>?) {
        self.inodeNumber = inodeNumber
        self.isDirectory = isDirectory
        self.inode = inode
        super.init()
    }

    /// NTFS kokunun MFT kayit numarasi her zaman 5'tir.
    static let rootInodeNumber: UInt64 = 5

    func closeInode() {
        if let inode {
            ntfs_inode_close(inode)
        }
        inode = nil
    }
}

/// NTFS zaman damgalari 1601-01-01'den itibaren 100 nanosaniyelik araliklardir.
@available(macOS 15.4, *)
enum NTFSTime {
    /// 1601 ile 1970 arasindaki saniye farki.
    private static let epochDelta: Int64 = 11_644_473_600

    static func toTimespec(_ ntfsTime: UInt64) -> timespec {
        let hundredNanos = Int64(bitPattern: ntfsTime)
        guard hundredNanos > 0 else { return timespec(tv_sec: 0, tv_nsec: 0) }
        let seconds = hundredNanos / 10_000_000 - epochDelta
        let nanos = (hundredNanos % 10_000_000) * 100
        return timespec(tv_sec: Int(seconds), tv_nsec: Int(nanos))
    }

    static func fromTimespec(_ time: timespec) -> UInt64 {
        let hundredNanos = (Int64(time.tv_sec) + epochDelta) * 10_000_000
            + Int64(time.tv_nsec) / 100
        return UInt64(bitPattern: hundredNanos)
    }
}
