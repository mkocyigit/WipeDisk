import Foundation

/// NTFS bicimlendirmesini yuruten katman.
///
/// macOS NTFS olusturamaz — `diskutil listFilesystems` ciktisinda NTFS yoktur ve
/// `ntfs.fs` paketinde bir bicimlendirici tanimli degildir. Bu bosluk, ntfs-3g
/// projesinin `mkntfs` araciyla kapatiliyor; arac uygulama paketinde tasiniyor.
///
/// Okuma tarafi macOS'un kendi isi: NTFS birimleri FSKit uzerinden salt okunur
/// baglanir, ek surucu gerekmez.
public enum NTFSFormatter {

    public enum NTFSError: LocalizedError {
        case toolMissing
        case needsFullDiskAccess(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .toolMissing:
                return """
                NTFS bicimlendirme araci (mkntfs) bulunamadi. \
                Scripts/build-ntfsprogs.sh calistirilip uygulama yeniden paketlenmeli.
                """
            case .needsFullDiskAccess(let device):
                return """
                \(device) uzerine NTFS yazilamadi — macOS izin vermedi.

                Ham disk aygitlarina erisim, root olsa bile "Tam Disk Erisimi" iznine \
                baglidir. Sistem Ayarlari › Gizlilik ve Guvenlik › Tam Disk Erisimi \
                bolumune WipeDisk uygulamasini ekleyin, ardindan uygulamayi tamamen \
                kapatip yeniden acin.
                """
            case .failed(let detail):
                return "mkntfs basarisiz: \(detail)"
            }
        }

        public var eventCode: String? {
            if case .needsFullDiskAccess = self { return "fullDiskAccess" }
            return nil
        }
    }

    /// `mkntfs` ikilisinin yeri. Once uygulama paketinin yani, sonra gelistirme
    /// agacindaki Vendor dizini denenir.
    public static func toolURL() -> URL? {
        var candidates: [URL] = []

        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("mkntfs"))
        }
        let argv0 = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        candidates.append(argv0.appendingPathComponent("mkntfs"))
        // Gelistirmede .build/debug'dan calisirken depo kokundeki Vendor kullanilir.
        candidates.append(
            argv0.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Vendor/ntfsprogs/bin/mkntfs")
        )

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var isAvailable: Bool { toolURL() != nil }

    /// Verilen bolum aygitina NTFS yazar. Aygitin bagli olmamasi gerekir.
    ///
    /// - Parameters:
    ///   - device: Bolum aygiti, or. `disk6s1`.
    ///   - label: Birim adi.
    ///   - quick: Hizli bicimlendirme (kume haritasi sifirlanmaz).
    public static func format(
        device: String,
        label: String,
        quick: Bool = true,
        onOutput: @escaping (String) -> Void
    ) throws {
        guard let tool = toolURL() else { throw NTFSError.toolMissing }

        let node = device.hasPrefix("/dev/") ? device : "/dev/\(device)"
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        var arguments = ["--force", "--label", trimmed.isEmpty ? "UNTITLED" : trimmed]
        if quick { arguments.append("--fast") }
        arguments.append(node)

        var lines: [String] = []
        let status = try Shell.runStreaming(tool.path, arguments) { line in
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            lines.append(text)
            if lines.count > 8 { lines.removeFirst() }
            onOutput(text)
        }

        guard status == 0 else {
            let detail = lines.joined(separator: " ")
            // mkntfs, TCC engellendiginde aygiti acamadigini bildirir; bu, eksik
            // izin demektir, gercek bir bicimlendirme hatasi degil.
            if detail.localizedCaseInsensitiveContains("Operation not permitted")
                || detail.localizedCaseInsensitiveContains("Permission denied") {
                throw NTFSError.needsFullDiskAccess(node)
            }
            throw NTFSError.failed(detail.isEmpty ? "cikis kodu \(status)" : detail)
        }
    }
}
