import CDiskIO
import Foundation

public struct WipeOptions: Sendable {
    public var method: WipeMethod
    /// Son gecisten sonra diski geri okuyup yazilanla karsilastirir.
    public var verify: Bool
    /// Hicbir sey yazmadan butun akisi calistirir — guvenli deneme.
    public var dryRun: Bool
    /// Yazma tamponu. 12 MiB; hem 4096'nin hem de Gutmann'in 3 baytlik
    /// desen periyodunun tam kati oldugu icin desen fazi parca sinirlarinda kaymaz.
    public var chunkSize: Int

    public init(
        method: WipeMethod,
        verify: Bool = false,
        dryRun: Bool = false,
        chunkSize: Int = 12 * 1024 * 1024
    ) {
        self.method = method
        self.verify = verify
        self.dryRun = dryRun
        self.chunkSize = chunkSize
    }
}

public enum WipeError: LocalizedError {
    case notRoot
    case diskProtected(String, WipeBlockReason)
    case openFailed(String, Int32)
    case needsFullDiskAccess(String)
    case ioctlFailed(String, Int32)
    case notWritable(String)
    case writeFailed(UInt64, Int32)
    case readFailed(UInt64, Int32)
    case verificationMismatch(UInt64)
    case emptyDevice(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notRoot:
            return "Ham diske yazmak icin root yetkisi gerekiyor."
        case .diskProtected(let disk, let reason):
            return "\(disk) silinemez — \(reason.localizedDescription)."
        case .openFailed(let path, let code):
            return "\(path) acilamadi: \(String(cString: strerror(code))) (errno \(code))"
        case .needsFullDiskAccess(let path):
            return """
            \(path) acilamadi — macOS izin vermedi.

            Ham disklere erisim, root olsa bile "Tam Disk Erisimi" iznine baglidir. \
            Sistem Ayarlari › Gizlilik ve Guvenlik › Tam Disk Erisimi bolumune WipeDisk \
            uygulamasini ekleyin, ardindan uygulamayi tamamen kapatip yeniden acin.
            """
        case .ioctlFailed(let what, let code):
            return "\(what) okunamadi: \(String(cString: strerror(code))) (errno \(code))"
        case .notWritable(let path):
            return "\(path) yazma korumali."
        case .writeFailed(let offset, let code):
            return "\(ByteFormatter.string(offset)) konumunda yazma hatasi: \(String(cString: strerror(code)))"
        case .readFailed(let offset, let code):
            return "\(ByteFormatter.string(offset)) konumunda okuma hatasi: \(String(cString: strerror(code)))"
        case .verificationMismatch(let offset):
            return "Dogrulama basarisiz: \(ByteFormatter.string(offset)) konumundaki veri yazilanla eslesmiyor."
        case .emptyDevice(let path):
            return "\(path) sifir bayt bildiriyor; aygit hazir degil."
        case .cancelled:
            return "Islem kullanici tarafindan durduruldu."
        }
    }

    /// Arayuzun hataya ozel bir eylem sunabilmesi icin makine tarafindan okunabilir etiket.
    public var eventCode: String? {
        switch self {
        case .needsFullDiskAccess: return "fullDiskAccess"
        default: return nil
        }
    }
}

/// Ham blok aygitina desen yazan motor.
public final class WipeEngine {

    private let disk: DiskInfo
    private let options: WipeOptions
    private let reporter: WipeReporter
    private let isCancelled: () -> Bool

    /// Her gecisin rastgele tohumu; dogrulamada ayni akisi yeniden uretmek icin saklanir.
    private var passSeeds: [UInt64] = []

    public init(
        disk: DiskInfo,
        options: WipeOptions,
        reporter: WipeReporter,
        isCancelled: @escaping () -> Bool
    ) {
        self.disk = disk
        self.options = options
        self.reporter = reporter
        self.isCancelled = isCancelled
    }

    /// `run()` sonunda dondurulen ozet. Bitis olayini helper yayinlar ki
    /// yeniden bicimlendirme de "tamamlandi"dan once bitmis olsun.
    public struct Summary: Sendable {
        public let bytesProcessed: UInt64
        public let bytesTotal: UInt64
        public let elapsed: TimeInterval
        public let passCount: Int
    }

    // MARK: - On kontrol

    /// Ham aygita erisilebildigini, diskteki birimler ayrilmadan once dogrular.
    ///
    /// TCC hem okumayi hem yazmayi `EPERM` ile reddeder; `EBUSY` ise yalnizca
    /// yazma denemesinde cikar. Bu yuzden salt okunur bir acma denemesi izin
    /// sorununu kesin ayirt eder ve bagli bir diskte bile guvenle yapilabilir.
    ///
    /// Onemli: bu kontrol ayirmadan once calisir. Aksi halde izin yoksa disk
    /// once ayrilir, sonra islem basarisiz olur ve kullanicinin birimleri
    /// ortada kalir.
    public static func preflight(disk: DiskInfo) throws {
        let path = disk.rawDeviceNode
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return
        }
        // Yalnizca izin reddi burada olumcul; diger hatalar asil acma
        // sirasinda daha iyi baglamla bildirilecek.
        if errno == EPERM, getuid() == 0 {
            throw WipeError.needsFullDiskAccess(path)
        }
    }

    // MARK: - Ana akis

    @discardableResult
    public func run() throws -> Summary {
        guard getuid() == 0 || options.dryRun else { throw WipeError.notRoot }
        if let reason = disk.blockReason {
            throw WipeError.diskProtected(disk.deviceIdentifier, reason)
        }

        let path = disk.rawDeviceNode
        let flags = options.dryRun ? O_RDONLY : O_RDWR
        let fd = open(path, flags)
        guard fd >= 0 else {
            let code = errno
            // root iken EPERM, Unix izni degil TCC kapisidir: macOS fiziksel disk
            // aygitlarini "Tam Disk Erisimi" iznine baglar. Bunu ayirt et ki
            // kullaniciya "errno 1" yerine ne yapacagi soylenebilsin.
            if code == EPERM, getuid() == 0 {
                throw WipeError.needsFullDiskAccess(path)
            }
            throw WipeError.openFailed(path, code)
        }
        defer { close(fd) }

        let geometry = try readGeometry(fd: fd, path: path)
        let totalBytes = geometry.totalBytes
        let blockSize = Int(geometry.blockSize)

        let shuffleSeed = Xoshiro256StarStar.randomSeed()
        let passes = options.method.passes(shuffleSeed: shuffleSeed)
        passSeeds = passes.map { _ in Xoshiro256StarStar.randomSeed() }

        let verifyPasses = options.verify ? 1 : 0
        let overallTotal = totalBytes * UInt64(passes.count + verifyPasses)

        var started = WipeEvent(kind: .started)
        started.device = disk.deviceIdentifier
        started.method = options.method.shortTitle
        started.deviceBytes = totalBytes
        started.passCount = passes.count
        started.overallTotal = overallTotal
        started.message = options.dryRun
            ? "DENEME MODU — hicbir sey yazilmayacak"
            : "\(path) · \(ByteFormatter.string(totalBytes)) · \(passes.count) gecis"
        reporter.report(started)

        // Tampon: blok boyutuna hizali, blok boyutunun ve desen periyodunun tam kati.
        let chunkSize = alignedChunkSize(requested: options.chunkSize, blockSize: blockSize)
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: chunkSize,
            alignment: 4096
        )
        defer { buffer.deallocate() }

        let startTime = Date()
        var overallDone: UInt64 = 0

        for (index, pattern) in passes.enumerated() {
            try checkCancellation()

            var passEvent = WipeEvent(kind: .passStarted)
            passEvent.passIndex = index + 1
            passEvent.passCount = passes.count
            passEvent.passLabel = pattern.label
            passEvent.overallTotal = overallTotal
            passEvent.overallDone = overallDone
            reporter.report(passEvent)

            try writePass(
                fd: fd,
                pattern: pattern,
                seed: passSeeds[index],
                buffer: buffer,
                chunkSize: chunkSize,
                totalBytes: totalBytes,
                passIndex: index + 1,
                passCount: passes.count,
                overallDone: &overallDone,
                overallTotal: overallTotal,
                startTime: startTime
            )

            var done = WipeEvent(kind: .passFinished)
            done.passIndex = index + 1
            done.passCount = passes.count
            done.passLabel = pattern.label
            done.overallDone = overallDone
            done.overallTotal = overallTotal
            reporter.report(done)
        }

        if options.verify, let lastPattern = passes.last {
            try verifyPass(
                fd: fd,
                pattern: lastPattern,
                seed: passSeeds[passes.count - 1],
                buffer: buffer,
                chunkSize: chunkSize,
                totalBytes: totalBytes,
                overallDone: &overallDone,
                overallTotal: overallTotal,
                startTime: startTime
            )
        }

        return Summary(
            bytesProcessed: overallDone,
            bytesTotal: overallTotal,
            elapsed: Date().timeIntervalSince(startTime),
            passCount: passes.count
        )
    }

    // MARK: - Gecisler

    private func writePass(
        fd: Int32,
        pattern: WipePattern,
        seed: UInt64,
        buffer: UnsafeMutableRawBufferPointer,
        chunkSize: Int,
        totalBytes: UInt64,
        passIndex: Int,
        passCount: Int,
        overallDone: inout UInt64,
        overallTotal: UInt64,
        startTime: Date
    ) throws {
        var rng = Xoshiro256StarStar(seed: seed)

        // Sabit desenler bir kez doldurulur; tampon periyodun tam kati oldugu
        // icin her parcada faz basa doner.
        if case .fixed(let bytes) = pattern {
            fill(buffer, with: bytes, count: chunkSize)
        }

        var offset: UInt64 = 0
        var throttle = ProgressThrottle()

        while offset < totalBytes {
            try checkCancellation()

            let remaining = totalBytes - offset
            let count = Int(min(UInt64(chunkSize), remaining))

            if case .random = pattern {
                rng.fill(buffer, count: count)
            }

            if !options.dryRun {
                try writeFully(fd: fd, buffer: buffer, count: count, offset: offset)
            }

            offset += UInt64(count)
            overallDone += UInt64(count)

            if throttle.shouldReport(done: offset, total: totalBytes) {
                var event = WipeEvent(kind: .progress)
                event.passIndex = passIndex
                event.passCount = passCount
                event.passLabel = pattern.label
                event.passDone = offset
                event.passTotal = totalBytes
                event.overallDone = overallDone
                event.overallTotal = overallTotal
                event.bytesPerSecond = throttle.bytesPerSecond
                event.elapsed = Date().timeIntervalSince(startTime)
                reporter.report(event)
            }
        }

        if !options.dryRun {
            fsync(fd)
        }
    }

    private func verifyPass(
        fd: Int32,
        pattern: WipePattern,
        seed: UInt64,
        buffer: UnsafeMutableRawBufferPointer,
        chunkSize: Int,
        totalBytes: UInt64,
        overallDone: inout UInt64,
        overallTotal: UInt64,
        startTime: Date
    ) throws {
        var event = WipeEvent(kind: .verifyStarted)
        event.passLabel = pattern.label
        event.message = "Son gecis geri okunup karsilastiriliyor"
        reporter.report(event)

        if options.dryRun {
            overallDone += totalBytes
            reporter.report(WipeEvent(kind: .verifyFinished, message: "Deneme modunda dogrulama atlandi"))
            return
        }

        // Beklenen icerigi ureten tampon + diskten okunani tutan tampon.
        let readBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 4096)
        defer { readBuffer.deallocate() }

        var rng = Xoshiro256StarStar(seed: seed)
        if case .fixed(let bytes) = pattern {
            fill(buffer, with: bytes, count: chunkSize)
        }

        var offset: UInt64 = 0
        var throttle = ProgressThrottle()

        while offset < totalBytes {
            try checkCancellation()

            let count = Int(min(UInt64(chunkSize), totalBytes - offset))
            if case .random = pattern {
                rng.fill(buffer, count: count)
            }

            try readFully(fd: fd, buffer: readBuffer, count: count, offset: offset)

            if memcmp(buffer.baseAddress!, readBuffer.baseAddress!, count) != 0 {
                let delta = firstDifference(buffer, readBuffer, count: count)
                throw WipeError.verificationMismatch(offset + UInt64(delta))
            }

            offset += UInt64(count)
            overallDone += UInt64(count)

            if throttle.shouldReport(done: offset, total: totalBytes) {
                var progress = WipeEvent(kind: .verifyProgress)
                progress.passLabel = pattern.label
                progress.passDone = offset
                progress.passTotal = totalBytes
                progress.overallDone = overallDone
                progress.overallTotal = overallTotal
                progress.bytesPerSecond = throttle.bytesPerSecond
                progress.elapsed = Date().timeIntervalSince(startTime)
                reporter.report(progress)
            }
        }

        reporter.report(WipeEvent(kind: .verifyFinished, message: "Dogrulama basarili — disk beklenen deseni iceriyor"))
    }

    // MARK: - Dusuk seviye G/C

    private struct Geometry {
        let blockSize: UInt32
        let blockCount: UInt64
        var totalBytes: UInt64 { UInt64(blockSize) * blockCount }
    }

    private func readGeometry(fd: Int32, path: String) throws -> Geometry {
        var blockSize: UInt32 = 0
        guard wd_block_size(fd, &blockSize) == 0, blockSize > 0 else {
            throw WipeError.ioctlFailed("blok boyutu", errno)
        }

        var blockCount: UInt64 = 0
        guard wd_block_count(fd, &blockCount) == 0 else {
            throw WipeError.ioctlFailed("blok sayisi", errno)
        }

        guard blockCount > 0 else { throw WipeError.emptyDevice(path) }

        if !options.dryRun {
            var writable: UInt32 = 1
            if wd_is_writable(fd, &writable) == 0, writable == 0 {
                throw WipeError.notWritable(path)
            }
        }

        return Geometry(blockSize: blockSize, blockCount: blockCount)
    }

    private func writeFully(
        fd: Int32,
        buffer: UnsafeMutableRawBufferPointer,
        count: Int,
        offset: UInt64
    ) throws {
        var written = 0
        while written < count {
            let result = pwrite(
                fd,
                buffer.baseAddress!.advanced(by: written),
                count - written,
                off_t(offset) + off_t(written)
            )
            if result < 0 {
                if errno == EINTR { continue }
                throw WipeError.writeFailed(offset + UInt64(written), errno)
            }
            if result == 0 { throw WipeError.writeFailed(offset + UInt64(written), EIO) }
            written += result
        }
    }

    private func readFully(
        fd: Int32,
        buffer: UnsafeMutableRawBufferPointer,
        count: Int,
        offset: UInt64
    ) throws {
        var read = 0
        while read < count {
            let result = pread(
                fd,
                buffer.baseAddress!.advanced(by: read),
                count - read,
                off_t(offset) + off_t(read)
            )
            if result < 0 {
                if errno == EINTR { continue }
                throw WipeError.readFailed(offset + UInt64(read), errno)
            }
            if result == 0 { throw WipeError.readFailed(offset + UInt64(read), EIO) }
            read += result
        }
    }

    // MARK: - Yardimcilar

    private func checkCancellation() throws {
        if isCancelled() { throw WipeError.cancelled }
    }

    /// Tamponu, blok boyutunun ve 3 baytlik Gutmann periyodunun tam kati yapar.
    private func alignedChunkSize(requested: Int, blockSize: Int) -> Int {
        let unit = lcm(max(blockSize, 512), 3)
        let multiples = max(requested / unit, 1)
        return unit * multiples
    }

    private func lcm(_ a: Int, _ b: Int) -> Int {
        a / gcd(a, b) * b
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return abs(x)
    }

    private func fill(_ buffer: UnsafeMutableRawBufferPointer, with bytes: [UInt8], count: Int) {
        guard let base = buffer.baseAddress, !bytes.isEmpty else { return }
        if bytes.count == 1 {
            memset(base, Int32(bytes[0]), count)
            return
        }
        // Once bir periyot yaz, sonra ustel olarak ikiye katlayarak cogalt.
        for index in 0..<min(bytes.count, count) {
            base.storeBytes(of: bytes[index], toByteOffset: index, as: UInt8.self)
        }
        var filled = min(bytes.count, count)
        while filled < count {
            let copy = min(filled, count - filled)
            memcpy(base.advanced(by: filled), base, copy)
            filled += copy
        }
    }

    private func firstDifference(
        _ expected: UnsafeMutableRawBufferPointer,
        _ actual: UnsafeMutableRawBufferPointer,
        count: Int
    ) -> Int {
        let lhs = expected.baseAddress!.assumingMemoryBound(to: UInt8.self)
        let rhs = actual.baseAddress!.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count where lhs[index] != rhs[index] {
            return index
        }
        return 0
    }
}

/// Ilerleme olaylarini saniyede birkac kez ile sinirlar ve anlik hizi olcer.
private struct ProgressThrottle {
    private var lastReport = Date.distantPast
    private var lastBytes: UInt64 = 0
    private(set) var bytesPerSecond: Double = 0

    mutating func shouldReport(done: UInt64, total: UInt64) -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastReport)
        guard elapsed >= 0.25 || done >= total else { return false }

        if elapsed > 0, elapsed < 3600 {
            let delta = Double(done - lastBytes)
            let instant = delta / elapsed
            // Ekrandaki sayinin zipzip atmamasi icin ustel duzlestirme.
            bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * 0.7 + instant * 0.3
        }
        lastReport = now
        lastBytes = done
        return true
    }
}
