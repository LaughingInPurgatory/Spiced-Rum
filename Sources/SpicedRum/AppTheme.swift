import SwiftUI

enum RumTheme {
    static let background = Color(red: 0.075, green: 0.078, blue: 0.082)
    static let content = Color(red: 0.118, green: 0.122, blue: 0.129)
    static let surface = Color(red: 0.165, green: 0.169, blue: 0.177)
    static let surfaceMuted = Color(red: 0.145, green: 0.149, blue: 0.157)
    static let accent = Color(red: 0.66, green: 0.78, blue: 0.98)
    static let onAccent = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let selection = accent.opacity(0.16)
}

struct RumBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RumTheme.background, Color(red: 0.045, green: 0.055, blue: 0.078)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(RumTheme.accent.opacity(0.10))
                .frame(width: 460, height: 460)
                .blur(radius: 125)
                .offset(x: 330, y: -270)
            Circle()
                .fill(.white.opacity(0.035))
                .frame(width: 390, height: 390)
                .blur(radius: 115)
                .offset(x: -360, y: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    func rumGlassSurface(cornerRadius: CGFloat = 12, fallback: Color = RumTheme.surface) -> some View {
        modifier(RumGlassSurface(cornerRadius: cornerRadius, fallback: fallback))
    }

    func rumGlassControl(cornerRadius: CGFloat = 9, active: Bool = false) -> some View {
        modifier(RumGlassControl(cornerRadius: cornerRadius, active: active))
    }
}

private struct RumGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fallback: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(fallback, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.07))
                }
        }
    }
}

private struct RumGlassControl: ViewModifier {
    let cornerRadius: CGFloat
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(active ? RumTheme.surface : .clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.10))
                    }
                }
        }
    }
}

struct RumGlassSelection: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(RumTheme.accent.opacity(0.28)).interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                content
                    .background(RumTheme.selection, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(RumTheme.accent.opacity(0.14))
                    }
            }
        } else {
            content
        }
    }
}

struct RumPrimaryButtonGlass: ViewModifier {
    let isPressed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(RumTheme.accent.opacity(isPressed ? 0.62 : 0.82)).interactive(), in: Capsule())
        } else {
            content.background(RumTheme.accent.opacity(isPressed ? 0.82 : 1), in: Capsule())
        }
    }
}
