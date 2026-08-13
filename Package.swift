// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WipeDisk",
    platforms: [.macOS(.v14)],
    targets: [
        // Ham disk ioctl'leri icin C kopru katmani (Swift C variadic'leri cagiramaz).
        .target(name: "CDiskIO"),

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

        // Ayricaliksiz SwiftUI arayuz.
        .executableTarget(
            name: "WipeDisk",
            dependencies: ["WipeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
