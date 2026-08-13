import Foundation

/// Tek bir gecisin diske yazacagi veri.
public enum WipePattern: Equatable, Sendable {
    /// Tekrarlanan sabit bayt dizisi (1 veya 3 bayt).
    case fixed([UInt8])
    /// Sozde rastgele akis. Tohum kaydedildigi icin dogrulamada yeniden uretilebilir.
    case random

    public var label: String {
        switch self {
        case .random:
            return "rastgele"
        case .fixed(let bytes):
            return bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        }
    }

    /// Tampon uzunlugunun tam boluneceginden emin olunmasi gereken periyot.
    var period: Int {
        switch self {
        case .random: return 1
        case .fixed(let bytes): return max(bytes.count, 1)
        }
    }
}

public enum WipeMethod: String, CaseIterable, Sendable, Codable, Identifiable {
    case zeros
    case random
    case dod7
    case gutmann35

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .zeros: return "Sifirlarla doldur"
        case .random: return "Rastgele veriyle doldur"
        case .dod7: return "7 gecis — DoD 5220.22-M (ECE)"
        case .gutmann35: return "35 gecis — Gutmann"
        }
    }

    public var summary: String {
        switch self {
        case .zeros:
            return "Diskin tamami bir kez 0x00 ile yazilir. En hizli secenek; modern sürücülerde veri kurtarmayi pratikte imkansiz kilar."
        case .random:
            return "Diskin tamami bir kez kriptografik tohumdan uretilen sozde rastgele veriyle yazilir. Sifirlamadan ayirt edilemez sekilde hizli, ancak eski verinin sinirini gizler."
        case .dod7:
            return "0x00, 0xFF, rastgele, rastgele, 0x00, 0xFF, rastgele. Eski ABD Savunma Bakanligi standardinin genisletilmis (ECE) bicimi. Sifir gecisin yedi kati sure alir."
        case .gutmann35:
            return "Peter Gutmann'in 1996 tarihli 35 gecisli dizisi: 4 rastgele, 27 hedeflenmis desen (karisik sirayla), 4 rastgele. 1990'larin MFM/RLL sabit disklerine yoneliktir; gunumuz sürücülerinde asiri ama en kapsamli secenektir."
        }
    }

    /// Insan diline uygun kisa etiket, gunlukte kullanilir.
    public var shortTitle: String {
        switch self {
        case .zeros: return "Sifir"
        case .random: return "Rastgele"
        case .dod7: return "DoD 7 gecis"
        case .gutmann35: return "Gutmann 35 gecis"
        }
    }

    public var passCount: Int {
        switch self {
        case .zeros, .random: return 1
        case .dod7: return 7
        case .gutmann35: return 35
        }
    }

    /// Yontemin gecis listesi.
    ///
    /// `seed`, Gutmann'da deterministik desenlerin karistirma sirasini belirler;
    /// boylece ayni tohumla ayni sira yeniden uretilebilir.
    public func passes(shuffleSeed: UInt64) -> [WipePattern] {
        switch self {
        case .zeros:
            return [.fixed([0x00])]

        case .random:
            return [.random]

        case .dod7:
            // DoD 5220.22-M (E) uclusu -> rastgele -> uclu tekrar.
            return [
                .fixed([0x00]),
                .fixed([0xFF]),
                .random,
                .random,
                .fixed([0x00]),
                .fixed([0xFF]),
                .random,
            ]

        case .gutmann35:
            var rng = Xoshiro256StarStar(seed: shuffleSeed)
            var deterministic = Self.gutmannDeterministicPatterns
            // Gutmann, 27 hedefli gecisin rastgele sirada uygulanmasini sart kosar.
            deterministic.shuffle(using: &rng)
            return Array(repeating: WipePattern.random, count: 4)
                + deterministic
                + Array(repeating: WipePattern.random, count: 4)
        }
    }

    /// Gutmann dizisinin 5–31. gecisleri (kodlama-hedefli sabit desenler).
    static let gutmannDeterministicPatterns: [WipePattern] = [
        .fixed([0x55, 0x55, 0x55]),
        .fixed([0xAA, 0xAA, 0xAA]),
        .fixed([0x92, 0x49, 0x24]),
        .fixed([0x49, 0x24, 0x92]),
        .fixed([0x24, 0x92, 0x49]),
        .fixed([0x00, 0x00, 0x00]),
        .fixed([0x11, 0x11, 0x11]),
        .fixed([0x22, 0x22, 0x22]),
        .fixed([0x33, 0x33, 0x33]),
        .fixed([0x44, 0x44, 0x44]),
        .fixed([0x55, 0x55, 0x55]),
        .fixed([0x66, 0x66, 0x66]),
        .fixed([0x77, 0x77, 0x77]),
        .fixed([0x88, 0x88, 0x88]),
        .fixed([0x99, 0x99, 0x99]),
        .fixed([0xAA, 0xAA, 0xAA]),
        .fixed([0xBB, 0xBB, 0xBB]),
        .fixed([0xCC, 0xCC, 0xCC]),
        .fixed([0xDD, 0xDD, 0xDD]),
        .fixed([0xEE, 0xEE, 0xEE]),
        .fixed([0xFF, 0xFF, 0xFF]),
        .fixed([0x92, 0x49, 0x24]),
        .fixed([0x49, 0x24, 0x92]),
        .fixed([0x24, 0x92, 0x49]),
        .fixed([0x6D, 0xB6, 0xDB]),
        .fixed([0xB6, 0xDB, 0x6D]),
        .fixed([0xDB, 0x6D, 0xB6]),
    ]
}
