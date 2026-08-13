import Foundation

/// Bir diskin neden silinemeyecegini anlatan sebep.
public enum WipeBlockReason: Hashable, Sendable, Codable {
    /// Sistemin acilis / veri birimini barindiriyor.
    case systemDisk
    /// APFS tarafindan sentezlenmis sanal kap; fiziksel deposu silinmeli.
    case synthesized(physicalStores: [String])
    /// Disk imaji gibi, arkasinda gercek bir ortam olmayan sanal aygit.
    case virtualMedia
    /// Donanim veya surucu duzeyinde salt okunur.
    case readOnly

    public var localizedDescription: String {
        switch self {
        case .systemDisk:
            return "Sistem diski — macOS bu diskten calisiyor"
        case .synthesized(let stores):
            return "Sanal APFS kabi — bunun yerine \(stores.joined(separator: ", ")) silinmeli"
        case .virtualMedia:
            return "Sanal aygit (disk imaji) — fiziksel bir ortam degil"
        case .readOnly:
            return "Salt okunur ortam"
        }
    }
}

public struct PartitionInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { deviceIdentifier }
    public let deviceIdentifier: String
    public let volumeName: String?
    public let content: String?
    public let size: UInt64
    public let mountPoint: String?

    public init(
        deviceIdentifier: String,
        volumeName: String?,
        content: String?,
        size: UInt64,
        mountPoint: String?
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.volumeName = volumeName
        self.content = content
        self.size = size
        self.mountPoint = mountPoint
    }

    public var displayName: String {
        volumeName ?? content ?? deviceIdentifier
    }
}

public struct DiskInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { deviceIdentifier }

    public let deviceIdentifier: String   // "disk4"
    public let deviceNode: String         // "/dev/disk4"
    public let mediaName: String          // "SanDisk Ultra Media"
    public let size: UInt64
    public let blockSize: UInt32
    public let isInternal: Bool
    public let isRemovable: Bool
    public let isSolidState: Bool
    public let isVirtual: Bool
    public let busProtocol: String
    public let partitions: [PartitionInfo]
    public let blockReason: WipeBlockReason?

    public init(
        deviceIdentifier: String,
        deviceNode: String,
        mediaName: String,
        size: UInt64,
        blockSize: UInt32,
        isInternal: Bool,
        isRemovable: Bool,
        isSolidState: Bool,
        isVirtual: Bool,
        busProtocol: String,
        partitions: [PartitionInfo],
        blockReason: WipeBlockReason?
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceNode = deviceNode
        self.mediaName = mediaName
        self.size = size
        self.blockSize = blockSize
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isSolidState = isSolidState
        self.isVirtual = isVirtual
        self.busProtocol = busProtocol
        self.partitions = partitions
        self.blockReason = blockReason
    }

    /// Yazma icin kullanilacak ham aygit dugumu — tamponsuz, cok daha hizli.
    public var rawDeviceNode: String {
        "/dev/r" + deviceIdentifier
    }

    public var canWipe: Bool { blockReason == nil }

    /// Listede gosterilecek en anlamli ad.
    public var displayName: String {
        let volumes = partitions.compactMap(\.volumeName).filter { !$0.isEmpty }
        if let first = volumes.first {
            return volumes.count > 1 ? "\(first) +\(volumes.count - 1)" : first
        }
        return mediaName.isEmpty ? deviceIdentifier : mediaName
    }

    public var connectionSummary: String {
        var parts: [String] = [isInternal ? "Dahili" : "Harici"]
        if !busProtocol.isEmpty { parts.append(busProtocol) }
        parts.append(isSolidState ? "SSD" : "HDD")
        if isRemovable { parts.append("Cikarilabilir") }
        return parts.joined(separator: " · ")
    }

    public var formattedSize: String {
        ByteFormatter.string(size)
    }
}

/// Bayt bicimleyici — 1000 tabanli, `diskutil` ile ayni gosterim.
public enum ByteFormatter {
    public static func string(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let digits = value >= 100 || index == 0 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(digits)f %@", value, units[index])
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        return string(UInt64(bytesPerSecond)) + "/s"
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 60 * 60 * 24 * 30 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
