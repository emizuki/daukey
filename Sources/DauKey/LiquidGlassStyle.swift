import SwiftUI

// MARK: - Liquid Glass Design Tokens & Styles

enum LiquidGlass {
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 8
    static let smallCornerRadius: CGFloat = 6

    /// Creates a specular highlight gradient simulating top-left light hitting glass edges.
    static func specularGradient(isDark: Bool, isHovered: Bool = false) -> LinearGradient {
        if isDark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(isHovered ? 0.35 : 0.22),
                    Color.white.opacity(isHovered ? 0.12 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(isHovered ? 0.85 : 0.65),
                    Color.white.opacity(isHovered ? 0.25 : 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Liquid Glass Card Modifier

struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = LiquidGlass.cardCornerRadius

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? ZincPalette.zinc900 : ZincPalette.zinc100)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? ZincPalette.zinc800.opacity(0.40)
                                : ZincPalette.zinc100.opacity(0.65)
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LiquidGlass.specularGradient(isDark: colorScheme == .dark),
                        lineWidth: 0.75
                    )
            }
    }
}

// MARK: - Liquid Glass Border Modifier

struct LiquidGlassBorderModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = LiquidGlass.controlCornerRadius
    var isHovered: Bool = false
    var lineWidth: CGFloat = 0.75

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: isHovered),
                    lineWidth: lineWidth
                )
        }
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = LiquidGlass.cardCornerRadius) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassBorder(cornerRadius: CGFloat = LiquidGlass.controlCornerRadius, isHovered: Bool = false, lineWidth: CGFloat = 0.75) -> some View {
        modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius, isHovered: isHovered, lineWidth: lineWidth))
    }
}

// MARK: - Liquid Glass Toolbar Icon Button

struct ToolbarIconButton: View {
    let icon: String
    let helpText: String
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    init(icon: String, helpText: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.helpText = helpText
        self.isDisabled = isDisabled
        self.action = action
    }
    private var buttonFillColor: Color {
        if isDisabled {
            return Color.clear
        }
        if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.85)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.45)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(buttonFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: isHovered),
                            lineWidth: isDisabled ? 0 : 0.75
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
        .help(helpText)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
