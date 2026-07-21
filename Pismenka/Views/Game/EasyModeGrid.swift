//
//  LetterGrid.swift (file kept as EasyModeGrid.swift for project-file stability)
//  Pismenka
//
//  Letter grid used by both the calibration flow and the adaptive game.
//  Calibration stays 2x2; adaptive rounds can grow to 6 or 8 options.
//

import SwiftUI

// MARK: - Answer Animation State

enum AnswerAnimationState: Equatable {
    case none
    case correct(index: Int)
    case incorrect(index: Int)
    case revealing(index: Int)
}

// MARK: - Letter Grid

struct LetterGrid: View {
    let letters: [String]
    let targetLetter: String
    let answerAnimation: AnswerAnimationState
    let correctLetterIndex: Int?
    let color: Color
    let onLetterTap: (String, Int) -> Void

    private var gridSpacing: CGFloat {
        switch letters.count {
        case 0...4: return 20
        case 5...6: return 16
        default: return 12
        }
    }

    private var buttonDimension: CGFloat {
        switch letters.count {
        case 0...4: return 140
        case 5...6: return 116
        default: return 96
        }
    }

    private var fontSize: CGFloat {
        switch letters.count {
        case 0...4: return 72
        case 5...6: return 60
        default: return 50
        }
    }

    private var horizontalPadding: CGFloat {
        letters.count <= 4 ? 12 : 8
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: gridSpacing),
            GridItem(.flexible(), spacing: gridSpacing)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = gridMetrics(for: geometry.size)
            LazyVGrid(columns: metrics.columns, spacing: metrics.spacing) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    LetterButton(
                        letter: letter,
                        index: index,
                        color: color,
                        answerAnimation: answerAnimation,
                        isCorrectLetter: correctLetterIndex == index,
                        showCorrectFlash: correctLetterIndex == index && answerAnimation != .correct(index: index),
                        dimension: metrics.buttonDimension,
                        fontSize: metrics.fontSize,
                        onTap: {
                            onLetterTap(letter, index)
                        }
                    )
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func gridMetrics(for size: CGSize) -> GridMetrics {
        let rowCount = max(1, Int(ceil(Double(max(letters.count, 1)) / 2.0)))
        let spacing = gridSpacing
        let horizontalPadding = self.horizontalPadding
        let availableWidth = max(0, size.width - horizontalPadding * 2 - spacing)
        let availableHeight = max(0, size.height - CGFloat(rowCount - 1) * spacing)
        let widthBound = availableWidth / 2
        let heightBound = availableHeight / CGFloat(rowCount)
        let proposedDimension = min(widthBound, heightBound)
        let dimension = proposedDimension.isFinite && proposedDimension > 0
            ? max(64, proposedDimension)
            : buttonDimension
        let fontScale = fontSize / buttonDimension
        return GridMetrics(
            spacing: spacing,
            horizontalPadding: horizontalPadding,
            buttonDimension: dimension,
            fontSize: dimension * fontScale
        )
    }
}

private struct GridMetrics {
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    let buttonDimension: CGFloat
    let fontSize: CGFloat

    var columns: [GridItem] {
        [
            GridItem(.fixed(buttonDimension), spacing: spacing),
            GridItem(.fixed(buttonDimension), spacing: spacing)
        ]
    }
}

// MARK: - Letter Button

/// Brand-aligned letter tile. The resting state mirrors the website's
/// 2x2 hero card: a soft pastel "candy key-cap" with an ink letter and a
/// warm drop shadow. Correct / incorrect / revealing states override the
/// fill with leaf/berry and switch the letter to white so feedback stays
/// unmistakable.
///
/// The `color` parameter is kept on the public API for backwards compat
/// (calibration + game pass `profile.colorTheme`) but is intentionally
/// **not** used as a fill tint — the per-index pastel rotation is what
/// gives every round its candy-box look. The avatar's color survives as
/// an identity cue everywhere else (avatar circle, focus glow, confetti).
struct LetterButton: View {
    let letter: String
    let index: Int
    let color: Color
    let answerAnimation: AnswerAnimationState
    let isCorrectLetter: Bool
    let showCorrectFlash: Bool
    let dimension: CGFloat
    let fontSize: CGFloat
    let onTap: () -> Void

    private var isCorrectAnswer: Bool {
        if case .correct(let i) = answerAnimation, i == index {
            return true
        }
        return false
    }

    private var isIncorrectAnswer: Bool {
        if case .incorrect(let i) = answerAnimation, i == index {
            return true
        }
        return false
    }

    private var isRevealingAnswer: Bool {
        if case .revealing(let i) = answerAnimation, i == index {
            return true
        }
        return false
    }

    /// Resting pastel for this tile. Stable for the round (driven by the
    /// position in the grid) so a child's eye doesn't get whiplash mid-round.
    private var restingFill: Color { BrandPastel.color(at: index) }

    private var isFeedbackActive: Bool {
        isCorrectAnswer || isRevealingAnswer || isIncorrectAnswer
    }

    private var tileFill: Color {
        if isCorrectAnswer || isRevealingAnswer || (showCorrectFlash && isCorrectLetter) {
            return .leaf
        } else if isIncorrectAnswer {
            return .berry
        }
        return restingFill
    }

    private var letterColor: Color {
        isFeedbackActive ? .white : .ink
    }

    // Matches the website hero's `rounded-[1.5rem]` on its 2×2 grid (24pt /
    // ~155pt tile ≈ 0.155). Tighter than the previous 0.22 so tiles read as
    // squarer "keycaps" instead of cushions, exactly mirroring the marketing
    // screenshot.
    private var cornerRadius: CGFloat { dimension * 0.155 }
    private var overlayIconSize: CGFloat { dimension * 0.23 }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tileFill)
                    .overlay(
                        // Inner bottom gradient sells the "candy key-cap"
                        // depth. Skipped in feedback states because the
                        // strong leaf/berry fill already pops.
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isFeedbackActive ? 0.0 : 0.35),
                                        .clear,
                                        Color.ink.opacity(isFeedbackActive ? 0.0 : 0.07)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .allowsHitTesting(false)
                    )
                    .frame(width: dimension, height: dimension)
                    .letterTileShadow()

                Text(displayText)
                    .font(.system(size: adjustedFontSize, weight: .black, design: .rounded))
                    .foregroundColor(letterColor)

                if isCorrectAnswer || isRevealingAnswer {
                    Image(systemName: "checkmark")
                        .font(.system(size: overlayIconSize, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: dimension * 0.3, y: -dimension * 0.3)
                }
                if isIncorrectAnswer {
                    Image(systemName: "xmark")
                        .font(.system(size: overlayIconSize, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: dimension * 0.3, y: -dimension * 0.3)
                }
            }
        }
        .buttonStyle(LetterButtonStyle())
        .modifier(WiggleModifier(wiggling: isIncorrectAnswer))
        .scaleEffect(isCorrectAnswer || isRevealingAnswer ? 1.08 : 1.0)
        .animation(.spring(response: 0.3), value: isCorrectAnswer)
        .animation(.spring(response: 0.3), value: isIncorrectAnswer)
        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: isRevealingAnswer)
        .opacity(showCorrectFlash && isCorrectLetter ? 1.0 : (answerAnimation != .none && !isFeedbackActive ? 0.5 : 1.0))
        .accessibilityLabel("Choice \(displayText)")
        .accessibilityHint("Double tap to choose \(displayText)")
    }

    private var displayText: String {
        if letter.hasSuffix("|lower") {
            return String(letter.dropLast("|lower".count)).lowercased()
        }
        // Bare digit keys ("5", "26", "100") are number glyphs in the grid —
        // never run them through FocusTarget(storageKey:), which treats any
        // single character as a letter (so "5" would become .letter("5")).
        if letter.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return letter
        }
        if let target = FocusTarget(storageKey: letter) {
            return target.displayText
        }
        return letter
    }

    private var adjustedFontSize: CGFloat {
        displayText.count > 2 ? fontSize * 0.55 : (displayText.count == 2 ? fontSize * 0.78 : fontSize)
    }
}

// MARK: - Letter Button Style

struct LetterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Wiggle Modifier

struct WiggleModifier: ViewModifier {
    let wiggling: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(wiggling ? 3 : 0))
            .animation(
                wiggling ? Animation.easeInOut(duration: 0.08).repeatCount(6, autoreverses: true) : .default,
                value: wiggling
            )
    }
}

#Preview {
    LetterGrid(
        letters: ["A", "B", "C", "D"],
        targetLetter: "A",
        answerAnimation: .none,
        correctLetterIndex: nil,
        color: .sun,
        onLetterTap: { _, _ in }
    )
    .padding(.vertical, 40)
    .brandBackground()
}
