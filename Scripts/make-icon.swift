#!/usr/bin/env swift
//
// WipeDisk uygulama ikonunu uretir — tamamen kodla cizilir, disaridan
// hicbir gorsel varlik kullanilmaz, dolayisiyla telif sorunu yoktur.
//
// Tasarim: koyu squircle zemin uzerinde bir disk platteri; capraz bir "silme
// basligi" plattere carpar ve carptigi yerden itibaren disk piksellere dagilir.
// Kucuk boyutlarda bile "daire + capraz kesik" siluetiyle okunur kalir.
//
// Kullanim:  swift Scripts/make-icon.swift [cikis-dizini]
// Uretir:    AppIcon.iconset/ + AppIcon.icns
//
import AppKit
import Foundation

// MARK: - Yardimcilar

/// Tekrarlanabilir sozde rastgele — her calistirmada ayni ikon ciksin diye.
struct Random {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
    mutating func next(_ lower: Double, _ upper: Double) -> Double {
        lower + next() * (upper - lower)
    }
}

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    )!
}

// MARK: - Cizim

/// Butun cizim 1024x1024'luk bir tuvalde tanimlanir; olcek en sonda uygulanir.
let canvas: CGFloat = 1024

// Silme basliginin acisi ve platter merkezi.
let sweepAngle = 34.0 * .pi / 180.0
let center = CGPoint(x: 512, y: 500)
let platterRadius: CGFloat = 258

// Capraz cizginin yon ve normal vektorleri.
let dir = CGVector(dx: cos(sweepAngle), dy: sin(sweepAngle))
let normal = CGVector(dx: -sin(sweepAngle), dy: cos(sweepAngle))
// Cizgi merkezin biraz altindan gecsin ki saglam kisim daha genis gorunsun.
let lineOrigin = CGPoint(x: center.x - normal.dx * 26, y: center.y - normal.dy * 26)

/// Cizginin bir tarafini kaplayan cok buyuk dortgen — yari duzlem kirpmasi icin.
func halfPlane(positiveSide: Bool) -> CGPath {
    let far: CGFloat = 3000
    let sign: CGFloat = positiveSide ? 1 : -1
    let a = CGPoint(x: lineOrigin.x - dir.dx * far, y: lineOrigin.y - dir.dy * far)
    let b = CGPoint(x: lineOrigin.x + dir.dx * far, y: lineOrigin.y + dir.dy * far)
    let offset = CGVector(dx: normal.dx * far * sign, dy: normal.dy * far * sign)

    let path = CGMutablePath()
    path.move(to: a)
    path.addLine(to: b)
    path.addLine(to: CGPoint(x: b.x + offset.dx, y: b.y + offset.dy))
    path.addLine(to: CGPoint(x: a.x + offset.dx, y: a.y + offset.dy))
    path.closeSubpath()
    return path
}

/// Bir noktanin cizgiye gore isaretli uzakligi. Pozitif taraf = silinmis taraf.
func signedDistance(_ point: CGPoint) -> CGFloat {
    (point.x - lineOrigin.x) * normal.dx + (point.y - lineOrigin.y) * normal.dy
}

func drawIcon(into ctx: CGContext) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // --- Zemin: macOS squircle oranlarina yakin yuvarlatilmis kare ---------
    let plate = CGRect(x: 92, y: 92, width: 840, height: 840)
    let platePath = CGPath(
        roundedRect: plate, cornerWidth: 188, cornerHeight: 188, transform: nil
    )

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0x3C4757), rgb(0x1D242E), rgb(0x0E1218)], [0, 0.55, 1]),
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )
    // Ust kenarda hafif isik — zemine derinlik verir.
    ctx.drawRadialGradient(
        gradient([rgb(0xFFFFFF, 0.13), rgb(0xFFFFFF, 0)], [0, 1]),
        startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 900), endRadius: 520,
        options: []
    )
    ctx.restoreGState()

    // Ince kenar cizgisi — koyu arka planlarda siluetin kaybolmamasi icin.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    let platterRect = CGRect(
        x: center.x - platterRadius, y: center.y - platterRadius,
        width: platterRadius * 2, height: platterRadius * 2
    )
    let platterPath = CGPath(ellipseIn: platterRect, transform: nil)

    // --- Diskin saglam kalan yarisi ---------------------------------------
    ctx.saveGState()
    ctx.addPath(platterPath)
    ctx.clip()
    ctx.addPath(halfPlane(positiveSide: false))
    ctx.clip()

    ctx.drawLinearGradient(
        gradient([rgb(0xFFFFFF), rgb(0xD5DDE8), rgb(0xA9B5C6)], [0, 0.5, 1]),
        start: CGPoint(x: platterRect.minX, y: platterRect.maxY),
        end: CGPoint(x: platterRect.maxX, y: platterRect.minY),
        options: []
    )

    // Platter uzerindeki es merkezli izler.
    ctx.setLineWidth(3)
    for radius in stride(from: platterRadius - 26, to: 96.0, by: -34) {
        ctx.setStrokeColor(rgb(0x5C6B80, 0.22))
        ctx.addEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // --- Dagilan taraf: disk piksellere ayrilir ---------------------------
    ctx.saveGState()
    ctx.addPath(platterPath)
    ctx.clip()

    var rng = Random(seed: 0x5EED_1234)
    let step: CGFloat = 34
    var y = platterRect.minY
    while y < platterRect.maxY {
        var x = platterRect.minX
        while x < platterRect.maxX {
            // Izgarayi hafifce bozarak makine isi gorunumden kacin.
            let jitterX = CGFloat(rng.next(-7, 7))
            let jitterY = CGFloat(rng.next(-7, 7))
            let point = CGPoint(x: x + step / 2 + jitterX, y: y + step / 2 + jitterY)
            let distance = signedDistance(point)

            if distance > 0 {
                // Cizgiden uzaklastikca parcalar kuculur ve seffaflasir.
                let fade = min(distance / 300, 1)
                let alpha = max(0, 1 - fade * 1.15) * rng.next(0.55, 1.0)
                if alpha > 0.04 {
                    let size = step * CGFloat(0.72 - fade * 0.34) * CGFloat(rng.next(0.7, 1.15))
                    ctx.setFillColor(rgb(0xD8E0EA, alpha))
                    ctx.fill(CGRect(
                        x: point.x - size / 2, y: point.y - size / 2,
                        width: size, height: size
                    ))
                }
            } else {
                _ = rng.next()  // Akisi her iki dalda ayni tutmak icin.
            }
            x += step
        }
        y += step
    }
    ctx.restoreGState()

    // --- Mil deligi (yalnizca saglam tarafta) ------------------------------
    ctx.saveGState()
    ctx.addPath(halfPlane(positiveSide: false))
    ctx.clip()
    ctx.setFillColor(rgb(0x171D26))
    ctx.fillEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
    ctx.setStrokeColor(rgb(0x8C99AB, 0.55))
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
    ctx.restoreGState()

    // --- Silme basligi: platteri kesen parlak capraz cizgi ------------------
    let reach: CGFloat = 372
    let lineStart = CGPoint(x: lineOrigin.x - dir.dx * reach, y: lineOrigin.y - dir.dy * reach)
    let lineEnd = CGPoint(x: lineOrigin.x + dir.dx * reach, y: lineOrigin.y + dir.dy * reach)

    // Once genis, yumusak bir parilti; sonra keskin cekirdek.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xFF3B30, 0.28))
    ctx.setLineWidth(34)
    ctx.move(to: lineStart)
    ctx.addLine(to: lineEnd)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(15)
    ctx.addPath({
        let path = CGMutablePath()
        path.move(to: lineStart)
        path.addLine(to: lineEnd)
        return path
    }())
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0xFF9500), rgb(0xFF3B30), rgb(0xFF2D55)], [0, 0.5, 1]),
        start: lineStart, end: lineEnd, options: []
    )
    ctx.restoreGState()
}

// MARK: - Cikti

func renderPNG(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Bitmap olusturulamadi (\(size)px)") }

    NSGraphicsContext.saveGraphicsState()
    let nsContext = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsContext
    let ctx = nsContext.cgContext

    let scale = CGFloat(size) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(into: ctx)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG kodlanamadi (\(size)px)")
    }
    return data
}

let outputRoot = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")

let iconset = outputRoot.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil'in bekledigi standart isimlendirme.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let data = renderPNG(size: variant.size)
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}
print("iconset yazildi: \(iconset.path)")

// Onizleme icin tek bir buyuk PNG.
try renderPNG(size: 512).write(to: outputRoot.appendingPathComponent("AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path,
    "-o", outputRoot.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil basarisiz\n".utf8))
    exit(1)
}
print("icns yazildi: \(outputRoot.appendingPathComponent("AppIcon.icns").path)")
