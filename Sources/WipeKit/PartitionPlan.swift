import Foundation

/// Bir birime yazilabilecek dosya sistemi.
///
/// `diskutil`in bekledigi dosya sistemi adlarinin tek kaynagi burasidir;
/// silme sonrasi bicimlendirme (`ReformatOption`) da bunlara baglanir.
public enum VolumeFormat: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case apfs
    case exfat
    case hfsPlus
    case fat32
    /// macOS bunu olusturamaz; `mkntfs` ile yaziliyor.
    case ntfs
    /// Bicimlendirilmeden birakilan bos alan.
    case freeSpace

    public var id: String { rawValue }

    public var diskutilFilesystem: String {
        switch self {
        case .apfs: return "APFS"
        case .exfat: return "ExFAT"
        case .hfsPlus: return "JHFS+"
        case .fat32: return "MS-DOS FAT32"
        // diskutil NTFS olusturamaz. Bolum once ExFAT olarak acilir (ayni
        // "Microsoft Basic Data" tur kimligini kullanir), sonra uzerine mkntfs
        // ile NTFS yazilir. Bu deger yalnizca o ilk adim icindir.
        case .ntfs: return "ExFAT"
        case .freeSpace: return "free"
        }
    }

    public var title: String {
        switch self {
        case .apfs: return "APFS — yalnizca macOS"
        case .exfat: return "ExFAT — macOS + Windows"
        case .hfsPlus: return "Mac OS Genisletilmis (HFS+)"
        case .fat32: return "MS-DOS (FAT32)"
        case .ntfs: return "NTFS — Windows (macOS salt okunur baglar)"
        case .freeSpace: return "Bos alan (bicimlendirilmez)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .apfs: return "APFS"
        case .exfat: return "ExFAT"
        case .hfsPlus: return "HFS+"
        case .fat32: return "FAT32"
        case .ntfs: return "NTFS"
        case .freeSpace: return "Bos"
        }
    }

    /// `wipe-helper --format` bayraginin bekledigi takma ad.
    public var helperArgument: String {
        self == .hfsPlus ? "hfs" : rawValue
    }

    /// MBR semasi APFS tasiyamaz.
    public var supportsMBR: Bool { self != .apfs }

    /// diskutil'in olusturamadigi, harici arac gerektiren bicimler.
    public var needsExternalFormatter: Bool { self == .ntfs }

    /// macOS bu bicime yazabilir mi. NTFS yerlesik surucude salt okunurdur.
    public var isWritableByMacOS: Bool { self != .ntfs }

    /// FAT32'nin pratikte guvenli ust siniri.
    public var recommendedMaximum: UInt64? {
        self == .fat32 ? 32 * 1_000_000_000 : nil
    }
}

/// Bolum tablosu semasi.
public enum PartitionScheme: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case gpt = "GPT"
    case mbr = "MBR"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gpt: return "GUID (GPT) — modern, onerilen"
        case .mbr: return "Ana Onyukleme Kaydi (MBR) — eski aygitlar"
        }
    }

    /// MBR en fazla dort birincil bolum tanimlayabilir.
    public var maximumPartitions: Int? {
        switch self {
        case .gpt: return nil
        case .mbr: return 4
        }
    }
}

/// Bir bolumun boyutu.
public enum PartitionSize: Hashable, Sendable, Codable {
    case bytes(UInt64)
    /// Diskte kalan butun alan. Yalnizca son bolumde kullanilabilir.
    case remainder

    /// `diskutil`in bekledigi boyut ifadesi.
    var diskutilArgument: String {
        switch self {
        case .bytes(let value): return "\(value)B"
        case .remainder: return "R"
        }
    }

    public var byteValue: UInt64? {
        if case .bytes(let value) = self { return value }
        return nil
    }
}

public struct PlannedPartition: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var format: VolumeFormat
    public var size: PartitionSize

    public init(
        id: UUID = UUID(),
        name: String,
        format: VolumeFormat,
        size: PartitionSize
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.size = size
    }

    /// `diskutil`e verilecek ad. Bos alan bolumlerinde ad kullanilmaz.
    public var diskutilName: String {
        if format == .freeSpace { return "%noformat%" }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "UNTITLED" : trimmed
    }
}

/// Bir diske uygulanacak bolumleme plani.
public struct PartitionPlan: Hashable, Sendable, Codable {
    public var device: String
    public var scheme: PartitionScheme
    public var partitions: [PlannedPartition]

    public init(device: String, scheme: PartitionScheme = .gpt, partitions: [PlannedPartition]) {
        self.device = device
        self.scheme = scheme
        self.partitions = partitions
    }

    /// Yeni bir bolum eklenirken kullanilan baslangic degeri.
    public static var defaultPartition: PlannedPartition {
        PlannedPartition(name: "DISK", format: .exfat, size: .remainder)
    }

    /// Tek bolumlu, diskin tamamini kaplayan varsayilan plan.
    public static func single(device: String, format: VolumeFormat = .exfat, name: String = "DISK") -> PartitionPlan {
        PartitionPlan(
            device: device,
            scheme: .gpt,
            partitions: [PlannedPartition(name: name, format: format, size: .remainder)]
        )
    }

    /// Acikca boyut verilmis bolumlerin toplami.
    public var explicitBytes: UInt64 {
        partitions.reduce(0) { $0 + ($1.size.byteValue ?? 0) }
    }

    public var usesRemainder: Bool {
        partitions.contains { $0.size == .remainder }
    }

    // MARK: - Dogrulama

    public enum ValidationIssue: Hashable, Sendable {
        case empty
        case tooManyPartitions(limit: Int)
        case formatNotAllowedOnScheme(VolumeFormat, PartitionScheme)
        case remainderNotLast
        case multipleRemainders
        case zeroSize(String)
        case exceedsDisk(requested: UInt64, available: UInt64)
        case oversizedFormat(VolumeFormat, name: String, limit: UInt64)
        case allFreeSpace

        public var isBlocking: Bool {
            // Buyuk FAT32 calisir ama sorun cikarabilir; uyari olarak birakilir.
            if case .oversizedFormat = self { return false }
            return true
        }

        public var localizedDescription: String {
            switch self {
            case .empty:
                return "En az bir bolum tanimlamalisiniz."
            case .tooManyPartitions(let limit):
                return "Bu sema en fazla \(limit) bolum tasiyabilir."
            case .formatNotAllowedOnScheme(let format, let scheme):
                return "\(format.shortTitle), \(scheme.rawValue) semasinda kullanilamaz."
            case .remainderNotLast:
                return "\"Kalan alan\" yalnizca son bolumde secilebilir."
            case .multipleRemainders:
                return "Yalnizca bir bolum kalan alani kullanabilir."
            case .zeroSize(let name):
                return "\(name) icin boyut sifir olamaz."
            case .exceedsDisk(let requested, let available):
                return "Toplam \(ByteFormatter.string(requested)) istendi; diskte \(ByteFormatter.string(available)) var."
            case .oversizedFormat(let format, let name, let limit):
                return "\(name) bolumu \(format.shortTitle) icin buyuk (onerilen ust sinir \(ByteFormatter.string(limit)))."
            case .allFreeSpace:
                return "Butun bolumler bos alan olarak isaretlenmis; bicimlendirilecek birim yok."
            }
        }
    }

    /// Plani diske gore dogrular. Donen listede engelleyici ve uyari niteligindeki
    /// sorunlar birlikte bulunur; cagiran taraf `isBlocking` ile ayirir.
    public func validate(against disk: DiskInfo) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        guard !partitions.isEmpty else { return [.empty] }

        if let limit = scheme.maximumPartitions, partitions.count > limit {
            issues.append(.tooManyPartitions(limit: limit))
        }

        for partition in partitions where scheme == .mbr && !partition.format.supportsMBR {
            issues.append(.formatNotAllowedOnScheme(partition.format, scheme))
        }

        let remainderIndexes = partitions.indices.filter { partitions[$0].size == .remainder }
        if remainderIndexes.count > 1 {
            issues.append(.multipleRemainders)
        } else if let index = remainderIndexes.first, index != partitions.count - 1 {
            issues.append(.remainderNotLast)
        }

        for partition in partitions {
            if case .bytes(let value) = partition.size, value == 0 {
                issues.append(.zeroSize(partition.diskutilName))
            }
            if let limit = partition.format.recommendedMaximum,
               let value = partition.size.byteValue, value > limit {
                issues.append(.oversizedFormat(partition.format, name: partition.diskutilName, limit: limit))
            }
        }

        // Bolum tablosu ve hizalama icin diskin bir kismi kullanilamaz;
        // %1 pay birakmak, sinirda kalan planlarin diskutil'de patlamasini onler.
        let usable = disk.size - min(disk.size / 100, 128 * 1_000_000)
        if explicitBytes > usable {
            issues.append(.exceedsDisk(requested: explicitBytes, available: usable))
        }

        if partitions.allSatisfy({ $0.format == .freeSpace }) {
            issues.append(.allFreeSpace)
        }

        // Ayni sorun birden fazla bolumden dogabilir; kullaniciya bir kez soyle.
        var seen: Set<ValidationIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }

    /// `diskutil partitionDisk` argumanlari.
    func diskutilArguments() -> [String] {
        var arguments = ["partitionDisk", device, scheme.rawValue]
        for partition in partitions {
            arguments.append(partition.format.diskutilFilesystem)
            arguments.append(partition.diskutilName)
            arguments.append(partition.size.diskutilArgument)
        }
        return arguments
    }
}

/// Bolumleme ve bicimlendirme islemlerini yuruten katman.
///
/// Silme motorunun aksine burada ham aygita dokunulmaz; butun is `diskutil`e
/// devredilir. `diskutil` Apple tarafindan imzali oldugundan bu islemler
/// "Tam Disk Erisimi" iznine ihtiyac duymaz.
public enum DiskFormatter {

    private static let diskutil = "/usr/sbin/diskutil"

    public enum FormatError: LocalizedError {
        case planRejected([PartitionPlan.ValidationIssue])
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .planRejected(let issues):
                return "Plan uygulanamaz:\n" + issues.map { "• " + $0.localizedDescription }.joined(separator: "\n")
            case .commandFailed(let detail):
                return detail
            }
        }
    }

    /// Plani uygular. `diskutil` ciktisindaki her satir `onOutput` ile bildirilir.
    public static func apply(
        plan: PartitionPlan,
        to disk: DiskInfo,
        onOutput: @escaping (String) -> Void
    ) throws {
        let blocking = plan.validate(against: disk).filter(\.isBlocking)
        guard blocking.isEmpty else { throw FormatError.planRejected(blocking) }

        try runDiskutil(plan.diskutilArguments(), onOutput: onOutput)

        // NTFS istenen bolumler once ExFAT olarak olusturuldu; simdi uzerlerine
        // NTFS yaziliyor. Olusan veri bolumleri plandaki sirayla eslesir.
        guard plan.partitions.contains(where: { $0.format.needsExternalFormatter }) else { return }

        let created = try dataPartitions(of: plan.device)
        for (index, planned) in plan.partitions.enumerated()
        where planned.format.needsExternalFormatter {
            guard index < created.count else {
                throw FormatError.commandFailed(
                    "\(planned.diskutilName) icin olusturulan bolum bulunamadi."
                )
            }
            try writeNTFS(to: created[index], label: planned.diskutilName, onOutput: onOutput)
        }
    }

    /// Bir bolume NTFS yazar: once ayirir, mkntfs'i calistirir, sonra geri baglar.
    private static func writeNTFS(
        to device: String,
        label: String,
        onOutput: @escaping (String) -> Void
    ) throws {
        onOutput("\(device) uzerine NTFS yaziliyor…")
        // mkntfs aygita dogrudan yazar; bolumun bagli olmamasi gerekir.
        try? runDiskutil(["unmount", device]) { _ in }
        try NTFSFormatter.format(device: device, label: label, onOutput: onOutput)
        try? runDiskutil(["mount", device], onOutput: onOutput)
    }

    /// Diskteki veri bolumleri (EFI haric), bolum tablosundaki sirayla.
    private static func dataPartitions(of identifier: String) throws -> [String] {
        let listing = try Shell.plist(diskutil, ["list", "-plist", identifier])
        let entries = listing["AllDisksAndPartitions"] as? [[String: Any]] ?? []

        for entry in entries where (entry["DeviceIdentifier"] as? String) == identifier {
            return (entry["Partitions"] as? [[String: Any]] ?? []).compactMap { raw in
                guard let device = raw["DeviceIdentifier"] as? String else { return nil }
                return (raw["Content"] as? String) == "EFI" ? nil : device
            }
        }
        return []
    }

    /// Diskin tamamini tek adimda bicimlendirir: bolum tablosunu yeniden yazar
    /// ve tek bir birim olusturur. `diskutil eraseDisk`in karsiligi.
    public static func eraseDisk(
        _ identifier: String,
        format: VolumeFormat,
        name: String,
        scheme: PartitionScheme,
        onOutput: @escaping (String) -> Void
    ) throws {
        guard format != .freeSpace else {
            throw FormatError.commandFailed("Diskin tamami bos alan olarak bicimlendirilemez.")
        }
        guard scheme != .mbr || format.supportsMBR else {
            throw FormatError.commandFailed("\(format.shortTitle), MBR semasinda kullanilamaz.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "UNTITLED" : trimmed

        try runDiskutil(
            ["eraseDisk", format.diskutilFilesystem, label, scheme.rawValue, identifier],
            onOutput: onOutput
        )

        // diskutil NTFS olusturamaz. Bolum once ExFAT olarak aciliyor; ikisi de
        // ayni "Microsoft Basic Data" tur kimligini kullandigindan bolum tablosu
        // dogru kaliyor ve uzerine NTFS yazmak yetiyor.
        guard format.needsExternalFormatter else { return }
        guard let partition = try dataPartitions(of: identifier).first else {
            throw FormatError.commandFailed(
                "\(identifier) uzerinde bicimlendirilecek bolum bulunamadi."
            )
        }
        try writeNTFS(to: partition, label: label, onOutput: onOutput)
    }

    /// Bir birimi baglar. Yonetici yetkisi gerektirmez — cikarilabilir birimleri
    /// baglamak diskarbitrationd tarafindan normal kullaniciya aciktir.
    public static func mount(_ identifier: String, onOutput: @escaping (String) -> Void) throws {
        try runDiskutil(["mount", identifier], onOutput: onOutput)
    }

    public static func unmount(_ identifier: String, onOutput: @escaping (String) -> Void) throws {
        try runDiskutil(["unmount", identifier], onOutput: onOutput)
    }

    /// Mevcut tek bir birimi, bolum tablosuna dokunmadan yeniden bicimlendirir.
    public static func eraseVolume(
        _ identifier: String,
        format: VolumeFormat,
        name: String,
        onOutput: @escaping (String) -> Void
    ) throws {
        guard format != .freeSpace else {
            throw FormatError.commandFailed("Bos alan bir birime bicim olarak uygulanamaz.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "UNTITLED" : trimmed

        try runDiskutil(
            ["eraseVolume", format.diskutilFilesystem, label, identifier],
            onOutput: onOutput
        )

        if format.needsExternalFormatter {
            try writeNTFS(to: identifier, label: label, onOutput: onOutput)
        }
    }

    private static func runDiskutil(_ arguments: [String], onOutput: @escaping (String) -> Void) throws {
        var lastLines: [String] = []
        let status = try Shell.runStreaming(diskutil, arguments) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Hata mesajini kurabilmek icin son satirlar saklanir.
            lastLines.append(trimmed)
            if lastLines.count > 6 { lastLines.removeFirst() }
            onOutput(trimmed)
        }

        guard status == 0 else {
            let detail = lastLines.isEmpty
                ? "diskutil \(status) koduyla cikti."
                : lastLines.joined(separator: " ")
            throw FormatError.commandFailed(detail)
        }
    }
}
