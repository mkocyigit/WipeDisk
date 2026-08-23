import Foundation

/// `diskutil` ciktisini okuyup sistemdeki butun diskleri listeler ve
/// hangilerinin silinmesinin yasak oldugunu belirler.
public enum DiskEnumerator {

    private static let diskutil = "/usr/sbin/diskutil"

    /// Korunmasi gereken baglama noktalari. Bunlarin altindaki her sey
    /// fiziksel diske kadar geriye izlenip kara listeye alinir.
    private static let criticalMountPoints = [
        "/",
        "/System/Volumes/Data",
        "/System/Volumes/Preboot",
        "/System/Volumes/VM",
        "/System/Volumes/Update",
    ]

    // MARK: - Genel liste

    public static func allDisks() throws -> [DiskInfo] {
        let listing = try Shell.plist(diskutil, ["list", "-plist"])
        let wholeDisks = listing["WholeDisks"] as? [String] ?? []
        let protected = protectedWholeDisks()
        let actionable = Set(wholeDisks).subtracting(protected)
        let partitionMap = enrichedPartitions(from: listing, limitedTo: actionable)

        // Her disk icin ayri bir `diskutil info` calistirilir; seri yapildiginda
        // toplam sure saniyeleri buluyordu. Cagrilar birbirinden bagimsiz.
        let infos = concurrentPlists(for: wholeDisks)

        var disks: [DiskInfo] = []
        for identifier in wholeDisks {
            guard let info = infos[identifier] else { continue }
            disks.append(
                makeDisk(
                    identifier: identifier,
                    info: info,
                    partitions: partitionMap[identifier] ?? [],
                    protectedDisks: protected
                )
            )
        }

        // Once silinebilir harici diskler, sonra digerleri.
        return disks.sorted { lhs, rhs in
            if lhs.canWipe != rhs.canWipe { return lhs.canWipe }
            if lhs.isInternal != rhs.isInternal { return !lhs.isInternal }
            return lhs.deviceIdentifier.localizedStandardCompare(rhs.deviceIdentifier) == .orderedAscending
        }
    }

    /// Tek bir diski taze olarak okur. Helper, silmeden hemen once
    /// arayuzun verdigi bilgiye guvenmek yerine bunu kullanir.
    public static func disk(withIdentifier identifier: String) throws -> DiskInfo {
        let normalized = normalizeIdentifier(identifier)
        let info = try Shell.plist(diskutil, ["info", "-plist", normalized])

        guard (info["WholeDisk"] as? Bool) == true else {
            throw DiskError.notAWholeDisk(normalized)
        }

        let listing = (try? Shell.plist(diskutil, ["list", "-plist"])) ?? [:]
        return makeDisk(
            identifier: normalized,
            info: info,
            partitions: enrichedPartitions(from: listing, limitedTo: [normalized])[normalized] ?? [],
            protectedDisks: protectedWholeDisks()
        )
    }

    /// "/dev/disk4", "/dev/rdisk4" ve "disk4" girdilerini "disk4"e indirger.
    public static func normalizeIdentifier(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/dev/") { value.removeFirst("/dev/".count) }
        if value.hasPrefix("r"), value.dropFirst().hasPrefix("disk") { value.removeFirst() }
        return value
    }

    // MARK: - Kurulum yardimcilari

    private static func makeDisk(
        identifier: String,
        info: [String: Any],
        partitions: [PartitionInfo],
        protectedDisks: Set<String>
    ) -> DiskInfo {
        let isVirtual = (info["VirtualOrPhysical"] as? String)?.lowercased() == "virtual"
        let physicalStores = physicalStoreDisks(from: info)
        let writable = (info["WritableMedia"] as? Bool) ?? true

        var reason: WipeBlockReason?
        if protectedDisks.contains(identifier) {
            reason = .systemDisk
        } else if isVirtual {
            // Sentezlenmis APFS kabinin geriye izlenebilir bir fiziksel deposu vardir;
            // disk imajinin yoktur. Kullaniciya dogru sebebi gosterebilmek icin ayrilir.
            reason = physicalStores.isEmpty
                ? .virtualMedia
                : .synthesized(physicalStores: physicalStores.sorted())
        } else if !writable {
            reason = .readOnly
        }

        return DiskInfo(
            deviceIdentifier: identifier,
            deviceNode: (info["DeviceNode"] as? String) ?? "/dev/\(identifier)",
            mediaName: (info["MediaName"] as? String) ?? "",
            size: uint64(info["Size"]) ?? uint64(info["TotalSize"]) ?? 0,
            blockSize: UInt32(uint64(info["DeviceBlockSize"]) ?? 512),
            isInternal: (info["Internal"] as? Bool) ?? false,
            isRemovable: (info["RemovableMedia"] as? Bool)
                ?? ((info["RemovableMedia"] as? String)?.lowercased() == "removable"),
            isSolidState: (info["SolidState"] as? Bool) ?? false,
            isVirtual: isVirtual,
            busProtocol: (info["BusProtocol"] as? String) ?? "",
            partitions: partitions,
            blockReason: reason
        )
    }

    private static func partitionsByDisk(from listing: [String: Any]) -> [String: [PartitionInfo]] {
        var result: [String: [PartitionInfo]] = [:]
        let entries = listing["AllDisksAndPartitions"] as? [[String: Any]] ?? []

        for entry in entries {
            guard let disk = entry["DeviceIdentifier"] as? String else { continue }
            var parts: [PartitionInfo] = []

            for raw in (entry["Partitions"] as? [[String: Any]] ?? []) {
                parts.append(partition(from: raw))
            }
            // APFS kaplarinda birimler ayri bir anahtar altinda gelir.
            for raw in (entry["APFSVolumes"] as? [[String: Any]] ?? []) {
                parts.append(partition(from: raw))
            }
            result[disk] = parts
        }
        return result
    }

    /// Verilen aygitlar icin `diskutil info -plist` ciktilarini eszamanli toplar.
    private static func concurrentPlists(for identifiers: [String]) -> [String: [String: Any]] {
        guard !identifiers.isEmpty else { return [:] }
        var result: [String: [String: Any]] = [:]
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: identifiers.count) { index in
            let identifier = identifiers[index]
            guard let info = try? Shell.plist(diskutil, ["info", "-plist", identifier]) else { return }
            lock.lock()
            result[identifier] = info
            lock.unlock()
        }
        return result
    }

    /// Bolum listesini dosya sistemi ve yazilabilirlik bilgisiyle tamamlar.
    ///
    /// `diskutil list` yalnizca bolum tablosundaki turu verir ("Microsoft Basic
    /// Data"); bunun NTFS mi ExFAT mi oldugu ancak `diskutil info` ile anlasilir.
    private static func enrichedPartitions(
        from listing: [String: Any],
        limitedTo wanted: Set<String>
    ) -> [String: [PartitionInfo]] {
        let base = partitionsByDisk(from: listing)

        // Bolum basina bir `diskutil info` gerekiyor ve bu cagrilar
        // diskarbitrationd uzerinde siraya giriyor. Ayrinti yalnizca kullanicinin
        // islem yapabildigi disklerde gosterildigi icin otekiler atlanir:
        // tazeleme suresi ~40 cagridan birkac cagriya iniyor.
        let identifiers = base
            .filter { wanted.contains($0.key) }
            .values.flatMap { $0 }
            .map(\.deviceIdentifier)
        let details = concurrentPlists(for: identifiers)

        return base.mapValues { partitions in
            partitions.map { partition in
                guard let info = details[partition.deviceIdentifier] else { return partition }
                return PartitionInfo(
                    deviceIdentifier: partition.deviceIdentifier,
                    volumeName: partition.volumeName ?? (info["VolumeName"] as? String),
                    content: partition.content,
                    size: partition.size,
                    // Baglama noktasi `info`da daha guncel; list ciktisi gecikebiliyor.
                    mountPoint: (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? partition.mountPoint,
                    filesystem: (info["FilesystemName"] as? String)
                        ?? (info["FilesystemUserVisibleName"] as? String),
                    isWritable: (info["WritableVolume"] as? Bool) ?? true
                )
            }
        }
    }

    private static func partition(from raw: [String: Any]) -> PartitionInfo {
        PartitionInfo(
            deviceIdentifier: (raw["DeviceIdentifier"] as? String) ?? "?",
            volumeName: raw["VolumeName"] as? String,
            content: raw["Content"] as? String,
            size: uint64(raw["Size"]) ?? 0,
            mountPoint: raw["MountPoint"] as? String
        )
    }

    // MARK: - Koruma

    /// Sistemin uzerinde calistigi butun fiziksel diskleri bulur.
    ///
    /// Acilis birimi genellikle sentezlenmis bir APFS kabinin (`disk3s1s1`)
    /// icindedir; gercek hedef o kabin fiziksel deposudur (`disk0s2` -> `disk0`).
    private static let protectedCache = ProtectedDiskCache()

    /// Sistemin uzerinde calistigi diskler surec omru boyunca degismez
    /// (acilis birimi calisirken baska bir diske tasinmaz), bu yuzden bir kez
    /// hesaplanip saklanir. Tazeleme dongusundeki en pahali adim buydu.
    public static func protectedWholeDisks() -> Set<String> {
        if let cached = protectedCache.value { return cached }
        let computed = computeProtectedWholeDisks()
        protectedCache.value = computed
        return computed
    }

    /// Onbellegi bosaltir — yalnizca testler ve uzun omurlu sureclerde gerekir.
    public static func invalidateProtectedCache() {
        protectedCache.value = nil
    }

    private static func computeProtectedWholeDisks() -> Set<String> {
        var protected: Set<String> = []

        // Baglama noktalarinin bilgisi birbirinden bagimsiz; eszamanli topla.
        let existing = criticalMountPoints.filter { FileManager.default.fileExists(atPath: $0) }
        let mountInfos = concurrentPlists(for: existing)

        for mountPoint in existing {
            guard let info = mountInfos[mountPoint] else { continue }

            if let parent = info["ParentWholeDisk"] as? String {
                protected.insert(parent)
                protected.formUnion(physicalStoreWholeDisks(ofContainer: parent))
            }
            if let device = info["DeviceIdentifier"] as? String {
                protected.formUnion(physicalStoreWholeDisks(ofContainer: device))
            }
        }

        // Kap -> fiziksel depo zinciri birden fazla halka olabilir; sabit noktaya kadar genislet.
        var frontier = protected
        while !frontier.isEmpty {
            var next: Set<String> = []
            for disk in frontier {
                for store in physicalStoreWholeDisks(ofContainer: disk) where !protected.contains(store) {
                    next.insert(store)
                }
            }
            protected.formUnion(next)
            frontier = next
        }

        return protected
    }

    /// Bir APFS kabinin fiziksel depolarinin ait oldugu tam diskler.
    private static func physicalStoreWholeDisks(ofContainer identifier: String) -> Set<String> {
        guard let info = try? Shell.plist(diskutil, ["info", "-plist", identifier]) else { return [] }
        var result: Set<String> = []
        for store in physicalStoreDisks(from: info) {
            result.insert(wholeDisk(of: store))
        }
        return result
    }

    private static func physicalStoreDisks(from info: [String: Any]) -> Set<String> {
        var stores: Set<String> = []
        for entry in (info["APFSPhysicalStores"] as? [[String: Any]] ?? []) {
            if let store = entry["APFSPhysicalStore"] as? String { stores.insert(store) }
            if let store = entry["DeviceIdentifier"] as? String { stores.insert(store) }
        }
        if let single = info["APFSPhysicalStore"] as? String { stores.insert(single) }
        // CoreStorage (eski Fusion Drive) kurulumlari.
        if let cs = info["CoreStoragePhysicalDeviceIdentifiers"] as? [String] {
            stores.formUnion(cs)
        }
        return stores
    }

    /// "disk0s2" -> "disk0"
    public static func wholeDisk(of identifier: String) -> String {
        let normalized = normalizeIdentifier(identifier)
        guard normalized.hasPrefix("disk") else { return normalized }
        let digits = normalized.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? normalized : "disk\(digits)"
    }

    // MARK: - Baglantiyi kesme

    /// Silmeden once diskteki butun birimleri zorla ayirir.
    public static func unmountDisk(_ identifier: String) throws {
        try Shell.runChecked(diskutil, ["unmountDisk", "force", normalizeIdentifier(identifier)])
    }

    /// Silme sonrasi diski yeniden bolumlendirir.
    public static func reformat(_ identifier: String, format: ReformatOption, name: String) throws {
        guard let filesystem = format.diskutilFilesystem else { return }
        try Shell.runChecked(
            diskutil,
            ["eraseDisk", filesystem, name, format.partitionScheme, normalizeIdentifier(identifier)]
        )
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let n as NSNumber: return n.uint64Value
        case let s as String: return UInt64(s)
        default: return nil
        }
    }

    public enum DiskError: LocalizedError {
        case notAWholeDisk(String)

        public var errorDescription: String? {
            switch self {
            case .notAWholeDisk(let id):
                return "\(id) tam bir disk degil (bolum veya birim). Yalnizca tam diskler silinebilir."
            }
        }
    }
}

/// `protectedWholeDisks()` sonucunu tasiyan kilitli kutu.
private final class ProtectedDiskCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String>?

    var value: Set<String>? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

/// Silme bittikten sonra uygulanacak bicimlendirme.
public enum ReformatOption: String, CaseIterable, Sendable, Codable {
    case none
    case exfat
    case apfs
    case hfsPlus
    case fat32

    public var title: String {
        switch self {
        case .none: return "Bicimlendirme (ham disk kalir)"
        case .exfat: return "ExFAT — macOS + Windows"
        case .apfs: return "APFS — yalnizca macOS"
        case .hfsPlus: return "Mac OS Genisletilmis (HFS+)"
        case .fat32: return "MS-DOS (FAT32) — 32 GB'a kadar"
        }
    }

    /// Dosya sistemi adlarinin tek kaynagi `VolumeFormat`; burada yalnizca eslestirilir.
    public var volumeFormat: VolumeFormat? {
        switch self {
        case .none: return nil
        case .exfat: return .exfat
        case .apfs: return .apfs
        case .hfsPlus: return .hfsPlus
        case .fat32: return .fat32
        }
    }

    var diskutilFilesystem: String? { volumeFormat?.diskutilFilesystem }

    var partitionScheme: String {
        switch self {
        case .fat32: return "MBR"
        default: return "GPT"
        }
    }
}
