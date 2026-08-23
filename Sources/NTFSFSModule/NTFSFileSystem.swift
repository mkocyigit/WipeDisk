import Foundation
import FSKit
import CNTFS

/// NTFS icin FSKit dosya sistemi modulu.
///
/// macOS'un yerlesik NTFS surucusu salt okunurdur. Bu modul, okuma-yazma
/// destegi olan libntfs-3g'yi FSKit'in cagri yuzeyine baglar; boylece cekirdek
/// eklentisi (kext) ve macFUSE gerekmeden yazma mumkun olur.
///
/// Yuklenebilmesi icin `com.apple.developer.fskit.fsmodule` yetkisi sarttir;
/// bu yetki ucretli bir gelistirici hesabina bagli provisioning profile ile alinir.
/// FSKit macOS 15.4 ile geldi; ana uygulama macOS 14'u desteklemeye devam
/// ettigi icin yalnizca bu modul daha yuksek surum istiyor.
@available(macOS 15.4, *)
@objc(NTFSFileSystem)
public final class NTFSFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {

    /// libntfs-3g yeniden girise kapali; butun cagrilar tek bir kuyrukta sirlanir.
    static let queue = DispatchQueue(label: "wipedisk.ntfs.fs")

    public func probeResource(
        resource: FSResource,
        replyHandler reply: @escaping (FSProbeResult?, Error?) -> Void
    ) {
        guard let device = resource as? FSBlockDeviceResource else {
            reply(nil, fs_errorForPOSIXError(EINVAL))
            return
        }

        Self.queue.async {
            switch NTFSBootSector.probe(device: device) {
            case .success(let info):
                // Ad ve kap kimligi, birimin taninmasi ve yeniden baglanmasi icin.
                reply(.usable(name: info.name, containerID: info.containerID), nil)
            case .notNTFS:
                reply(.notRecognized, nil)
            case .failure(let error):
                reply(nil, error)
            }
        }
    }

    public func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping (FSVolume?, Error?) -> Void
    ) {
        guard let device = resource as? FSBlockDeviceResource else {
            reply(nil, fs_errorForPOSIXError(EINVAL))
            return
        }

        Self.queue.async {
            do {
                let volume = try NTFSVolume(device: device)
                reply(volume, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping (Error?) -> Void
    ) {
        reply(nil)
    }
}
