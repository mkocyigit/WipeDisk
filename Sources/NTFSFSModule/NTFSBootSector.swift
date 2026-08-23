import Foundation
import FSKit

/// NTFS onyukleme sektorunun tanidigi kadari.
///
/// Tanima icin kutuphaneyi baglatmaya gerek yok: ilk sektordeki OEM kimligi ve
/// birim seri numarasi yeterli. Bu, `probeResource` yolunu ucuz tutuyor.
@available(macOS 15.4, *)
enum NTFSBootSector {

    struct Info {
        /// Birim adi $Volume kaydinda tutuluyor; onyukleme sektorunde yok.
        /// Tanima asamasinda seri numarasindan turetilmis bir ad yeterli.
        let name: String
        let containerID: FSContainerIdentifier
    }

    enum Outcome {
        case success(Info)
        case notNTFS
        case failure(Error)
    }

    /// NTFS onyukleme sektorunun OEM kimligi her zaman bu sekiz bayttir.
    private static let oemIdentifier = Array("NTFS    ".utf8)

    static func probe(device: FSBlockDeviceResource) -> Outcome {
        var sector = [UInt8](repeating: 0, count: 512)

        do {
            let read = try sector.withUnsafeMutableBytes { buffer -> Int in
                var error: NSError?
                let count = device.__read(
                    into: buffer.baseAddress!,
                    startingAt: 0,
                    length: buffer.count,
                    error: &error
                )
                if let error { throw error }
                return count
            }
            guard read >= 512 else { return .notNTFS }
        } catch {
            return .failure(error)
        }

        // OEM kimligi 3. bayttan itibaren sekiz bayt.
        guard Array(sector[3..<11]) == oemIdentifier else { return .notNTFS }

        // Birim seri numarasi 0x48 konumunda, kucuk-endian 64 bit.
        var serial: UInt64 = 0
        for index in (0x48..<0x50).reversed() {
            serial = (serial << 8) | UInt64(sector[index])
        }

        // Seri numarasindan kararli bir UUID uretilir; ayni birim her
        // baglanisinda ayni kimligi almalidir.
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: serial.littleEndian) { raw in
            for index in 0..<8 { bytes[index] = raw[index] }
        }
        // Surum 4 / RFC 4122 varyant bitleri.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = NSUUID(uuidBytes: bytes)
        return .success(
            Info(
                name: String(format: "NTFS-%08X", UInt32(truncatingIfNeeded: serial)),
                containerID: FSContainerIdentifier(uuid: uuid as UUID)
            )
        )
    }
}
