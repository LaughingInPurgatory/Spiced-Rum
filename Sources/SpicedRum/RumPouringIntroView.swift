import SwiftUI

private let rumGold = Color(red: 0.96, green: 0.62, blue: 0.22)
private let rumHoney = Color(red: 0.91, green: 0.36, blue: 0.08)

struct RumPouringIntroView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bottleTilted = false
    @State private var streamProgress: CGFloat = 0
    @State private var liquidLevel: CGFloat = 0
    @State private var glow = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bottleSize = CGSize(width: min(210, size.width * 0.25), height: min(390, size.height * 0.52))
            let bottleCenter = CGPoint(x: size.width * 0.53, y: size.height * 0.425)
            let bottleAngle = -135.0
            let bottleOutlet = CGPoint(x: bottleSize.width / 2, y: bottleSize.height * 0.05)
            let pourStart = rotatedPoint(bottleOutlet, in: bottleSize, around: bottleCenter, degrees: bottleAngle)
            let glassSize = CGSize(width: 132, height: 174)
            let glassCenter = CGPoint(x: size.width * 0.32, y: size.height * 0.75)
            let glassBottom = glassCenter.y + glassSize.height * 0.47
            let risingSurface = glassCenter.y + glassSize.height * (0.5 - liquidLevel) + 4
            let pourEnd = CGPoint(x: glassCenter.x, y: min(glassBottom, risingSurface))
            ZStack {
                RadialGradient(
                    colors: [RumTheme.surfaceMuted, RumTheme.background],
                    center: UnitPoint(x: 0.58, y: 0.47),
                    startRadius: 20,
                    endRadius: max(size.width, size.height) * 0.78
                )

                ForEach(0..<18, id: \.self) { index in
                    let x = CGFloat((index * 47 + 29) % 97) / 100
                    let y = CGFloat((index * 31 + 13) % 73) / 100
                    Circle()
                        .fill(.white.opacity(index.isMultiple(of: 3) ? 0.10 : 0.045))
                        .frame(width: index.isMultiple(of: 4) ? 3 : 2)
                        .position(x: size.width * x, y: size.height * y)
                }

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, rumGold.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: size.height * 0.32)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(rumGold.opacity(0.22)).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)

                Circle()
                    .fill(RadialGradient(colors: [rumGold.opacity(glow ? 0.16 : 0.07), .clear], center: .center, startRadius: 0, endRadius: 145))
                    .frame(width: 290, height: 290)
                    .position(x: glassCenter.x, y: glassCenter.y)

                RumBottleArtwork()
                    .frame(width: bottleSize.width, height: bottleSize.height)
                    .rotationEffect(.degrees(bottleTilted ? bottleAngle : 0), anchor: .center)
                    .position(x: bottleCenter.x, y: bottleCenter.y)
                    .shadow(color: .black.opacity(0.48), radius: 28, x: 5, y: 22)

                PourStream(start: pourStart, end: pourEnd, progress: streamProgress)
                    .stroke(rumGold.opacity(0.36), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .blur(radius: 9)
                PourStream(start: pourStart, end: pourEnd, progress: streamProgress)
                    .stroke(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), rumGold, rumHoney], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                PourStream(start: pourStart, end: pourEnd, progress: streamProgress)
                    .stroke(.white.opacity(0.58), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                ShotglassArtwork(fillLevel: liquidLevel, glowing: glow)
                    .frame(width: glassSize.width, height: glassSize.height)
                    .position(x: glassCenter.x, y: glassCenter.y)
                    .shadow(color: rumGold.opacity(glow ? 0.32 : 0.12), radius: glow ? 26 : 12, y: 8)

                VStack(spacing: 10) {
                    Text("SPICED-RUM")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(rumGold.opacity(0.92))
                    Text("A little spirit. More play.")
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.91))
                    Text("SETTING THE TABLE")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, max(40, size.height * 0.085))

                Button("Skip intro", action: onFinish)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .buttonStyle(.plain)
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .task {
                guard !reduceMotion else { onFinish(); return }
                withAnimation(.spring(response: 0.95, dampingFraction: 0.78)) { bottleTilted = true }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { streamProgress = 1 }
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.45)) { liquidLevel = 0.59 }
                withAnimation(.easeInOut(duration: 0.8)) { glow = true }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                onFinish()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spiced-Rum startup animation")
    }
}

private func rotatedPoint(_ point: CGPoint, in size: CGSize, around center: CGPoint, degrees: Double) -> CGPoint {
    let radians = degrees * .pi / 180
    let x = point.x - size.width / 2
    let y = point.y - size.height / 2
    return CGPoint(
        x: center.x + x * cos(radians) - y * sin(radians),
        y: center.y + x * sin(radians) + y * cos(radians)
    )
}

private struct RumBottleArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                BottleShape()
                    .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.10, blue: 0.045), Color(red: 0.52, green: 0.22, blue: 0.06), Color(red: 0.22, green: 0.085, blue: 0.035)], startPoint: .leading, endPoint: .trailing))
                BottleShape()
                    .fill(LinearGradient(colors: [rumGold.opacity(0.22), .clear, Color(red: 0.98, green: 0.56, blue: 0.13).opacity(0.20)], startPoint: .top, endPoint: .bottom))
                BottleShape().stroke(.white.opacity(0.40), lineWidth: 1.6)
                BottleShape().stroke(LinearGradient(colors: [.white.opacity(0.40), .clear, rumGold.opacity(0.38)], startPoint: .leading, endPoint: .trailing), lineWidth: 3)

                ZStack {
                    Ellipse().fill(Color(red: 0.075, green: 0.033, blue: 0.018))
                    Ellipse().stroke(rumGold.opacity(0.82), lineWidth: 2)
                    Ellipse().stroke(.white.opacity(0.28), lineWidth: 0.8).padding(3)
                }
                .frame(width: 48, height: 18)
                .position(x: size.width / 2, y: size.height * 0.05)
                Capsule().fill(rumGold.opacity(0.7))
                    .frame(width: 60, height: 5)
                    .position(x: size.width / 2, y: size.height * 0.15)

                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: size.height * 0.48)
                    .offset(x: -56, y: size.height * 0.065)

                VStack(spacing: 3) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 15, weight: .light))
                    Text("SPICED")
                        .font(.system(size: 12, weight: .black, design: .serif))
                        .tracking(1.6)
                    Text("RUM")
                        .font(.system(size: 25, weight: .black, design: .serif))
                        .tracking(3)
                    Rectangle().fill(Color(red: 0.46, green: 0.22, blue: 0.08)).frame(width: 52, height: 1)
                    Text("AGED · DISTILLED")
                        .font(.system(size: 5, weight: .semibold))
                        .tracking(1)
                }
                .foregroundStyle(Color(red: 0.35, green: 0.16, blue: 0.065))
                .frame(width: 112, height: 96)
                .background(LinearGradient(colors: [Color(red: 0.91, green: 0.75, blue: 0.48), Color(red: 0.73, green: 0.50, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.42), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .offset(y: size.height * 0.15)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.37, y: rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.width * 0.63, y: rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.width * 0.63, y: rect.height * 0.22))
        path.addCurve(to: CGPoint(x: rect.width * 0.79, y: rect.height * 0.32), control1: CGPoint(x: rect.width * 0.65, y: rect.height * 0.27), control2: CGPoint(x: rect.width * 0.73, y: rect.height * 0.27))
        path.addCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.43), control1: CGPoint(x: rect.width * 0.88, y: rect.height * 0.36), control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.91))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.81, y: rect.height * 0.97), control: CGPoint(x: rect.width * 0.88, y: rect.height * 0.97))
        path.addLine(to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.97))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.91), control: CGPoint(x: rect.width * 0.12, y: rect.height * 0.97))
        path.addLine(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.43))
        path.addCurve(to: CGPoint(x: rect.width * 0.21, y: rect.height * 0.32), control1: CGPoint(x: rect.width * 0.12, y: rect.height * 0.38), control2: CGPoint(x: rect.width * 0.12, y: rect.height * 0.36))
        path.addCurve(to: CGPoint(x: rect.width * 0.37, y: rect.height * 0.22), control1: CGPoint(x: rect.width * 0.27, y: rect.height * 0.27), control2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.27))
        path.closeSubpath()
        return path
    }
}

private struct PourStream: Shape {
    var start: CGPoint
    var end: CGPoint
    var progress: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, end.y) }
        set {
            progress = newValue.first
            end.y = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return path }
        let origin = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
        let target = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
        let tip = CGPoint(x: origin.x + (target.x - origin.x) * fraction, y: origin.y + (target.y - origin.y) * fraction)
        let dx = tip.x - origin.x
        let dy = tip.y - origin.y
        path.move(to: origin)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: origin.x + dx * 0.30, y: origin.y + dy * 0.26),
            control2: CGPoint(x: tip.x - dx * 0.12, y: tip.y - dy * 0.08)
        )
        return path
    }
}

private struct ShotglassArtwork: View {
    let fillLevel: CGFloat
    let glowing: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                GlassShape().fill(.white.opacity(0.035))
                LiquidShape(level: fillLevel)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.75, blue: 0.27), rumGold, rumHoney], startPoint: .top, endPoint: .bottom))
                    .clipShape(GlassShape())
                if fillLevel > 0.01 {
                    Capsule().fill(.white.opacity(0.48))
                        .frame(width: size.width * 0.28, height: 2)
                        .position(x: size.width * 0.47, y: size.height * (1 - fillLevel) + 4)
                    Circle().fill(.white.opacity(glowing ? 0.62 : 0.28))
                        .frame(width: 4, height: 4)
                        .position(x: size.width * 0.70, y: size.height * (1 - fillLevel) + 15)
                }
                GlassShape().stroke(LinearGradient(colors: [.white.opacity(0.82), .white.opacity(0.12), .white.opacity(0.62)], startPoint: .leading, endPoint: .trailing), lineWidth: 2)
                Ellipse().stroke(.white.opacity(0.72), lineWidth: 2)
                    .frame(width: size.width * 0.72, height: 12)
                    .position(x: size.width / 2, y: size.height * 0.055)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.28))
                    .frame(width: size.width * 0.46, height: 3)
                    .position(x: size.width / 2, y: size.height * 0.955)
            }
        }
    }
}

private struct GlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.14, y: rect.height * 0.055))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.055))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.91))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.97), control: CGPoint(x: rect.width * 0.76, y: rect.height * 0.97))
        path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.97))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.91), control: CGPoint(x: rect.width * 0.24, y: rect.height * 0.97))
        path.closeSubpath()
        return path
    }
}

private struct LiquidShape: Shape {
    var level: CGFloat
    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        let surfaceY = rect.maxY - rect.height * level
        path.move(to: CGPoint(x: rect.minX, y: surfaceY + 3))
        path.addCurve(to: CGPoint(x: rect.maxX, y: surfaceY), control1: CGPoint(x: rect.width * 0.3, y: surfaceY - 5), control2: CGPoint(x: rect.width * 0.7, y: surfaceY + 6))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
