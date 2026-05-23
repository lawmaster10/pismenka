//
//  SessionEndView.swift (file kept as SummaryView.swift for project-file stability)
//  Pismenka
//
//  Always-celebratory session end screen. Shows the Today's focus card stamps, the
//  day-streak flame, letters mastered + progression bar, an optional
//  focus-graduation badge, and a peek at tomorrow. The headline + confetti
//  intensity differ per `SessionEndReason` but the structure and tone are
//  identical — the child should feel they accomplished something regardless
//  of how the session actually ended.
//

import SwiftUI

struct SessionEndView: View {
    let profile: Profile
    let summary: SessionSummary
    let onPlayAgain: () -> Void
    let onHome: () -> Void

    @State private var showContent = false
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            BrandBackground(accent: profile.colorTheme).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headline
                    if let graduated = summary.focusGraduatedThisSession {
                        masteredBadge(letter: graduated)
                    }
                    stampsCard
                    statsCard
                    tomorrowPreview
                    Spacer(minLength: 8)
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            HapticService.shared.success()
            withAnimation(.easeOut(duration: 0.3)) { showContent = true }
            withAnimation { showConfetti = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { showConfetti = false }
            }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(profile.colorTheme)
                    .frame(width: 120, height: 120)
                    .shadow(color: profile.colorTheme.opacity(0.35), radius: 16, x: 0, y: 10)
                Text(profile.avatarId.emoji)
                    .font(.system(size: 72))
            }
            VStack(spacing: 4) {
                Text("Today".uppercased())
                    .brandEyebrowStyle()
                Text(headlineText)
                    .font(.brandTitleXL(34))
                    .tracking(-1.2)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .opacity(showContent ? 1.0 : 0.0)
    }

    private var headlineText: String {
        switch summary.endReason {
        case .goalComplete: return "You did it!"
        case .homeTapped: return "Great practicing!"
        case .outOfHearts: return "Nice try today!"
        case .tiredSignal: return "Great practicing!"
        case .practiceComplete: return "Practice complete!"
        }
    }

    private func masteredBadge(letter: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.ink)
            Text("You mastered \(letter)!")
                .font(.brandTitleM(20))
                .tracking(-0.4)
                .foregroundColor(.ink)
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.ink)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.sun.opacity(0.55), Color.peachTint.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sun.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.sun.opacity(0.25), radius: 14, x: 0, y: 8)
    }

    private var stampsCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today".uppercased())
                        .brandEyebrowStyle()
                    Text("Sticker card")
                        .font(.brandTitleM(18))
                        .tracking(-0.4)
                        .foregroundColor(.ink)
                }
                Spacer()
                Text("\(summary.stampsEarned.count) / \(summary.applicableStamps.count)")
                    .font(.brandBody(14, weight: .black))
                    .foregroundColor(.slate500)
                    .monospacedDigit()
            }

            HStack(spacing: 16) {
                ForEach(summary.applicableStamps) { stamp in
                    VStack(spacing: 6) {
                        StampBadge(
                            stamp: stamp,
                            isFilled: summary.stampsEarned.contains(stamp),
                            isPopping: false,
                            color: profile.colorTheme
                        )
                        Text(stamp.displayName)
                            .font(.brandBody(11, weight: .bold))
                            .foregroundColor(.slate500)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            let unearned = summary.applicableStamps.filter { !summary.stampsEarned.contains($0) }
            if !unearned.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unearned) { stamp in
                        Text(stampHint(for: stamp))
                            .font(.brandBody(12, weight: .semibold))
                            .foregroundColor(.slate500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .softCard()
    }

    private var statsCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.sun.opacity(0.35))
                        .frame(width: 44, height: 44)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.berry)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day streak".uppercased())
                        .brandEyebrowStyle()
                    Text("Day \(summary.dayStreakCount) in a row")
                        .font(.brandTitleM(20))
                        .tracking(-0.4)
                        .foregroundColor(.ink)
                }
                Spacer()
                if summary.bestDailyStreak > summary.dayStreakCount {
                    Text("Best \(summary.bestDailyStreak)")
                        .font(.brandBody(12, weight: .black))
                        .foregroundColor(.slate500)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.amberTint))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Letters mastered".uppercased())
                        .brandEyebrowStyle()
                    Spacer()
                    Text("\(summary.letterMasteredCount) / \(summary.totalLetters)")
                        .font(.brandBody(14, weight: .black))
                        .foregroundColor(.slate500)
                        .monospacedDigit()
                }
                GradientProgressBar(
                    progress: Double(summary.letterMasteredCount) /
                        Double(max(summary.nextLevelThreshold, summary.totalLetters))
                )
                Text("\(summary.newLevel.badgeEmoji)  \(summary.newLevel.displayName)")
                    .font(.brandBody(13, weight: .bold))
                    .foregroundColor(.slate500)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .softCard()
    }

    private func stampHint(for stamp: DailyStamp) -> String {
        switch stamp {
        case .warmupStar:
            return "Sticker idea: warm up with a few correct answers."
        case .braveStart:
            return "Sticker idea: start with a brave correct tap."
        case .reviewStar:
            return "Sticker idea: collect a few review wins."
        case .helloFocus:
            if let focus = summary.currentFocusLetter ?? summary.nextFocusPreview {
                return "Sticker idea: say hello to \(focus)."
            }
            return "Sticker idea: say hello to today's letter."
        case .practicePro:
            if let focus = summary.currentFocusLetter ?? summary.focusGraduatedThisSession {
                return "Sticker idea: find \(focus) a few times."
            }
            return "Sticker idea: keep collecting correct answers."
        case .streakStar:
            return "Sticker idea: build a little correct-answer streak."
        case .extraPractice:
            return "Sticker idea: finish an extra practice round."
        }
    }

    private var tomorrowPreview: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sun.opacity(0.45))
                    .frame(width: 38, height: 38)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tomorrow".uppercased())
                    .brandEyebrowStyle()
                Text(tomorrowText)
                    .font(.brandBody(15, weight: .bold))
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22)
    }

    private var tomorrowText: String {
        if summary.endReason == .tiredSignal {
            return "Tomorrow we'll start easy again."
        }
        if summary.focusGraduatedThisSession != nil {
            if let next = summary.nextFocusPreview {
                return "Tomorrow we'll see \(next)!"
            }
            return "Tomorrow let's review what you know!"
        }
        if let focus = summary.currentFocusLetter {
            return "Tomorrow we'll keep practicing \(focus)."
        }
        return "Tomorrow let's review!"
    }

    private var actionButtons: some View {
        HStack(spacing: 28) {
            BrandIconButton(
                systemImage: "house.fill",
                action: {
                    HapticService.shared.tap()
                    onHome()
                },
                size: 72,
                style: .neutral,
                accessibilityLabel: "Home"
            )
            BrandIconButton(
                systemImage: "arrow.counterclockwise",
                action: {
                    HapticService.shared.tap()
                    onPlayAgain()
                },
                size: 86,
                style: .leaf,
                accessibilityLabel: "Play again"
            )
        }
    }
}

#Preview {
    SessionEndView(
        profile: Profile(avatarId: .lion, language: .english),
        summary: SessionSummary(
            profileId: UUID(),
            endReason: .goalComplete,
            stampsEarned: [.warmupStar, .helloFocus, .practicePro, .streakStar],
            applicableStamps: [.warmupStar, .helloFocus, .practicePro, .streakStar],
            heartsRemaining: 4,
            bestSessionStreak: 8,
            roundsAnswered: 25,
            roundsCorrect: 22,
            focusGraduatedThisSession: "O",
            dayStreakCount: 5,
            bestDailyStreak: 8,
            letterMasteredCount: 12,
            totalLetters: 26,
            nextLevelThreshold: 15,
            currentFocusLetter: nil,
            nextFocusPreview: "P",
            didLevelUp: false,
            newLevel: .beginner,
            unintroducedExposures: 0
        ),
        onPlayAgain: {},
        onHome: {}
    )
}
