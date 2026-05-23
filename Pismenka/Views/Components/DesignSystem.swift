//
//  DesignSystem.swift
//  Pismenka
//
//  Shared brand language for the iOS app. Mirrors the website
//  (`website/src/styles/global.css` + the hero card in
//  `website/src/pages/index.astro`) so the App Store screenshots, the
//  marketing site, and the in-app experience all read as the same product.
//
//  Conventions
//  -----------
//  * Brand colors live as static `Color` extensions (`Color.ink`,
//    `Color.cream`, etc.). Pastel tints used for tiles are suffixed `Tint`
//    to avoid collisions with system colors (`Color.mint`, `Color.pink`).
//  * Typography helpers (`.titleXL()`, `.eyebrow()`, …) standardize the
//    weight/tracking pairings the website uses so we don't drift toward
//    "default SwiftUI bold" again.
//  * View modifiers (`.softCard()`, `.glassCard()`, `.letterTileShadow()`,
//    `.brandBackground()`) replicate the website's `soft-card`, `glass`,
//    `letter-shadow`, and warm radial backdrop.
//  * Reusable views (`HeartsPill`, `GradientProgressBar`, `SectionEyebrow`,
//    `BrandIconButton`) are the building blocks the redesigned screens are
//    composed from.
//

import SwiftUI

// MARK: - Brand colors

extension Color {
    // Core brand
    static let ink = Color(red: 23.0 / 255.0, green: 32.0 / 255.0, blue: 51.0 / 255.0)
    static let cream = Color(red: 255.0 / 255.0, green: 250.0 / 255.0, blue: 240.0 / 255.0)
    static let creamDeep = Color(red: 247.0 / 255.0, green: 239.0 / 255.0, blue: 226.0 / 255.0)
    static let sun = Color(red: 255.0 / 255.0, green: 209.0 / 255.0, blue: 102.0 / 255.0)
    static let leaf = Color(red: 72.0 / 255.0, green: 199.0 / 255.0, blue: 142.0 / 255.0)
    static let berry = Color(red: 255.0 / 255.0, green: 107.0 / 255.0, blue: 138.0 / 255.0)
    static let sky = Color(red: 91.0 / 255.0, green: 124.0 / 255.0, blue: 250.0 / 255.0)

    // Soft pastel tints (Tailwind *-100 family). Used for tile fills,
    // chip backgrounds, soft accents. Suffixed `Tint` so they don't shadow
    // built-in SwiftUI colors.
    static let mintTint = Color(red: 209.0 / 255.0, green: 250.0 / 255.0, blue: 229.0 / 255.0)
    static let amberTint = Color(red: 254.0 / 255.0, green: 243.0 / 255.0, blue: 199.0 / 255.0)
    /// Tailwind `amber-50` (#fffbeb). Used as the **inner card** gradient bottom
    /// stop on the website hero (`bg-gradient-to-b from-white to-amber-50`).
    static let amberMist = Color(red: 255.0 / 255.0, green: 251.0 / 255.0, blue: 235.0 / 255.0)
    static let indigoTint = Color(red: 224.0 / 255.0, green: 231.0 / 255.0, blue: 255.0 / 255.0)
    static let pinkTint = Color(red: 252.0 / 255.0, green: 231.0 / 255.0, blue: 243.0 / 255.0)
    static let skyTint = Color(red: 219.0 / 255.0, green: 234.0 / 255.0, blue: 254.0 / 255.0)
    static let lavenderTint = Color(red: 237.0 / 255.0, green: 233.0 / 255.0, blue: 254.0 / 255.0)
    static let peachTint = Color(red: 254.0 / 255.0, green: 215.0 / 255.0, blue: 170.0 / 255.0)
    static let roseTint = Color(red: 255.0 / 255.0, green: 228.0 / 255.0, blue: 230.0 / 255.0)
    static let mossTint = Color(red: 220.0 / 255.0, green: 240.0 / 255.0, blue: 210.0 / 255.0)
    static let sandTint = Color(red: 246.0 / 255.0, green: 235.0 / 255.0, blue: 215.0 / 255.0)

    // Supporting text greys (Tailwind slate ramp)
    static let slate400 = Color(red: 148.0 / 255.0, green: 163.0 / 255.0, blue: 184.0 / 255.0)
    static let slate500 = Color(red: 100.0 / 255.0, green: 116.0 / 255.0, blue: 139.0 / 255.0)
    static let slate600 = Color(red: 71.0 / 255.0, green: 85.0 / 255.0, blue: 105.0 / 255.0)

    // Deeper berry for hearts pill ink — matches `rose-500` on the website.
    static let berryInk = Color(red: 244.0 / 255.0, green: 63.0 / 255.0, blue: 94.0 / 255.0)
}

/// Brand-aligned rotation used by letter tiles, sticker stamps, and any
/// "pick a friendly pastel" UI. Deterministic from an index so the same
/// round always looks the same.
enum BrandPastel {
    static let rotation: [Color] = [
        .mintTint,
        .amberTint,
        .indigoTint,
        .pinkTint,
        .skyTint,
        .lavenderTint,
        .peachTint,
        .mossTint
    ]

    static func color(at index: Int) -> Color {
        let count = rotation.count
        let normalized = ((index % count) + count) % count
        return rotation[normalized]
    }
}

// MARK: - Typography

extension Font {
    /// Tiny uppercase eyebrow label ("TODAY", "FOR PARENTS"). Wide-tracked,
    /// usually paired with `Color.slate400`.
    static func brandEyebrow(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Hero title (`Daily letters`, `Písmenka`). Heavy weight + rounded.
    /// Pair with `.tracking(-1.2)` on the Text for the website's tight feel.
    static func brandTitleXL(_ size: CGFloat = 38) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func brandTitleL(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func brandTitleM(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func brandBody(_ size: CGFloat = 16, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Eyebrow text styling shortcut: uppercase, wide tracking, slate ink.
    /// Apply to a `Text` whose string is already uppercased.
    func brandEyebrowStyle() -> some View {
        self
            .font(.brandEyebrow())
            .tracking(2.6)
            .foregroundColor(.slate400)
    }
}

// MARK: - Surface modifiers

extension View {
    /// Mirrors `.soft-card` on the website: warm parchment fill, hairline
    /// warm border, soft warm drop. The default radius is 28; pass a
    /// larger value for hero cards.
    func softCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.06), radius: 18, x: 0, y: 14)
    }

    /// Mirrors `.glass` on the website: translucent white with a subtle
    /// border and a generous warm drop. Slight rim-light overlay sells
    /// the "frosted candy" feel.
    func glassCard(cornerRadius: CGFloat = 32) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.08), radius: 24, x: 0, y: 18)
    }

    /// Letter/key-cap drop: dual warm shadows + an inner bottom gradient
    /// that sells the "candy keycap" depth without requiring real CoreGraphics
    /// inset shadows. Place this on whatever owns the rounded fill — the
    /// modifier itself does not change the fill or the shape.
    func letterTileShadow() -> some View {
        self
            .shadow(color: Color.ink.opacity(0.08), radius: 5, x: 0, y: 3)
            .shadow(color: Color.ink.opacity(0.08), radius: 18, x: 0, y: 14)
    }

    /// Warm cream backdrop with two corner radial accents (sun top-left,
    /// sky top-right). Matches the website body background so the app feels
    /// like the same product when a parent flips between the App Store
    /// listing and the running app.
    func brandBackground() -> some View {
        self.background(BrandBackground().ignoresSafeArea())
    }
}

/// Standalone canvas color — use directly as a full-screen background when
/// you want the warm radial accents.
struct BrandBackground: View {
    /// Optional tint that bleeds through softly so we can keep an avatar's
    /// identity visible without painting the entire screen in that color.
    var accent: Color = .clear

    var body: some View {
        ZStack {
            Color.cream
            RadialGradient(
                gradient: Gradient(colors: [Color.sun.opacity(0.32), .clear]),
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                gradient: Gradient(colors: [Color.sky.opacity(0.18), .clear]),
                center: .topTrailing,
                startRadius: 20,
                endRadius: 540
            )
            RadialGradient(
                gradient: Gradient(colors: [Color.berry.opacity(0.12), .clear]),
                center: .bottom,
                startRadius: 20,
                endRadius: 460
            )
            if accent != .clear {
                RadialGradient(
                    gradient: Gradient(colors: [accent.opacity(0.20), .clear]),
                    center: .center,
                    startRadius: 40,
                    endRadius: 520
                )
                .blendMode(.multiply)
            }
        }
    }
}

// MARK: - Reusable components

/// Soft eyebrow + title pair used at the top of every brand section. Mirrors
/// the website's `TODAY / Daily letters` block.
struct SectionEyebrow: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .brandEyebrowStyle()
            Text(title)
                .font(.brandTitleL())
                .tracking(-0.8)
                .foregroundColor(.ink)
        }
    }
}

/// Hearts indicator pill ("5 ♥"). Glyph order intentionally matches the
/// website hero (number first, heart second) so a screenshot of the game
/// card reads as the same artifact as the marketing image.
struct HeartsPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.brandBody(15, weight: .black))
                .monospacedDigit()
            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .heavy))
        }
        .foregroundColor(.berryInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.roseTint)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.berryInk.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(count) hearts remaining")
    }
}

/// Slim gradient progress bar. The website uses a leaf→sky fill on an
/// amber-tinted track; this preserves both the look and the brand's
/// "warm rest, cool action" color story.
struct GradientProgressBar: View {
    /// Clamped 0…1.
    let progress: Double
    var height: CGFloat = 12
    var trackColor: Color = .amberTint
    var fillColors: [Color] = [.leaf, .sky]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: fillColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, progress))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    }
}

/// Round icon button used for primary CTAs (play / replay / done / home).
/// Defaults to the brand leaf for the "go" action; pass `style: .neutral`
/// for the home/exit action so destructive/back affordances stay calm.
struct BrandIconButton: View {
    enum Style {
        case leaf
        case ink
        case neutral
        case berry
    }

    let systemImage: String
    let action: () -> Void
    var size: CGFloat = 82
    var style: Style = .leaf
    var accessibilityLabel: String?

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                Circle()
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundColor(iconColor)
            }
            .frame(width: size, height: size)
            .shadow(color: shadowColor.opacity(0.28), radius: 14, x: 0, y: 8)
            .shadow(color: Color.ink.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }

    private var fill: Color {
        switch style {
        case .leaf: return .leaf
        case .ink: return .ink
        case .neutral: return Color.white.opacity(0.9)
        case .berry: return .berry
        }
    }

    private var iconColor: Color {
        switch style {
        case .leaf, .ink, .berry: return .white
        case .neutral: return .slate500
        }
    }

    private var shadowColor: Color {
        switch style {
        case .leaf: return .leaf
        case .ink: return .ink
        case .neutral: return .ink
        case .berry: return .berry
        }
    }

    private var strokeOpacity: Double {
        switch style {
        case .leaf, .ink, .berry: return 0.18
        case .neutral: return 0.4
        }
    }
}

/// Two-layer composition that mirrors the website's hero card:
/// outer **glass** wrap (`rgba(255,255,255,0.7)` + warm drop) + inner
/// **white → amber-mist** gradient surface. Use this anywhere we want the
/// app to read as a 1:1 of the marketing screenshot — currently the in-game
/// area, the session-end summary "today's card" panel, and any future hero
/// surface (App Store hero, splash, share card, etc.).
struct BrandHeroCard<Content: View>: View {
    var outerPadding: CGFloat = 12
    var innerPadding: CGFloat = 20
    var outerCornerRadius: CGFloat = 36
    var innerCornerRadius: CGFloat = 28
    let content: Content

    init(
        outerPadding: CGFloat = 12,
        innerPadding: CGFloat = 20,
        outerCornerRadius: CGFloat = 36,
        innerCornerRadius: CGFloat = 28,
        @ViewBuilder _ content: () -> Content
    ) {
        self.outerPadding = outerPadding
        self.innerPadding = innerPadding
        self.outerCornerRadius = outerCornerRadius
        self.innerCornerRadius = innerCornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(innerPadding)
            .background(
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white, Color.amberMist],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .padding(outerPadding)
            .background(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            // Warm chocolate-tinted drop, matching the website's
            // `0 24px 90px rgba(71,52,24,0.13)`.
            .shadow(
                color: Color(red: 71.0 / 255.0, green: 52.0 / 255.0, blue: 24.0 / 255.0).opacity(0.13),
                radius: 28,
                x: 0,
                y: 18
            )
    }
}

/// Small pill chip with brand-leaning styling. Used for status tags
/// ("FREE", "NEW", "DAY 5") on hero surfaces.
struct BrandChip: View {
    let text: String
    var background: Color = .sun
    var foreground: Color = .ink

    var body: some View {
        Text(text.uppercased())
            .font(.brandEyebrow(11))
            .tracking(2.0)
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }
}

#Preview("Design system") {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            SectionEyebrow(eyebrow: "Today", title: "Daily letters")

            HStack(spacing: 14) {
                HeartsPill(count: 5)
                BrandChip(text: "Day 3")
                BrandChip(text: "Free", background: .leaf, foreground: .white)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Soft card surface")
                    .font(.brandTitleM())
                    .foregroundColor(.ink)
                Text("Mirrors the website's `.soft-card` panel. Use for stat blocks, info panels, and any container that should feel warm and matte.")
                    .font(.brandBody())
                    .foregroundColor(.slate500)
            }
            .padding(20)
            .softCard()

            VStack(spacing: 12) {
                HStack {
                    Text("17 / 25")
                        .font(.brandBody(14, weight: .black))
                        .foregroundColor(.slate500)
                        .monospacedDigit()
                    Spacer()
                    Text("Winner soon")
                        .font(.brandBody(14, weight: .black))
                        .foregroundColor(.slate500)
                }
                GradientProgressBar(progress: 0.68)
            }
            .padding(20)
            .softCard()

            HStack(spacing: 18) {
                BrandIconButton(systemImage: "house.fill", action: {}, size: 64, style: .neutral)
                BrandIconButton(systemImage: "play.fill", action: {}, size: 82, style: .leaf)
                BrandIconButton(systemImage: "checkmark", action: {}, size: 64, style: .ink)
            }
        }
        .padding(24)
    }
    .brandBackground()
}
