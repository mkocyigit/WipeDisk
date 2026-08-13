import Foundation

/// xoshiro256** — hizli, tohumdan yeniden uretilebilir sozde rastgele uretec.
///
/// Uzerine yazma icin kriptografik uretec gerekmez; onemli olan yuksek entropili
/// baytlari disk hizini yavaslatmadan uretebilmek. Tohum `arc4random`dan gelir,
/// yani gecisler arasi desen tahmin edilemez; ayni tohum saklandigi icin
/// dogrulama asamasinda ayni akis birebir yeniden uretilebilir.
public struct Xoshiro256StarStar: RandomNumberGenerator {

    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    public init(seed: UInt64) {
        // splitmix64 ile tek kelimelik tohumu dort duruma dagit.
        var x = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func nextSplitMix() -> UInt64 {
            x &+= 0x9E37_79B9_7F4A_7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = nextSplitMix()
        s1 = nextSplitMix()
        s2 = nextSplitMix()
        s3 = nextSplitMix()
    }

    public static func randomSeed() -> UInt64 {
        var value: UInt64 = 0
        arc4random_buf(&value, MemoryLayout<UInt64>.size)
        return value
    }

    public mutating func next() -> UInt64 {
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17

        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = rotl(s3, 45)

        return result
    }

    /// Tamponu bastan sona rastgele baytla doldurur.
    /// `buffer` 8 baytin kati ve 8'e hizali olmalidir (silme tamponlari oyle).
    public mutating func fill(_ buffer: UnsafeMutableRawBufferPointer, count: Int) {
        guard let base = buffer.baseAddress, count > 0 else { return }
        let words = count / 8
        let pointer = base.assumingMemoryBound(to: UInt64.self)
        for index in 0..<words {
            pointer[index] = next()
        }
        // Artan baytlar (yalnizca hizali olmayan son parcada olusabilir).
        let remainder = count % 8
        if remainder > 0 {
            var tail = next()
            withUnsafeBytes(of: &tail) { raw in
                base.advanced(by: words * 8).copyMemory(from: raw.baseAddress!, byteCount: remainder)
            }
        }
    }

    @inline(__always)
    private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x << k) | (x >> (64 &- k))
    }
}
