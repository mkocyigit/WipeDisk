import Foundation

/// `wipe-helper`i yonetici yetkisiyle baslatir.
///
/// macOS'un standart kimlik dogrulama penceresi `osascript`in
/// `do shell script … with administrator privileges` yapisi uzerinden acilir.
/// Helper arka plana alinir; ilerleme, paylasilan bir dosya uzerinden takip edilir.
enum PrivilegedRunner {

    enum LaunchError: LocalizedError {
        case helperNotFound
        case authorizationCancelled
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperNotFound:
                return "wipe-helper bulunamadi. Uygulamayi Scripts/make-app.sh ile yeniden paketleyin."
            case .authorizationCancelled:
                return "Yonetici kimlik dogrulamasi iptal edildi."
            case .launchFailed(let detail):
                return "Yardimci islem baslatilamadi: \(detail)"
            }
        }
    }

    /// Helper ikilisi, uygulama ikilisiyle ayni dizinde durur
    /// (paketlenmis halde `WipeDisk.app/Contents/MacOS/`, gelistirmede `.build/debug/`).
    static func helperURL() -> URL? {
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("wipe-helper"))
        }
        if let resource = Bundle.main.url(forResource: "wipe-helper", withExtension: nil) {
            candidates.append(resource)
        }
        candidates.append(
            URL(fileURLWithPath: CommandLine.arguments[0])
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
                .appendingPathComponent("wipe-helper")
        )

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Helper'i arka planda, root olarak baslatir ve hemen doner.
    static func launch(arguments: [String], prompt: String) throws {
        guard let helper = helperURL() else { throw LaunchError.helperNotFound }

        let command = ([helper.path] + arguments).map(shellQuote).joined(separator: " ")
        // Alt kabuk + arka plan: `do shell script` ciktinin kapanmasini bekler,
        // bu sayede hemen doner ve helper calismaya devam eder.
        let detached = "(\(command) >/dev/null 2>&1 &)"

        let script = """
        do shell script \(appleScriptQuote(detached)) \
        with prompt \(appleScriptQuote(prompt)) \
        with administrator privileges
        """

        let result = try Shell.osascript(script)
        guard result.status == 0 else {
            // -128, kullanicinin parola penceresini iptal etmesi.
            if result.stderr.contains("-128") || result.stderr.lowercased().contains("user canceled") {
                throw LaunchError.authorizationCancelled
            }
            throw LaunchError.launchFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: - Alintlama

    /// POSIX kabugu icin tek tirnakli alintlama.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript dizesi icin alintlama — once ters bolu, sonra tirnak.
    private static func appleScriptQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private enum Shell {
        struct Output {
            let status: Int32
            let stdout: String
            let stderr: String
        }

        static func osascript(_ script: String) throws -> Output {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try process.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return Output(
                status: process.terminationStatus,
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self)
            )
        }
    }
}
