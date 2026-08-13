import Foundation

/// Harici komut calistirmak icin ince sarmalayici.
public enum Shell {

    public struct Result: Sendable {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data

        public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    public enum ShellError: LocalizedError {
        case launchFailed(String, Error)
        case nonZeroExit(String, Int32, String)

        public var errorDescription: String? {
            switch self {
            case .launchFailed(let cmd, let err):
                return "\(cmd) baslatilamadi: \(err.localizedDescription)"
            case .nonZeroExit(let cmd, let status, let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(cmd) \(status) koduyla cikti\(trimmed.isEmpty ? "" : ": \(trimmed)")"
            }
        }
    }

    @discardableResult
    public static func run(_ launchPath: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(launchPath, error)
        }

        // Buyuk ciktilarda kilitlenmemek icin once oku, sonra bekle.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(status: process.terminationStatus, stdout: outData, stderr: errData)
    }

    /// Cikis kodu 0 degilse hata firlatir.
    @discardableResult
    public static func runChecked(_ launchPath: String, _ arguments: [String]) throws -> Result {
        let result = try run(launchPath, arguments)
        guard result.status == 0 else {
            let combined = result.stderrText.isEmpty ? result.stdoutText : result.stderrText
            throw ShellError.nonZeroExit(
                ([launchPath] + arguments).joined(separator: " "),
                result.status,
                combined
            )
        }
        return result
    }

    /// `-plist` ureten komutlari calistirip sozluk olarak dondurur.
    public static func plist(_ launchPath: String, _ arguments: [String]) throws -> [String: Any] {
        let result = try runChecked(launchPath, arguments)
        let object = try PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        )
        return object as? [String: Any] ?? [:]
    }
}
