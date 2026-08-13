import Foundation
import WipeKit

// ---------------------------------------------------------------------------
// wipe-helper — root olarak calisan, asil yazma islemini yapan parca.
//
// Arayuz bunu `osascript … with administrator privileges` ile baslatir, ardindan
// --progress dosyasini kuyruktan takip eder. Iptal, --cancel yolunda bir dosya
// olusturularak bildirilir; her parcada bakilir.
//
// Bu ikili tek basina da calistirilabilir:
//   sudo wipe-helper --device disk4 --method zeros --confirm disk4
// ---------------------------------------------------------------------------

let usage = """
Kullanim:
  wipe-helper --device <diskN> --method <yontem> --confirm <diskN> [secenekler]

Yontemler:
  zeros       Tek gecis, 0x00
  random      Tek gecis, sozde rastgele
  dod7        7 gecis, DoD 5220.22-M (ECE)
  gutmann35   35 gecis, Gutmann

Bolumleme / bicimlendirme (silme yapmaz):
  --partition <plan>    JSON bolumleme planini uygular. --confirm gerekir.
  --erase-volume <id>   Tek bir birimi yeniden bicimlendirir (or. disk6s2).
  --format <bicim>      --erase-volume ile: apfs | exfat | hfs | fat32
  --label <ad>          --erase-volume ile birim adi.

Secenekler:
  --confirm <diskN>     Zorunlu. --device ile birebir ayni olmali.
  --progress <yol>      Ilerleme olaylarinin JSON satirlari olarak yazilacagi dosya.
  --cancel <yol>        Bu yolda dosya olusursa islem durdurulur.
  --verify              Son gecisten sonra diski geri okuyup dogrular.
  --reformat <bicim>    none | exfat | apfs | hfs | fat32   (varsayilan: none)
  --label <ad>          Yeniden bicimlendirmede birim adi (varsayilan: WIPED)
  --dry-run             Hicbir sey yazmaz; butun akisi prova eder.
  --list                Diskleri JSON olarak yazdirir ve cikar.
  --help                Bu metni gosterir.
"""

// MARK: - Argumanlar

struct Arguments {
    var device: String?
    var method: WipeMethod = .zeros
    var confirm: String?
    var progressPath: String?
    var cancelPath: String?
    var verify = false
    var reformat: ReformatOption = .none
    var label = "WIPED"
    var dryRun = false
    var list = false
    var help = false
    var planPath: String?
    var eraseVolume: String?
    var volumeFormat: VolumeFormat?
}

func parseArguments(_ argv: [String]) throws -> Arguments {
    var args = Arguments()
    var index = 0

    func value(for flag: String) throws -> String {
        index += 1
        guard index < argv.count else { throw HelperError.missingValue(flag) }
        return argv[index]
    }

    while index < argv.count {
        let flag = argv[index]
        switch flag {
        case "--device", "-d":
            args.device = try value(for: flag)
        case "--method", "-m":
            let raw = try value(for: flag)
            guard let method = WipeMethod(rawValue: raw) ?? methodAlias(raw) else {
                throw HelperError.unknownMethod(raw)
            }
            args.method = method
        case "--confirm":
            args.confirm = try value(for: flag)
        case "--progress":
            args.progressPath = try value(for: flag)
        case "--cancel":
            args.cancelPath = try value(for: flag)
        case "--verify":
            args.verify = true
        case "--reformat":
            let raw = try value(for: flag).lowercased()
            guard let option = reformatAlias(raw) else { throw HelperError.unknownReformat(raw) }
            args.reformat = option
        case "--label":
            args.label = try value(for: flag)
        case "--dry-run":
            args.dryRun = true
        case "--partition":
            args.planPath = try value(for: flag)
        case "--erase-volume":
            args.eraseVolume = try value(for: flag)
        case "--format":
            let raw = try value(for: flag).lowercased()
            guard let option = reformatAlias(raw), let format = option.volumeFormat else {
                throw HelperError.unknownReformat(raw)
            }
            args.volumeFormat = format
        case "--list":
            args.list = true
        case "--help", "-h":
            args.help = true
        default:
            throw HelperError.unknownFlag(flag)
        }
        index += 1
    }
    return args
}

func methodAlias(_ raw: String) -> WipeMethod? {
    switch raw.lowercased() {
    case "zero", "zeros", "0": return .zeros
    case "random", "rand": return .random
    case "dod", "dod7", "7", "7pass": return .dod7
    case "gutmann", "gutmann35", "35", "35pass": return .gutmann35
    default: return nil
    }
}

func reformatAlias(_ raw: String) -> ReformatOption? {
    switch raw {
    case "none", "": return ReformatOption.none
    case "exfat": return .exfat
    case "apfs": return .apfs
    case "hfs", "hfs+", "jhfs+": return .hfsPlus
    case "fat32", "msdos", "fat": return .fat32
    default: return nil
    }
}

enum HelperError: LocalizedError {
    case missingValue(String)
    case unknownFlag(String)
    case unknownMethod(String)
    case unknownReformat(String)
    case missingDevice
    case confirmationMismatch(String, String)
    case notRoot

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag): return "\(flag) bir deger bekliyor."
        case .unknownFlag(let flag): return "Bilinmeyen secenek: \(flag)"
        case .unknownMethod(let raw): return "Bilinmeyen yontem: \(raw)"
        case .unknownReformat(let raw): return "Bilinmeyen bicim: \(raw)"
        case .missingDevice: return "--device zorunlu."
        case .confirmationMismatch(let device, let confirm):
            return "Onay eslesmedi: --device \(device) fakat --confirm \(confirm)."
        case .notRoot: return "Bu komut root olarak calistirilmalidir (sudo)."
        }
    }
}

// MARK: - Iptal

/// Belirtilen yolda dosya olusup olusmadigina bakar; ayrica SIGINT/SIGTERM'i yakalar.
final class CancellationWatcher {
    private let path: String?
    private let signalled = ManagedAtomicFlag()

    init(path: String?) {
        self.path = path
        installSignalHandlers()
    }

    var isCancelled: Bool {
        if signalled.value { return true }
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func installSignalHandlers() {
        // Sinyal islevlerinden yalnizca atomik bayrak yazilir; baska is yapilmaz.
        globalCancellationFlag = signalled
        signal(SIGINT) { _ in globalCancellationFlag?.set() }
        signal(SIGTERM) { _ in globalCancellationFlag?.set() }
    }
}

/// C sinyal islevlerinden erisilebilmesi icin genel bayrak.
final class ManagedAtomicFlag: @unchecked Sendable {
    private var storage: Int32 = 0
    var value: Bool { storage != 0 }
    func set() { storage = 1 }
}

nonisolated(unsafe) var globalCancellationFlag: ManagedAtomicFlag?

// MARK: - Calistirma

func emit(_ reporter: WipeReporter, _ kind: WipeEvent.Kind, _ message: String) {
    reporter.report(WipeEvent(kind: kind, message: message))
}

func main() -> Int32 {
    let argv = Array(CommandLine.arguments.dropFirst())

    let args: Arguments
    do {
        args = try parseArguments(argv)
    } catch {
        FileHandle.standardError.write(Data("Hata: \(error.localizedDescription)\n\n\(usage)\n".utf8))
        return 2
    }

    if args.help || argv.isEmpty {
        print(usage)
        return 0
    }

    if args.list {
        do {
            let disks = try DiskEnumerator.allDisks()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(disks))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Diskler listelenemedi: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    // Raportorler: her zaman stdout, istege bagli olarak arayuzun okudugu dosya.
    var reporters: [WipeReporter] = [ConsoleWipeReporter()]
    var fileReporter: FileWipeReporter?
    if let progressPath = args.progressPath {
        do {
            let reporter = try FileWipeReporter(path: progressPath)
            fileReporter = reporter
            reporters.append(reporter)
        } catch {
            FileHandle.standardError.write(
                Data("Ilerleme dosyasi acilamadi: \(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }
    let reporter = MultiWipeReporter(reporters)
    defer { fileReporter?.close() }

    func fail(_ message: String, code: String? = nil) -> Int32 {
        var event = WipeEvent(kind: .failed, message: message)
        event.errorCode = code
        reporter.report(event)
        FileHandle.standardError.write(Data("Hata: \(message)\n".utf8))
        return 1
    }

    /// Bolumleme ve bicimlendirme, korumali disklere de uygulanamaz.
    func guardWholeDisk(_ identifier: String) -> (DiskInfo?, Int32?) {
        do {
            let disk = try DiskEnumerator.disk(withIdentifier: identifier)
            if let reason = disk.blockReason {
                return (nil, fail(WipeError.diskProtected(identifier, reason).localizedDescription))
            }
            return (disk, nil)
        } catch {
            return (nil, fail(error.localizedDescription))
        }
    }

    // --- Tek birimi yeniden bicimlendir -------------------------------------

    if let rawVolume = args.eraseVolume {
        let volume = DiskEnumerator.normalizeIdentifier(rawVolume)
        let confirm = DiskEnumerator.normalizeIdentifier(args.confirm ?? "")
        guard confirm == volume else {
            return fail(HelperError.confirmationMismatch(
                volume, confirm.isEmpty ? "(yok)" : confirm
            ).localizedDescription)
        }
        guard let format = args.volumeFormat else {
            return fail("--erase-volume icin --format zorunlu.")
        }

        // Koruma kontrolu yetki kontrolunden once yapilir: hedef zaten yasaksa
        // parola sormanin anlami yok, ayrica bu yol koksuz de sinanabilir olur.
        let (_, failure) = guardWholeDisk(DiskEnumerator.wholeDisk(of: volume))
        if let failure { return failure }

        guard getuid() == 0 else { return fail(HelperError.notRoot.localizedDescription) }

        var started = WipeEvent(kind: .started)
        started.device = volume
        started.method = format.shortTitle
        started.message = "\(volume) birimi \(format.shortTitle) olarak bicimlendiriliyor…"
        reporter.report(started)

        do {
            try DiskFormatter.eraseVolume(volume, format: format, name: args.label) { line in
                emit(reporter, .log, line)
            }
        } catch {
            return fail(error.localizedDescription)
        }

        var finished = WipeEvent(kind: .finished)
        finished.device = volume
        finished.message = "\(volume) bicimlendirildi — \(format.shortTitle) · \(args.label)"
        reporter.report(finished)
        return 0
    }

    // --- Bolumleme plani uygula ---------------------------------------------

    if let planPath = args.planPath {
        guard let data = FileManager.default.contents(atPath: planPath) else {
            return fail("Bolumleme plani okunamadi: \(planPath)")
        }
        let plan: PartitionPlan
        do {
            plan = try JSONDecoder().decode(PartitionPlan.self, from: data)
        } catch {
            return fail("Bolumleme plani cozumlenemedi: \(error.localizedDescription)")
        }

        let identifier = DiskEnumerator.normalizeIdentifier(plan.device)
        let confirm = DiskEnumerator.normalizeIdentifier(args.confirm ?? "")
        guard confirm == identifier else {
            return fail(HelperError.confirmationMismatch(
                identifier, confirm.isEmpty ? "(yok)" : confirm
            ).localizedDescription)
        }
        let (maybeDisk, failure) = guardWholeDisk(identifier)
        if let failure { return failure }
        guard let disk = maybeDisk else { return fail("\(identifier) okunamadi.") }

        // Plan diske uymuyorsa parola sormadan once reddet.
        let blocking = plan.validate(against: disk).filter(\.isBlocking)
        guard blocking.isEmpty else {
            return fail(DiskFormatter.FormatError.planRejected(blocking).localizedDescription)
        }

        guard getuid() == 0 else { return fail(HelperError.notRoot.localizedDescription) }

        var started = WipeEvent(kind: .started)
        started.device = identifier
        started.method = "\(plan.scheme.rawValue) · \(plan.partitions.count) bolum"
        started.deviceBytes = disk.size
        started.message = "\(identifier) bolumleniyor — \(plan.scheme.rawValue), "
            + plan.partitions.map(\.diskutilName).joined(separator: ", ")
        reporter.report(started)

        do {
            try DiskFormatter.apply(plan: plan, to: disk) { line in
                emit(reporter, .log, line)
            }
        } catch {
            return fail(error.localizedDescription)
        }

        var finished = WipeEvent(kind: .finished)
        finished.device = identifier
        finished.message = "\(plan.partitions.count) bolum olusturuldu"
        reporter.report(finished)
        return 0
    }

    // --- Dogrulamalar -------------------------------------------------------

    guard let requestedDevice = args.device else {
        return fail(HelperError.missingDevice.localizedDescription)
    }
    let identifier = DiskEnumerator.normalizeIdentifier(requestedDevice)

    let confirm = DiskEnumerator.normalizeIdentifier(args.confirm ?? "")
    guard confirm == identifier else {
        return fail(HelperError.confirmationMismatch(identifier, confirm.isEmpty ? "(yok)" : confirm).localizedDescription)
    }

    if !args.dryRun && getuid() != 0 {
        return fail(HelperError.notRoot.localizedDescription)
    }

    // Arayuzun gonderdigi bilgiye guvenme; diski burada yeniden oku.
    let disk: DiskInfo
    do {
        disk = try DiskEnumerator.disk(withIdentifier: identifier)
    } catch {
        return fail(error.localizedDescription)
    }

    if let reason = disk.blockReason {
        return fail(WipeError.diskProtected(identifier, reason).localizedDescription)
    }

    let watcher = CancellationWatcher(path: args.cancelPath)
    if watcher.isCancelled {
        reporter.report(WipeEvent(kind: .cancelled, message: "Baslamadan once iptal edildi"))
        return 130
    }

    // --- Baglantiyi kes -----------------------------------------------------

    if !args.dryRun {
        emit(reporter, .log, "\(identifier) uzerindeki birimler ayriliyor…")
        do {
            try DiskEnumerator.unmountDisk(identifier)
        } catch {
            // Zaten bagli degilse diskutil hata verebilir; yazma denemesi asil testtir.
            emit(reporter, .log, "Ayirma uyarisi: \(error.localizedDescription)")
        }
    }

    // --- Sil ----------------------------------------------------------------

    let options = WipeOptions(method: args.method, verify: args.verify, dryRun: args.dryRun)
    let engine = WipeEngine(
        disk: disk,
        options: options,
        reporter: reporter,
        isCancelled: { watcher.isCancelled }
    )

    let summary: WipeEngine.Summary
    do {
        summary = try engine.run()
    } catch WipeError.cancelled {
        reporter.report(WipeEvent(kind: .cancelled, message: "Durduruldu — disk kismen uzerine yazilmis durumda"))
        return 130
    } catch let error as WipeError {
        return fail(error.localizedDescription, code: error.eventCode)
    } catch {
        return fail(error.localizedDescription)
    }

    // --- Yeniden bicimlendir ------------------------------------------------

    if args.reformat != .none && !args.dryRun {
        emit(reporter, .log, "\(args.reformat.title) olarak yeniden bicimlendiriliyor…")
        do {
            try DiskEnumerator.reformat(identifier, format: args.reformat, name: args.label)
            emit(reporter, .log, "Bicimlendirme tamamlandi: \(args.label)")
        } catch {
            emit(reporter, .log, "Bicimlendirme basarisiz: \(error.localizedDescription)")
        }
    }

    // --- Bitis --------------------------------------------------------------

    var finished = WipeEvent(kind: .finished)
    finished.device = identifier
    finished.method = args.method.shortTitle
    finished.overallDone = summary.bytesProcessed
    finished.overallTotal = summary.bytesTotal
    finished.passCount = summary.passCount
    finished.elapsed = summary.elapsed
    finished.message = args.dryRun
        ? "Deneme tamamlandi — diske dokunulmadi"
        : "\(summary.passCount) gecis · \(ByteFormatter.string(summary.bytesProcessed)) yazildi"
    reporter.report(finished)

    return 0
}

exit(main())
