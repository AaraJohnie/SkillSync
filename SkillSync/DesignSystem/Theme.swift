import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Ink {
    static let bg = adaptive(
        light: UIColor(red: 1.0, green: 0.945, blue: 0.957, alpha: 1),
        dark: UIColor(red: 0.110, green: 0.047, blue: 0.078, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55),
        dark: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    )
    static let card = adaptive(
        light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.42),
        dark: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.10)
    )
    static let gold = adaptive(
        light: UIColor(red: 0.949, green: 0.239, blue: 0.478, alpha: 1),
        dark: UIColor(red: 0.965, green: 0.353, blue: 0.561, alpha: 1)
    )
    static let teal = adaptive(
        light: UIColor(red: 0.620, green: 0.220, blue: 0.400, alpha: 1),
        dark: UIColor(red: 0.965, green: 0.639, blue: 0.761, alpha: 1)
    )
    static let coral = adaptive(
        light: UIColor(red: 0.820, green: 0.220, blue: 0.340, alpha: 1),
        dark: UIColor(red: 0.965, green: 0.478, blue: 0.580, alpha: 1)
    )
    static let paper = adaptive(
        light: UIColor(red: 0.145, green: 0.078, blue: 0.110, alpha: 1),
        dark: UIColor(red: 0.996, green: 0.945, blue: 0.961, alpha: 1)
    )
    static let mute = adaptive(
        light: UIColor(red: 0.541, green: 0.400, blue: 0.455, alpha: 1),
        dark: UIColor(red: 0.820, green: 0.655, blue: 0.722, alpha: 1)
    )
    static let line = adaptive(
        light: UIColor.white.withAlphaComponent(0.72),
        dark: UIColor.white.withAlphaComponent(0.16)
    )
    /// Light ink for text sitting on the pink accent.
    static let stamp = Color.white

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum Typeface {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func title() -> Font {
        .system(.title2, design: .serif).weight(.semibold)
    }

    static func body() -> Font {
        .system(.body, design: .default)
    }
}

struct PaperCard<Content: View>: View {
    var padding: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .shadow(color: Ink.gold.opacity(colorScheme == .light ? 0.14 : 0.22), radius: 18, y: 8)
    }
}

struct SkillChip: View {
    var name: String
    var level: SkillLevel?
    var tone: ChipTone = .teal

    enum ChipTone {
        case teal, gold, mute
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
            if let level {
                Text(level.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color.opacity(0.9))
            }
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
    }

    private var color: Color {
        switch tone {
        case .teal: Ink.teal
        case .gold: Ink.gold
        case .mute: Ink.mute
        }
    }
}

struct SynergyRing: View {
    var score: Int
    var size: CGFloat = 64
    var emphasized: Bool = false
    var starCount: Int = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var weave = 0.0
    @State private var glow = false
    @State private var breath = false

    var body: some View {
        let drawn = CGFloat(progress) * CGFloat(score) / 100
        let shown = Int((progress * Double(score)).rounded())
        ZStack {
            Circle()
                .fill(Ink.gold.opacity(breath ? 0.07 : 0.02))
            Circle()
                .stroke(Ink.line, lineWidth: 6)
            if !reduceMotion {
                SynergyWeave(progress: weave, size: size, compact: !emphasized)
            }
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(Ink.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? Ink.gold.opacity(0.65) : .clear, radius: glow ? 10 : 0)
            constellation
            VStack(spacing: 0) {
                Text("\(shown)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.paper)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Ink.gold)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(score) percent synergy")
        .task(id: score) { await play() }
    }

    private var constellation: some View {
        let ticks = min(max(starCount, 0), 4)
        return ForEach(0..<ticks, id: \.self) { index in
            let fraction = Double(index + 1) / Double(ticks + 1)
            let lit = progress >= fraction * 0.85
            Circle()
                .fill(Ink.gold.opacity(lit ? 0.95 : 0))
                .frame(width: emphasized ? 5 : 3.5, height: emphasized ? 5 : 3.5)
                .offset(y: -(size / 2))
                .rotationEffect(.degrees(-90 + fraction * 360 * Double(score) / 100))
        }
    }

    @MainActor
    private func play() async {
        progress = 0
        weave = 0
        glow = false
        breath = false
        if reduceMotion {
            progress = 1
            weave = 1
            return
        }
        if emphasized {
            withAnimation(.easeInOut(duration: 0.9)) { weave = 1 }
            try? await Task.sleep(for: .milliseconds(550))
        } else {
            withAnimation(.easeOut(duration: 0.28)) { weave = 1 }
        }
        withAnimation(.spring(duration: emphasized ? 0.85 : 0.62, bounce: 0.14)) {
            progress = 1
        }
        if score >= 80 {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeInOut(duration: 0.4)) { glow = true }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.6)) { glow = false }
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            breath = true
        }
    }
}

struct SynergyWeave: View {
    var progress: Double
    var size: CGFloat
    var compact: Bool

    var body: some View {
        let radius = size * (compact ? 0.28 : 0.38)
        let mote = compact ? 5.0 : 7.0
        let goldAngle = 270.0 + progress * 90.0
        let tealAngle = 90.0 - progress * 90.0
        ZStack {
            moteDot(Ink.gold, size: mote)
                .offset(y: -radius)
                .rotationEffect(.degrees(goldAngle))
            moteDot(Ink.teal, size: mote)
                .offset(y: -radius)
                .rotationEffect(.degrees(tealAngle))
        }
        .opacity(progress < 0.02 ? 0 : (progress > 0.92 ? 0.15 : 1))
        .allowsHitTesting(false)
    }

    private func moteDot(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.7), radius: 4)
    }
}

struct ListAppear: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.easeOut(duration: 0.35).delay(Double(min(index, 12)) * 0.04)) {
                    shown = true
                }
            }
    }
}

struct SoftSheetIntro: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.easeOut(duration: 0.28)) { shown = true }
            }
    }
}

struct SoftPop: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.92)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.spring(duration: 0.45, bounce: 0.18)) { shown = true }
            }
    }
}

struct RoleUnderline: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Ink.gold)
                    .frame(height: 1)
                    .scaleEffect(x: drawn || reduceMotion ? 1 : 0, anchor: .leading)
            }
            .onAppear {
                if reduceMotion {
                    drawn = true
                    return
                }
                withAnimation(.easeOut(duration: 0.45).delay(0.12)) { drawn = true }
            }
    }
}

extension View {
    func listAppear(index: Int) -> some View {
        modifier(ListAppear(index: index))
    }

    func softSheetIntro() -> some View {
        modifier(SoftSheetIntro())
    }

    func softPop() -> some View {
        modifier(SoftPop())
    }

    func roleUnderline() -> some View {
        modifier(RoleUnderline())
    }
}

struct InitialsMark: View {
    var name: String
    var initials: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .semibold, design: .serif))
            .foregroundStyle(Ink.stamp)
            .frame(width: size, height: size)
            .background(hue, in: Circle())
    }

    private var hue: Color {
        let palette = [Ink.teal, Ink.gold, Ink.coral, Color(red: 0.62, green: 0.72, blue: 0.98)]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Ink.mute)
    }
}

struct PrimaryButton: View {
    var title: String
    var fill: Color = Ink.gold
    var ink: Color = Ink.stamp
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FieldLabel: View {
    var title: String
    var text: Binding<String>
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    var disablesAutocorrection: Bool = true
    var allowsClipboard: Bool = false
    var addressKeys: Bool = false
    var axis: Axis = .horizontal
    var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.mute)
                Spacer(minLength: 8)
                if allowsClipboard {
                    clipboardControls
                }
            }
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text, axis: axis)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(disablesAutocorrection)
            .keyboardType(keyboard)
            .toolbar {
                if addressKeys {
                    ToolbarItemGroup(placement: .keyboard) {
                        addressKey("@")
                        addressKey(".")
                        addressKey("_")
                        addressKey("-")
                        Spacer()
                    }
                }
            }
            .lineLimit(axis == .vertical ? 2...4 : 1...1)
            .foregroundStyle(Ink.paper)
            .padding(12)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func addressKey(_ symbol: String) -> some View {
        Button(symbol) {
            text.wrappedValue.append(symbol)
        }
        .font(.title3.weight(.semibold))
        .accessibilityLabel("Insert \(symbol)")
    }

    private var clipboardControls: some View {
        Button {
            guard let value = UIPasteboard.general.string else { return }
            text.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Ink.gold.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Ink.gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste")
    }
}

struct TrustMark: View {
    var trust: TrustLevel

    var body: some View {
        if trust != .unverified {
            Label(trust.label, systemImage: trust == .trusted ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(trust == .trusted ? Ink.teal : Ink.gold)
        }
    }
}

struct ProofChip: View {
    var urlString: String?

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text(ProofLink.hostLabel(urlString) ?? "Proof")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.gold)
            }
            .softPop()
        }
    }
}

struct SkillGapRadar: View {
    var required: [String]
    var owned: [UserSkill]

    var body: some View {
        let missing = GapAnalyzer.missing(required: required, owned: owned)
        let covered = max(required.count - missing.count, 0)
        let total = max(required.count, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(covered)/\(total) skills covered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                Spacer()
                Text(missing.isEmpty ? "Ready to build" : "Still missing \(missing.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(missing.isEmpty ? Ink.teal : Ink.gold)
            }
            ProgressView(value: Double(covered), total: Double(total))
                .tint(missing.isEmpty ? Ink.teal : Ink.gold)
        }
    }
}

struct EmptyNote: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(Ink.gold)
            Text(title)
                .font(Typeface.title())
                .foregroundStyle(Ink.paper)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
