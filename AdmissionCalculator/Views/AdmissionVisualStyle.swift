import SwiftUI

enum AdmissionStyle {
    static let cornerRadius: CGFloat = 28
    static let compactRadius: CGFloat = 18
    static let hairline = Color.white.opacity(0.16)
    static let pageBackground = Color(red: 0.925, green: 0.925, blue: 0.935)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let darkTextPrimary = Color(red: 0.05, green: 0.05, blue: 0.055)
    static let darkTextSecondary = Color.black.opacity(0.58)

    static let aurora: [Color] = [
        Color(red: 0.07, green: 0.08, blue: 0.10),
        Color(red: 0.19, green: 0.13, blue: 0.22),
        Color(red: 0.08, green: 0.18, blue: 0.18),
        Color(red: 0.12, green: 0.11, blue: 0.18)
    ]

    static let blackGlass: [Color] = [
        Color(red: 0.02, green: 0.02, blue: 0.025),
        Color(red: 0.09, green: 0.10, blue: 0.13),
        Color(red: 0.02, green: 0.02, blue: 0.025)
    ]

    static let pinkMist: [Color] = [
        Color(red: 0.96, green: 0.55, blue: 0.80),
        Color(red: 0.88, green: 0.13, blue: 0.50),
        Color(red: 0.18, green: 0.05, blue: 0.18),
        Color(red: 0.78, green: 0.64, blue: 0.76)
    ]

    static let mintNight: [Color] = [
        Color(red: 0.68, green: 0.91, blue: 0.78),
        Color(red: 0.10, green: 0.14, blue: 0.18),
        Color(red: 0.02, green: 0.03, blue: 0.07),
        Color(red: 0.66, green: 0.86, blue: 0.76)
    ]

    static let citrus: [Color] = [
        Color(red: 1.00, green: 0.77, blue: 0.26),
        Color(red: 0.98, green: 0.33, blue: 0.24),
        Color(red: 0.31, green: 0.12, blue: 0.19)
    ]

    static let bluePulse: [Color] = [
        Color(red: 0.10, green: 0.34, blue: 0.95),
        Color(red: 0.02, green: 0.04, blue: 0.12),
        Color(red: 0.53, green: 0.91, blue: 0.82)
    ]

    static let lilac: [Color] = [
        Color(red: 0.85, green: 0.65, blue: 0.90),
        Color(red: 0.54, green: 0.22, blue: 0.82),
        Color(red: 0.12, green: 0.07, blue: 0.18)
    ]

    static let roseSlate: [Color] = [
        Color(red: 0.95, green: 0.56, blue: 0.62),
        Color(red: 0.46, green: 0.37, blue: 0.48),
        Color(red: 0.08, green: 0.09, blue: 0.12)
    ]

    static func titleFont(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func sectionFont() -> Font {
        .system(.headline, design: .rounded).weight(.bold)
    }

    static func bodyFont() -> Font {
        .system(.subheadline, design: .rounded)
    }
}

struct AdmissionPageBackground: View {
    var body: some View {
        Color(red: 0.925, green: 0.925, blue: 0.935)
            .ignoresSafeArea()
    }
}

struct AdmissionHeroCard<Content: View>: View {
    let colors: [Color]
    let content: Content

    init(colors: [Color], @ViewBuilder content: () -> Content) {
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color.white.opacity(0.24), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 240
            )
            .blendMode(.screen)
            content
                .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous)
                .stroke(AdmissionStyle.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }
}

struct AdmissionGradientCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let colors: [Color]
    let foreground: Color
    let secondary: Color
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        colors: [Color],
        foreground: Color = AdmissionStyle.textPrimary,
        secondary: Color = AdmissionStyle.textSecondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.colors = colors
        self.foreground = foreground
        self.secondary = secondary
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(foreground)
                        .background(foreground.opacity(0.14), in: Circle())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AdmissionStyle.sectionFont())
                        .foregroundStyle(foreground)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .font(AdmissionStyle.bodyFont())
            .tint(foreground)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous)
                .stroke(AdmissionStyle.hairline, lineWidth: 1)
        )
        .foregroundStyle(foreground)
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

struct AdmissionMetricPill: View {
    let title: String
    let value: String
    var foreground: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(foreground.opacity(0.66))
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(foreground.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(foreground.opacity(0.16), lineWidth: 1))
    }
}

struct AdmissionAnimatedPercentText: View {
    let value: Double
    var font: Font = .system(size: 44, weight: .black, design: .rounded)
    var foreground: Color = .white
    var startDelayMilliseconds = 0
    var finalLabel: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedPercent = 0
    @State private var hasSettled = false

    private var targetPercent: Int {
        min(100, max(0, Int((value * 100).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(displayedPercent)")
                    .contentTransition(.numericText(value: Double(displayedPercent)))
                Text("%")
            }
            .font(font)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .accessibilityLabel("概率 \(targetPercent)%")

            if let finalLabel {
                Text(hasSettled ? finalLabel : "估算生成中")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(foreground.opacity(hasSettled ? 0.70 : 0.52))
                    .contentTransition(.opacity)
            }
        }
        .task(id: targetPercent) {
            await animateToTarget()
        }
    }

    @MainActor
    private func animateToTarget() async {
        displayedPercent = 0
        hasSettled = false

        if reduceMotion {
            displayedPercent = targetPercent
            hasSettled = true
            return
        }

        if startDelayMilliseconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(startDelayMilliseconds) * 1_000_000)
        }

        guard targetPercent > 0 else {
            hasSettled = true
            return
        }

        for nextValue in 1...targetPercent {
            guard !Task.isCancelled else { return }
            let progress = Double(nextValue) / Double(max(targetPercent, 1))
            let delay = 0.014 + progress * 0.070
            withAnimation(.linear(duration: min(0.12, delay * 0.92))) {
                displayedPercent = nextValue
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.easeOut(duration: 0.24)) {
            hasSettled = true
        }
    }
}

struct AdmissionProbabilityCard: View {
    let title: String
    let subtitle: String
    let value: Double
    let colors: [Color]
    var countText: String? = nil
    var delayIndex: Int = 0
    var symbolName: String = "waveform.path.ecg"
    var fontSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.10), in: Circle())
            }

            AdmissionAnimatedPercentText(
                value: value,
                font: .system(size: fontSize, weight: .black, design: .rounded),
                startDelayMilliseconds: delayIndex * 130,
                finalLabel: "估算定格"
            )

            if let countText {
                Text(countText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .admissionSmallCard(colors: colors)
    }
}

struct AdmissionSoftButtonStyle: ButtonStyle {
    let colors: [Color]
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(foreground.opacity(0.16), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct AdmissionQuietButtonStyle: ButtonStyle {
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(foreground.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(foreground.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    func admissionPage() -> some View {
        padding(.bottom, 24)
            .padding(.top, 16)
            .background(AdmissionPageBackground())
            .scrollContentBackground(.hidden)
    }

    func admissionSmallCard(colors: [Color], foreground: Color = .white) -> some View {
        padding(12)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                    .stroke(foreground.opacity(0.16), lineWidth: 1)
            )
    }
}
