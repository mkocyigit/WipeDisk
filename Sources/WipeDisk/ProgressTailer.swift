import Foundation
import WipeKit

/// Helper'in yazdigi JSON satirlarini canli okuyup olaylara cevirir.
///
/// Helper root, arayuz normal kullanici olarak calistigi icin iki islem
/// arasindaki tek kopru bu dosya. Satir tamamlanmadan cozumlemeye
/// calismamak icin yarim satirlar tamponda bekletilir.
final class ProgressTailer {

    private let url: URL
    private let onEvent: (WipeEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var offset: UInt64 = 0
    private var pending = Data()
    private let queue = DispatchQueue(label: "wipedisk.tailer")

    init(url: URL, onEvent: @escaping (WipeEvent) -> Void) {
        self.url = url
        self.onEvent = onEvent
    }

    func start(interval: TimeInterval = 0.15) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.drain() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Kalan her seyi okur — helper cikinca son satirlarin kaybolmamasi icin.
    func flush() {
        queue.sync { drain() }
    }

    private func drain() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
        } catch {
            return
        }

        guard let fresh = try? handle.readToEnd(), !fresh.isEmpty else { return }
        offset += UInt64(fresh.count)
        pending.append(fresh)

        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending = pending[pending.index(after: newline)...]
            guard !line.isEmpty, let event = WipeEvent.decode(line: Data(line)) else { continue }
            let handler = onEvent
            DispatchQueue.main.async { handler(event) }
        }
    }
}
