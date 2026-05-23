//
//  ConfettiView.swift
//  Pismenka
//
//  Confetti animation for correct answers and the Winner celebration.
//

import SwiftUI

struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [ConfettiParticle] = []

    let style: ConfettiStyle

    let colors: [Color] = [
        .red, .blue, .green, .yellow, .orange, .purple, .pink,
        Color(red: 0.10, green: 0.78, blue: 0.85),  // teal
        Color(red: 0.95, green: 0.45, blue: 0.65),  // hot pink
        Color(red: 0.60, green: 0.85, blue: 0.30)   // lime
    ]

    init(style: ConfettiStyle = .standard) {
        self.style = style
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func createParticles(in size: CGSize) {
        guard !reduceMotion else {
            particles = []
            return
        }
        particles = style.particleSpecs.flatMap { spec -> [ConfettiParticle] in
            (0..<spec.count).map { _ in
                let startY = style.startY(in: size)
                return ConfettiParticle(
                    x: CGFloat.random(in: 0...size.width),
                    y: startY,
                    color: colors.randomElement() ?? .yellow,
                    shape: style.randomShape(),
                    size: style.particleSize,
                    aspectRatio: style.randomAspectRatio(),
                    rotation: Double.random(in: 0...360),
                    targetY: style.targetY(from: startY, in: size),
                    horizontalOffset: style.horizontalOffset(in: size),
                    swayAmplitude: style.swayAmplitude,
                    swayPeriod: style.swayPeriod,
                    flipPeriod: style.flipPeriod,
                    delay: spec.delayRange.randomDelay(),
                    duration: style.duration,
                    animationCurve: style.animationCurve
                )
            }
        }
    }
}

// MARK: - Style

enum ConfettiStyle {
    case standard
    /// Big celebratory shower for the daily Winner moment. Pieces start
    /// above the screen, fall under "gravity" (easeIn), drift sideways
    /// like real paper, and arrive in two overlapping waves so the
    /// screen never goes empty during the celebration window.
    case celebration

    struct WaveSpec {
        let count: Int
        let delayRange: DelayRange
    }

    struct DelayRange {
        let lower: Double
        let upper: Double
        func randomDelay() -> Double {
            guard upper > lower else { return lower }
            return Double.random(in: lower...upper)
        }
    }

    enum ParticleShape {
        case rectangle
        case strip
        case circle
    }

    enum AnimationCurve {
        case easeIn
        case easeOut
    }

    var particleSpecs: [WaveSpec] {
        switch self {
        case .standard:
            return [WaveSpec(count: 40, delayRange: DelayRange(lower: 0, upper: 0.3))]
        case .celebration:
            return [
                WaveSpec(count: 130, delayRange: DelayRange(lower: 0.0, upper: 0.6)),
                WaveSpec(count: 110, delayRange: DelayRange(lower: 0.6, upper: 2.4))
            ]
        }
    }

    var particleSize: CGFloat {
        switch self {
        case .standard: return CGFloat.random(in: 8...16)
        case .celebration: return CGFloat.random(in: 10...22)
        }
    }

    var animationCurve: AnimationCurve {
        switch self {
        case .standard: return .easeOut
        case .celebration: return .easeIn
        }
    }

    var duration: Double {
        switch self {
        case .standard: return Double.random(in: 1.0...1.5)
        case .celebration: return Double.random(in: 2.4...3.6)
        }
    }

    var swayAmplitude: CGFloat {
        switch self {
        case .standard: return 0
        case .celebration: return CGFloat.random(in: 12...26)
        }
    }

    var swayPeriod: Double {
        switch self {
        case .standard: return 0
        case .celebration: return Double.random(in: 0.7...1.3)
        }
    }

    var flipPeriod: Double {
        switch self {
        case .standard: return 0
        case .celebration: return Double.random(in: 0.6...1.2)
        }
    }

    func randomShape() -> ParticleShape {
        switch self {
        case .standard:
            return .rectangle
        case .celebration:
            // 60% rectangles, 25% narrow strips, 15% circles for paper variety.
            let roll = Double.random(in: 0..<1)
            if roll < 0.60 { return .rectangle }
            if roll < 0.85 { return .strip }
            return .circle
        }
    }

    func randomAspectRatio() -> CGFloat {
        switch self {
        case .standard:
            return 0.6
        case .celebration:
            return CGFloat.random(in: 0.4...0.8)
        }
    }

    func startY(in size: CGSize) -> CGFloat {
        switch self {
        case .standard:
            return -20
        case .celebration:
            // Always start above the visible top edge so the shower
            // appears to fall *into* the screen rather than materialize.
            return CGFloat.random(in: -220 ... -20)
        }
    }

    func targetY(from startY: CGFloat, in size: CGSize) -> CGFloat {
        switch self {
        case .standard:
            return size.height + 50
        case .celebration:
            return size.height + CGFloat.random(in: 80...220)
        }
    }

    func horizontalOffset(in size: CGSize) -> CGFloat {
        switch self {
        case .standard:
            return CGFloat.random(in: -100...100)
        case .celebration:
            // Wider drift than .standard so confetti spreads across the
            // screen as it falls instead of dropping in tight columns.
            return CGFloat.random(in: -(size.width * 0.45)...(size.width * 0.45))
        }
    }
}

// MARK: - Particle

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let shape: ConfettiStyle.ParticleShape
    let size: CGFloat
    let aspectRatio: CGFloat
    let rotation: Double
    let targetY: CGFloat
    let horizontalOffset: CGFloat
    let swayAmplitude: CGFloat
    let swayPeriod: Double
    let flipPeriod: Double
    let delay: Double
    let duration: Double
    let animationCurve: ConfettiStyle.AnimationCurve
}

struct ConfettiPiece: View {
    let particle: ConfettiParticle

    @State private var animatedY: CGFloat = 0
    @State private var animatedRotation: Double = 0
    @State private var animatedX: CGFloat = 0
    @State private var sway: CGFloat = 0
    @State private var flip: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        shapeView
            .rotationEffect(.degrees(animatedRotation))
            .rotation3DEffect(.degrees(flip), axis: (x: 1, y: 0, z: 0))
            .position(x: particle.x + animatedX + sway, y: animatedY)
            .opacity(opacity)
            .onAppear { startAnimation() }
    }

    @ViewBuilder
    private var shapeView: some View {
        switch particle.shape {
        case .rectangle:
            Rectangle()
                .fill(particle.color)
                .frame(width: particle.size, height: particle.size * particle.aspectRatio)
        case .strip:
            RoundedRectangle(cornerRadius: 1)
                .fill(particle.color)
                .frame(width: particle.size * 1.4, height: max(particle.size * 0.18, 2))
        case .circle:
            Circle()
                .fill(particle.color)
                .frame(width: particle.size * 0.7, height: particle.size * 0.7)
        }
    }

    private func startAnimation() {
        animatedY = particle.y

        let baseFall: Animation
        switch particle.animationCurve {
        case ConfettiStyle.AnimationCurve.easeIn:
            baseFall = Animation.easeIn(duration: particle.duration)
        case ConfettiStyle.AnimationCurve.easeOut:
            baseFall = Animation.easeOut(duration: particle.duration)
        }
        let fallAnimation = baseFall.delay(particle.delay)

        withAnimation(fallAnimation) {
            animatedY = particle.targetY
            animatedRotation = particle.rotation + 720
            animatedX = particle.horizontalOffset
        }

        if particle.swayAmplitude > 0 && particle.swayPeriod > 0 {
            // Two-stage sway: a tiny easeOut into the first peak so the
            // repeatForever oscillation starts mid-stroke instead of a
            // noticeable jump from rest. The autoreverses curve does the
            // back-and-forth flutter for the rest of the fall.
            withAnimation(
                .easeInOut(duration: particle.swayPeriod / 2)
                .delay(particle.delay)
            ) {
                sway = particle.swayAmplitude
            }
            withAnimation(
                .easeInOut(duration: particle.swayPeriod)
                .repeatForever(autoreverses: true)
                .delay(particle.delay + particle.swayPeriod / 2)
            ) {
                sway = -particle.swayAmplitude
            }
        }

        if particle.flipPeriod > 0 {
            withAnimation(
                .linear(duration: particle.duration)
                .delay(particle.delay)
            ) {
                flip = 720
            }
        }

        withAnimation(
            .easeIn(duration: 0.3)
            .delay(particle.delay + particle.duration - 0.3)
        ) {
            opacity = 0
        }
    }
}

#Preview("Standard") {
    ZStack {
        Color.white
        ConfettiView()
    }
}

#Preview("Celebration") {
    ZStack {
        Color(red: 0.95, green: 0.92, blue: 0.85)
        ConfettiView(style: .celebration)
    }
}
