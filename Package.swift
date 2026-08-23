// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WipeDisk",
    platforms: [.macOS(.v14)],
    targets: [
        // Ham disk ioctl'leri icin C kopru katmani (Swift C variadic'leri cagiramaz).
        .target(name: "CDiskIO"),

        // libntfs-3g'yi Swift'e acan kopru. Kutuphane ve basliklar
        // Scripts/build-ntfsprogs.sh tarafindan Vendor/ altina uretilir.
        .target(
            name: "CNTFS",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .unsafeFlags(["-IVendor/ntfsprogs/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-LVendor/ntfsprogs/lib"]),
                .linkedLibrary("ntfs-3g"),
                // libntfs-3g, macOS'ta Unicode normalizasyonu icin CF kullanir.
                .linkedFramework("CoreFoundation"),
            ]
        ),

        // Disk listeleme + silme motoru. Hem arayuz hem helper bunu kullanir.
        .target(
            name: "WipeKit",
            dependencies: ["CDiskIO"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // root olarak calisan, asil yazma islemini yapan CLI.
        .executableTarget(
            name: "wipe-helper",
            dependencies: ["WipeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // NTFS icin FSKit dosya sistemi modulu. Uygulama uzantisi (.appex) olarak
        // paketlenir; giris noktasi Foundation'in NSExtensionMain'idir.
        .executableTarget(
            name: "NTFSFSModule",
            dependencies: ["CNTFS"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // CNTFS semsiye basligi vendor edilmis ntfs-3g basliklarini iceriyor;
                // modul Swift'ten ice aktarilirken de bu yol gorunmeli.
                .unsafeFlags(["-Xcc", "-IVendor/ntfsprogs/include", "-Xcc", "-DHAVE_CONFIG_H"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
                .linkedFramework("FSKit"),
            ]
        ),

        // Ayricaliksiz SwiftUI arayuz.
        .executableTarget(
            name: "WipeDisk",
            dependencies: ["WipeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
