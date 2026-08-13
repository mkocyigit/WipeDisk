import Foundation

/// Helper'in ilerleme dosyasina JSON satiri olarak yazdigi, arayuzun okudugu olay.
///
/// Butun alanlar istege bagli tutuldu ki iki taraf birbirinden bagimsiz gelisebilsin;
/// eski bir helper yeni bir arayuzle calistiginda cozumleme kirilmaz.
public struct WipeEvent: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable {
        case started
        case passStarted
        case progress
        case passFinished
        case verifyStarted
        case verifyProgress
        case verifyFinished
        case log
        case finished
        case failed
        case cancelled
    }

    public var kind: Kind
    public var message: String?
    /// Hatalarda, arayuzun ozel bir eylem sunabilmesi icin makine okunur etiket.
    public var errorCode: String?

    public var device: String?
    public var method: String?
    public var deviceBytes: UInt64?

    public var passIndex: Int?
    public var passCount: Int?
    public var passLabel: String?

    public var passDone: UInt64?
    public var passTotal: UInt64?
    public var overallDone: UInt64?
    public var overallTotal: UInt64?
    public var bytesPerSecond: Double?
    public var elapsed: Double?

    public init(kind: Kind, message: String? = nil) {
        self.kind = kind
        self.message = message
    }

    // MARK: - Tel bicimi

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Sonunda yeni satir olan tek satirlik JSON.
    public func jsonLine() throws -> Data {
        var data = try Self.encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> WipeEvent? {
        try? JSONDecoder().decode(WipeEvent.self, from: line)
    }
}

/// Motorun ilerleme bildirdigi kanal.
public protocol WipeReporter: AnyObject {
    func report(_ event: WipeEvent)
}

/// Olaylari bir dosyaya JSON satirlari olarak yazan raportor.
/// Arayuz bu dosyayi kuyruktan takip eder.
public final class FileWipeReporter: WipeReporter {

    private let handle: FileHandle
    private let queue = DispatchQueue(label: "wipedisk.reporter")

    public init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.handle = handle
    }

    public func report(_ event: WipeEvent) {
        queue.sync {
            guard let data = try? event.jsonLine() else { return }
            handle.write(data)
            // Arayuz canli okuyor; her satiri hemen diske dusur.
            try? handle.synchronize()
        }
    }

    public func close() {
        queue.sync { try? handle.close() }
    }
}

/// Olaylari standart ciktiya basan raportor — helper'i elle calistirirken kullanisli.
public final class ConsoleWipeReporter: WipeReporter {
    public init() {}

    public func report(_ event: WipeEvent) {
        guard let data = try? event.jsonLine() else { return }
        FileHandle.standardOutput.write(data)
    }
}

/// Birden fazla raportore ayni anda yazar.
public final class MultiWipeReporter: WipeReporter {
    private let reporters: [WipeReporter]

    public init(_ reporters: [WipeReporter]) {
        self.reporters = reporters
    }

    public func report(_ event: WipeEvent) {
        for reporter in reporters { reporter.report(event) }
    }
}
