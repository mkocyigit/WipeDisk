import Foundation
import FSKit
import CNTFS

/// libntfs-3g ile baglanmis bir NTFS birimi.
///
/// Butun G/C, FSKit'in verdigi `FSBlockDeviceResource` uzerinden gecer:
/// libntfs-3g'nin takilabilir aygit katmani (`wd_ntfs_device_new`) kutuphanenin
/// okuma/yazma cagrilarini buraya yonlendirir. Boylece uzantinin `/dev/diskNsM`
/// acma yetkisine ihtiyaci kalmaz — sandbox icinde calisabilir.
@available(macOS 15.4, *)
final class NTFSVolume: FSVolume {

    enum VolumeError: LocalizedError {
        case mountFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .mountFailed(let code):
                return "NTFS birimi baglanamadi: \(String(cString: strerror(code))) (errno \(code))"
            }
        }
    }

    private let device: FSBlockDeviceResource
    private var volume: UnsafeMutablePointer<ntfs_volume>?
    private var ntfsDevice: UnsafeMutablePointer<ntfs_device>?

    init(device: FSBlockDeviceResource) throws {
        self.device = device
        super.init(
            volumeID: FSVolume.Identifier(uuid: UUID()),
            volumeName: FSFileName(string: device.bsdName)
        )
    }

    // MARK: - Aygit koprusu

    /// libntfs-3g'ye verilecek geri cagirmalar. Baglam olarak bu nesne gecer.
    private func makeIO() -> wd_ntfs_io {
        wd_ntfs_io(
            ctx: Unmanaged.passUnretained(self).toOpaque(),
            pread: { ctx, buffer, count, offset in
                let volume = Unmanaged<NTFSVolume>.fromOpaque(ctx!).takeUnretainedValue()
                return volume.read(into: buffer!, count: count, offset: offset)
            },
            pwrite: { ctx, buffer, count, offset in
                let volume = Unmanaged<NTFSVolume>.fromOpaque(ctx!).takeUnretainedValue()
                return volume.write(from: buffer!, count: count, offset: offset)
            },
            sync: { ctx in
                let volume = Unmanaged<NTFSVolume>.fromOpaque(ctx!).takeUnretainedValue()
                return volume.flush()
            },
            size: { ctx in
                let volume = Unmanaged<NTFSVolume>.fromOpaque(ctx!).takeUnretainedValue()
                return Int64(volume.device.blockCount * volume.device.blockSize)
            }
        )
    }

    private func read(into buffer: UnsafeMutableRawPointer, count: Int64, offset: Int64) -> Int64 {
        var error: NSError?
        let got = device.__read(
            into: buffer, startingAt: off_t(offset), length: Int(count), error: &error
        )
        return error == nil ? Int64(got) : -1
    }

    private func write(from buffer: UnsafeRawPointer, count: Int64, offset: Int64) -> Int64 {
        var error: NSError?
        let put = device.__write(
            from: UnsafeMutableRawPointer(mutating: buffer),
            startingAt: off_t(offset), length: Int(count), error: &error
        )
        return error == nil ? Int64(put) : -1
    }

    private func flush() -> Int32 {
        do {
            try device.metadataFlush()
            return 0
        } catch {
            return -1
        }
    }

    // MARK: - Baglama

    /// Birimi libntfs-3g ile baglar. Salt okunur bayragi verilmezse
    /// kutuphane okuma-yazma acar.
    func openVolume(readOnly: Bool) throws {
        var io = makeIO()
        guard let device = wd_ntfs_device_new(self.device.bsdName, &io) else {
            throw VolumeError.mountFailed(errno)
        }
        ntfsDevice = device

        // NTFS_MNT_RDONLY bir enum sabiti; bayrak alani unsigned long.
        let flags = ntfs_mount_flags(readOnly ? NTFS_MNT_RDONLY : 0)
        guard let mounted = ntfs_device_mount(device, flags) else {
            let code = errno
            ntfs_device_free(device)
            ntfsDevice = nil
            throw VolumeError.mountFailed(code)
        }
        volume = mounted
    }

    func closeVolume() {
        if let volume { ntfs_umount(volume, BOOL(0)) }
        volume = nil
        // ntfs_umount aygiti da birakir; cift birakmayi onlemek icin sifirlanir.
        ntfsDevice = nil
    }

    deinit { closeVolume() }
}
