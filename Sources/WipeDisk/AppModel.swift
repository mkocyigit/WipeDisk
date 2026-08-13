import Foundation
import SwiftUI
import WipeKit

/// Ekranda gorunen ayricalikli islemin durumu.
struct WipeSession {

    /// Oturumun ne is yaptigi. Bolumleme bayt bazinda ilerleme uretmez,
    /// bu yuzden panel ona gore sadelesir.
    enum JobKind: Equatable {
        case wipe
        case partition
        case formatVolume

        var isByteTracked: Bool { self == .wipe }
    }

    enum Phase: Equatable {
        case starting
        case writing
        case verifying
        case finished
        case failed(String)
        case cancelled(String)

        var isActive: Bool {
            switch self {
            case .starting, .writing, .verifying: return true
            case .finished, .failed, .cancelled: return false
            }
        }
    }

    let disk: DiskInfo
    let kind: JobKind
    /// Baslikta gosterilen is ozeti — "DoD 5220.22-M" veya "GPT · 3 bolum".
    let subtitle: String
    let startedAt: Date
    let isDryRun: Bool

    var phase: Phase = .starting
    var passIndex = 0
    var passCount: Int
    var passLabel = ""
    var passDone: UInt64 = 0
    var passTotal: UInt64 = 0
    var overallDone: UInt64 = 0
    var overallTotal: UInt64 = 0
    var bytesPerSecond: Double = 0
    var elapsed: TimeInterval = 0
    var log: [LogLine] = []
    /// Helper'in bildirdigi hata etiketi; arayuz buna gore ek eylem gosterir.
    var errorCode: String?

    struct LogLine: Identifiable {
        let id = UUID()
        let timestamp: Date
        let text: String
        let isError: Bool
    }

    var overallFraction: Double {
        guard overallTotal > 0 else { return 0 }
        return min(Double(overallDone) / Double(overallTotal), 1)
    }

    var passFraction: Double {
        guard passTotal > 0 else { return 0 }
        return min(Double(passDone) / Double(passTotal), 1)
    }

    /// Kalan sure — olculen anlik hiza gore.
    var eta: TimeInterval? {
        guard phase.isActive, bytesPerSecond > 1, overallTotal > overallDone else { return nil }
        return Double(overallTotal - overallDone) / bytesPerSecond
    }

    var statusText: String {
        switch phase {
        case .starting: return "Hazirlaniyor…"
        case .writing:
            guard kind.isByteTracked else {
                return kind == .partition ? "Bolumleniyor…" : "Bicimlendiriliyor…"
            }
            let label = passLabel.isEmpty ? "" : " · \(passLabel)"
            return "Gecis \(passIndex)/\(passCount)\(label)"
        case .verifying: return "Dogrulaniyor…"
        case .finished:
            switch kind {
            case .wipe: return isDryRun ? "Deneme tamamlandi" : "Silme tamamlandi"
            case .partition: return "Bolumleme tamamlandi"
            case .formatVolume: return "Bicimlendirme tamamlandi"
            }
        // Cok satirli hatalarda basliga yalnizca ilk satir; ayrintisi gunlukte.
        case .failed(let message): return message.components(separatedBy: "\n").first ?? message
        case .cancelled(let message): return message
        }
    }
}

@MainActor
final class AppModel: ObservableObject {

    // Disk listesi
    @Published private(set) var disks: [DiskInfo] = []
    @Published var selectedDiskID: DiskInfo.ID?
    @Published private(set) var isRefreshing = false
    @Published var listError: String?

    // Secenekler
    @Published var method: WipeMethod = .zeros
    @Published var verify = false
    @Published var dryRun = false
    @Published var reformat: ReformatOption = .none
    @Published var volumeLabel = "WIPED"

    // Bolumleme plani
    @Published var detailMode: DetailMode = .wipe
    @Published var scheme: PartitionScheme = .gpt
    @Published var partitions: [PlannedPartition] = [PartitionPlan.defaultPartition]
    @Published var isConfirmingPartition = false

    // Tek birim bicimlendirme
    @Published var volumeToFormat: PartitionInfo?
    @Published var volumeFormat: VolumeFormat = .exfat
    @Published var volumeFormatName = "DISK"

    // Oturum
    @Published var session: WipeSession?
    @Published var isConfirming = false
    @Published var launchError: String?
    /// Bolumleme `diskutil`e devredildigi icin yarida kesilemez.
    @Published private(set) var isCancellable = true

    enum DetailMode: String, CaseIterable, Identifiable {
        case wipe
        case partition

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wipe: return "Sil"
            case .partition: return "Bolumle"
            }
        }

        var systemImage: String {
            switch self {
            case .wipe: return "trash"
            case .partition: return "square.split.2x1"
            }
        }
    }

    private var tailer: ProgressTailer?
    private var runDirectory: URL?
    private var refreshTimer: Timer?

    var selectedDisk: DiskInfo? {
        disks.first { $0.id == selectedDiskID }
    }

    var isBusy: Bool { session?.phase.isActive ?? false }

    // MARK: - Disk listesi

    func startAutoRefresh() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isBusy else { return }
                self.refresh()
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .userInitiated) {
            let result = Result { try DiskEnumerator.allDisks() }
            await MainActor.run {
                self.isRefreshing = false
                switch result {
                case .success(let disks):
                    self.disks = disks
                    self.listError = nil
                    // Secimi listeyle ayni turda degistirmek, kenar cubugunun
                    // altindaki NSTableView'i yeniden girisli calistiriyor.
                    // Duzeltmeyi bir sonraki tura birak.
                    Task { @MainActor in self.reconcileSelection() }
                case .failure(let error):
                    self.listError = error.localizedDescription
                }
            }
        }
    }

    /// Liste tazelendikten sonra secimi gecerli bir diske sabitler.
    private func reconcileSelection() {
        if let id = selectedDiskID, !disks.contains(where: { $0.id == id }) {
            selectedDiskID = nil
        }
        if selectedDiskID == nil {
            selectedDiskID = disks.first(where: \.canWipe)?.id
        }
    }

    // MARK: - Silme

    /// Toplam yazilacak veri — kullaniciya isin buyuklugunu gostermek icin.
    func plannedBytes(for disk: DiskInfo) -> UInt64 {
        disk.size * UInt64(method.passCount + (verify ? 1 : 0))
    }

    func beginConfirmation() {
        guard let disk = selectedDisk, disk.canWipe, !isBusy else { return }
        launchError = nil
        isConfirming = true
    }

    func startWipe() {
        guard let disk = selectedDisk, disk.canWipe, !isBusy else { return }
        isConfirming = false

        var session = WipeSession(
            disk: disk,
            kind: .wipe,
            subtitle: method.title,
            startedAt: Date(),
            isDryRun: dryRun,
            passCount: method.passCount
        )
        session.overallTotal = plannedBytes(for: disk)

        launch(session: session, cancellable: true) { progressPath, cancelPath in
            var arguments = [
                "--device", disk.deviceIdentifier,
                "--confirm", disk.deviceIdentifier,
                "--method", self.method.rawValue,
                "--progress", progressPath,
                "--cancel", cancelPath,
            ]
            if self.verify { arguments.append("--verify") }
            if self.dryRun { arguments.append("--dry-run") }
            if self.reformat != .none {
                arguments += ["--reformat", self.reformat.rawValue, "--label", self.sanitizedLabel]
            }
            return arguments
        } prompt: {
            dryRun
                ? "WipeDisk, \(disk.deviceIdentifier) uzerinde deneme calistirmak icin yonetici yetkisi istiyor."
                : "WipeDisk, \(disk.deviceIdentifier) (\(disk.displayName)) diskini kalici olarak silmek icin yonetici yetkisi istiyor."
        }
    }

    // MARK: - Bolumleme

    /// Duzenlenmekte olan planin secili diske uygulanmis hali.
    func currentPlan(for disk: DiskInfo) -> PartitionPlan {
        PartitionPlan(device: disk.deviceIdentifier, scheme: scheme, partitions: partitions)
    }

    /// Disk degistiginde plan diskin tamamini kaplayan tek bolume doner.
    func resetPartitionPlan() {
        scheme = .gpt
        partitions = [PartitionPlan.defaultPartition]
    }

    func beginPartitionConfirmation() {
        guard let disk = selectedDisk, disk.canWipe, !isBusy else { return }
        guard currentPlan(for: disk).validate(against: disk).allSatisfy({ !$0.isBlocking }) else { return }
        launchError = nil
        isConfirmingPartition = true
    }

    func startPartitioning() {
        guard let disk = selectedDisk, disk.canWipe, !isBusy else { return }
        isConfirmingPartition = false

        let plan = currentPlan(for: disk)
        // Plan, helper'a dosya uzerinden gecer; komut satirinda tasimak icin fazla yapili.
        guard let planData = try? JSONEncoder().encode(plan) else {
            launchError = "Bolumleme plani kodlanamadi."
            return
        }

        let session = WipeSession(
            disk: disk,
            kind: .partition,
            subtitle: "\(scheme.rawValue) · \(partitions.count) bolum",
            startedAt: Date(),
            isDryRun: false,
            passCount: 1
        )

        launch(session: session, cancellable: false, writing: ["plan.json": planData]) { progressPath, _ in
            [
                "--partition", (progressPath as NSString).deletingLastPathComponent + "/plan.json",
                "--confirm", disk.deviceIdentifier,
                "--progress", progressPath,
            ]
        } prompt: {
            "WipeDisk, \(disk.deviceIdentifier) diskini yeniden bolumlemek icin yonetici yetkisi istiyor."
        }
    }

    // MARK: - Tek birim bicimlendirme

    func beginVolumeFormat(_ partition: PartitionInfo) {
        guard !isBusy else { return }
        launchError = nil
        volumeFormatName = partition.volumeName ?? "DISK"
        volumeToFormat = partition
    }

    func startVolumeFormat() {
        guard let disk = selectedDisk, disk.canWipe, !isBusy,
              let partition = volumeToFormat else { return }
        volumeToFormat = nil

        let format = volumeFormat
        let name = volumeFormatName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? "UNTITLED" : name

        let session = WipeSession(
            disk: disk,
            kind: .formatVolume,
            subtitle: "\(partition.deviceIdentifier) · \(format.shortTitle)",
            startedAt: Date(),
            isDryRun: false,
            passCount: 1
        )

        launch(session: session, cancellable: false) { progressPath, _ in
            [
                "--erase-volume", partition.deviceIdentifier,
                "--confirm", partition.deviceIdentifier,
                "--format", format.rawValue == "hfsPlus" ? "hfs" : format.rawValue,
                "--label", label,
                "--progress", progressPath,
            ]
        } prompt: {
            "WipeDisk, \(partition.deviceIdentifier) birimini bicimlendirmek icin yonetici yetkisi istiyor."
        }
    }

    // MARK: - Ortak baslatma

    /// Gecici dizini kurar, ilerleme takibini baslatir ve helper'i yonetici
    /// yetkisiyle calistirir. Uc is turu de bu yoldan gecer.
    private func launch(
        session initialSession: WipeSession,
        cancellable: Bool,
        writing files: [String: Data] = [:],
        arguments: (_ progressPath: String, _ cancelPath: String) -> [String],
        prompt: () -> String
    ) {
        launchError = nil

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WipeDisk-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in files {
                try data.write(to: directory.appendingPathComponent(name))
            }
        } catch {
            launchError = "Gecici dizin hazirlanamadi: \(error.localizedDescription)"
            return
        }
        runDirectory = directory
        isCancellable = cancellable

        let progressURL = directory.appendingPathComponent("progress.jsonl")
        let cancelURL = directory.appendingPathComponent("cancel")
        // Helper root olarak yazmadan once dosya var olmali ki takip hemen baslasin.
        FileManager.default.createFile(atPath: progressURL.path, contents: Data())

        var session = initialSession
        session.append("Yonetici yetkisi isteniyor…")
        self.session = session

        let argumentList = arguments(progressURL.path, cancelURL.path)
        let promptText = prompt()

        let tailer = ProgressTailer(url: progressURL) { [weak self] event in
            self?.handle(event)
        }
        self.tailer = tailer
        tailer.start()

        Task.detached(priority: .userInitiated) {
            do {
                try PrivilegedRunner.launch(arguments: argumentList, prompt: promptText)
            } catch {
                await MainActor.run { self.abort(with: error.localizedDescription) }
            }
        }
    }

    func cancelWipe() {
        guard let directory = runDirectory, isBusy, isCancellable else { return }
        let cancelURL = directory.appendingPathComponent("cancel")
        FileManager.default.createFile(atPath: cancelURL.path, contents: Data())
        session?.append("Durdurma istegi gonderildi; su anki parca bitince duracak.")
    }

    /// Bitmis oturumu kapatir ve listeyi tazeler.
    func dismissSession() {
        tailer?.stop()
        tailer = nil
        if let directory = runDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        runDirectory = nil
        session = nil
        refresh()
    }

    private var sanitizedLabel: String {
        let trimmed = volumeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "WIPED" : trimmed
    }

    // MARK: - Olay isleme

    private func handle(_ event: WipeEvent) {
        guard session != nil else { return }

        switch event.kind {
        case .started:
            session?.phase = .writing
            if let total = event.overallTotal { session?.overallTotal = total }
            if let count = event.passCount { session?.passCount = count }
            if let message = event.message { session?.append(message) }

        case .passStarted:
            session?.phase = .writing
            session?.passIndex = event.passIndex ?? 0
            session?.passCount = event.passCount ?? session?.passCount ?? 1
            session?.passLabel = event.passLabel ?? ""
            session?.passDone = 0
            session?.append("Gecis \(event.passIndex ?? 0)/\(event.passCount ?? 0) basladi — \(event.passLabel ?? "")")

        case .progress:
            session?.phase = .writing
            apply(progress: event)

        case .passFinished:
            if let done = event.overallDone { session?.overallDone = done }
            session?.passDone = session?.passTotal ?? 0

        case .verifyStarted:
            session?.phase = .verifying
            if let message = event.message { session?.append(message) }

        case .verifyProgress:
            session?.phase = .verifying
            apply(progress: event)

        case .verifyFinished:
            if let message = event.message { session?.append(message) }

        case .log:
            if let message = event.message { session?.append(message) }

        case .finished:
            session?.phase = .finished
            session?.overallDone = event.overallDone ?? session?.overallTotal ?? 0
            session?.elapsed = event.elapsed ?? session?.elapsed ?? 0
            if let message = event.message { session?.append(message) }
            session?.append("Toplam sure: \(ByteFormatter.duration(session?.elapsed ?? 0))")
            finishTailing()

        case .failed:
            let message = event.message ?? "Bilinmeyen hata"
            session?.errorCode = event.errorCode
            session?.phase = .failed(message)
            session?.append(message, isError: true)
            finishTailing()

        case .cancelled:
            let message = event.message ?? "Durduruldu"
            session?.phase = .cancelled(message)
            session?.append(message, isError: true)
            finishTailing()
        }
    }

    private func apply(progress event: WipeEvent) {
        if let index = event.passIndex { session?.passIndex = index }
        if let count = event.passCount { session?.passCount = count }
        if let label = event.passLabel { session?.passLabel = label }
        if let done = event.passDone { session?.passDone = done }
        if let total = event.passTotal { session?.passTotal = total }
        if let done = event.overallDone { session?.overallDone = done }
        if let total = event.overallTotal { session?.overallTotal = total }
        if let rate = event.bytesPerSecond { session?.bytesPerSecond = rate }
        if let elapsed = event.elapsed { session?.elapsed = elapsed }
    }

    private func abort(with message: String) {
        session?.phase = .failed(message)
        session?.append(message, isError: true)
        launchError = message
        finishTailing()
    }

    private func finishTailing() {
        tailer?.flush()
        tailer?.stop()
    }
}

private extension WipeSession {
    mutating func append(_ text: String, isError: Bool = false) {
        log.append(LogLine(timestamp: Date(), text: text, isError: isError))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
