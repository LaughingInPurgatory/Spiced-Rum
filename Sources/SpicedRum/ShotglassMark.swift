import AppKit
import SwiftUI

struct ShotglassMark: View {
    private static let artwork: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ShotglassMark.png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit()
            } else {
                ZStack {
                    ShotglassCup().fill(Color(red: 0.96, green: 0.87, blue: 0.73).opacity(0.12))
                    ShotglassLiquid().fill(Color(red: 0.94, green: 0.64, blue: 0.29))
                    ShotglassCup().stroke(Color(red: 0.96, green: 0.87, blue: 0.73), style: StrokeStyle(lineWidth: 2.8, lineJoin: .round))
                    ShotglassRim().stroke(Color(red: 0.96, green: 0.87, blue: 0.73), style: StrokeStyle(lineWidth: 2.8))
                    Path { path in
                        path.move(to: CGPoint(x: 34, y: 30))
                        path.addLine(to: CGPoint(x: 37, y: 49))
                    }.stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }.aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ShotglassCup: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100) }
        var path = Path()
        path.move(to: p(27.5, 20))
        path.addLine(to: p(72.5, 20))
        path.addLine(to: p(64.5, 78))
        path.addCurve(to: p(59, 84), control1: p(64, 82), control2: p(62, 84))
        path.addLine(to: p(41, 84))
        path.addCurve(to: p(35.5, 78), control1: p(38, 84), control2: p(36, 82))
        path.closeSubpath()
        return path
    }
}

private struct ShotglassLiquid: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100) }
        var path = Path()
        path.move(to: p(32.5, 52))
        path.addQuadCurve(to: p(67.5, 52), control: p(50, 49))
        path.addLine(to: p(64, 76))
        path.addCurve(to: p(60, 79), control1: p(63.7, 78), control2: p(62, 79))
        path.addLine(to: p(40, 79))
        path.addCurve(to: p(36, 76), control1: p(38, 79), control2: p(36.3, 78))
        path.closeSubpath()
        return path
    }
}

private struct ShotglassRim: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.minX + rect.width * 27 / 100,
                               y: rect.minY + rect.height * 16 / 100,
                               width: rect.width * 46 / 100,
                               height: rect.height * 9 / 100))
    }
}
