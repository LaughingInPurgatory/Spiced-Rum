import AppKit
import CoreGraphics
import Foundation
import ImageIO

private let side = 1024

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func render(background: Bool) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)

    if background {
        // macOS does not consistently mask legacy ICNS icons in the Dock.
        // Bake the familiar rounded-square silhouette into every exported size.
        let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                          cornerWidth: 220, cornerHeight: 220, transform: nil)
        context.addPath(tile)
        context.clip()

        context.setFillColor(color(0.075, 0.025, 0.035))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let colors = [color(0.31, 0.095, 0.055), color(0.075, 0.025, 0.035)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 120, y: 120), end: CGPoint(x: 880, y: 930), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.setFillColor(color(1, 0.47, 0.13, 0.14))
        context.fillEllipse(in: CGRect(x: 222, y: 185, width: 580, height: 580))
    }

    let glass = CGMutablePath()
    glass.move(to: CGPoint(x: 278, y: 198))
    glass.addLine(to: CGPoint(x: 746, y: 198))
    glass.addLine(to: CGPoint(x: 664, y: 790))
    glass.addCurve(to: CGPoint(x: 604, y: 847), control1: CGPoint(x: 659, y: 827), control2: CGPoint(x: 638, y: 847))
    glass.addLine(to: CGPoint(x: 420, y: 847))
    glass.addCurve(to: CGPoint(x: 360, y: 790), control1: CGPoint(x: 386, y: 847), control2: CGPoint(x: 365, y: 827))
    glass.closeSubpath()

    context.addPath(glass)
    context.setFillColor(color(0.98, 0.92, 0.81, background ? 0.16 : 0.14))
    context.fillPath()

    context.saveGState()
    context.addPath(glass)
    context.clip()
    let liquor = CGMutablePath()
    liquor.move(to: CGPoint(x: 328, y: 520))
    liquor.addQuadCurve(to: CGPoint(x: 696, y: 520), control: CGPoint(x: 512, y: 491))
    liquor.addLine(to: CGPoint(x: 648, y: 776))
    liquor.addCurve(to: CGPoint(x: 610, y: 808), control1: CGPoint(x: 645, y: 799), control2: CGPoint(x: 631, y: 808))
    liquor.addLine(to: CGPoint(x: 414, y: 808))
    liquor.addCurve(to: CGPoint(x: 376, y: 776), control1: CGPoint(x: 393, y: 808), control2: CGPoint(x: 379, y: 799))
    liquor.closeSubpath()
    let liquorGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [color(0.99, 0.68, 0.29), color(0.72, 0.31, 0.075)] as CFArray,
                                    locations: [0, 1])!
    context.addPath(liquor)
    context.clip()
    context.drawLinearGradient(liquorGradient, start: CGPoint(x: 480, y: 500), end: CGPoint(x: 550, y: 840), options: [])
    context.restoreGState()

    context.addPath(glass)
    context.setStrokeColor(color(1, 0.95, 0.85, 0.96))
    context.setLineWidth(28)
    context.setLineJoin(.round)
    context.strokePath()

    let rim = CGRect(x: 278, y: 157, width: 468, height: 84)
    context.setFillColor(color(0.16, 0.135, 0.11, 0.85))
    context.fillEllipse(in: rim)
    context.setStrokeColor(color(1, 0.95, 0.85, 0.98))
    context.setLineWidth(25)
    context.strokeEllipse(in: rim)

    let surface = CGMutablePath()
    surface.move(to: CGPoint(x: 330, y: 520))
    surface.addQuadCurve(to: CGPoint(x: 694, y: 520), control: CGPoint(x: 512, y: 491))
    context.addPath(surface)
    context.setStrokeColor(color(1, 0.83, 0.55, 0.88))
    context.setLineWidth(10)
    context.setLineCap(.round)
    context.strokePath()

    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: 340, y: 282))
    shine.addLine(to: CGPoint(x: 366, y: 472))
    context.addPath(shine)
    context.setStrokeColor(color(1, 1, 1, 0.7))
    context.setLineWidth(17)
    context.setLineCap(.round)
    context.strokePath()
    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "SpicedRumIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination."])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "SpicedRumIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG artwork."])
    }
}

private func resized(_ image: CGImage, to side: Int) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

@main
private struct GenerateAppIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: generate-app-icon <ShotglassMark.png> <AppIcon.png> <iconset-directory>")
        }
        let mark = render(background: false)
        let appIcon = render(background: true)
        try writePNG(mark, to: URL(fileURLWithPath: CommandLine.arguments[1]))
        try writePNG(appIcon, to: URL(fileURLWithPath: CommandLine.arguments[2]))

        let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        let variants: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, pixels) in variants {
            try writePNG(resized(appIcon, to: pixels), to: iconsetURL.appendingPathComponent(name))
        }
    }
}
