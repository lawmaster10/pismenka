//
//  GameView.swift
//  Pismenka
//
//  Adaptive game screen. Level-scaled answer options, hearts, Today's
//  focus card stamps, focus-unit intro overlay, mid-session focus-graduation
//  badge, and level-up overlay. Hands the session back to PismenkaApp via
//  `onExit(SessionSummary)`.
//

import SwiftUI

struct GameView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var audioService: AudioService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var checkpointStore: SessionCheckpointStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let profile: Profile
    let onExit: (SessionSummary) -> Void
    let onHome: () -> Void
    let onWeeklyTestCompletedByParent: () -> Void

    @StateObject private var gameState: AdaptiveGameState
    private let plan: SessionPlan

    @State private var answerAnimation: AnswerAnimationState = .none
    @State private var correctLetterIndex: Int?
    @State private var showConfetti = false
    @State private var confettiStyle: ConfettiStyle = .standard
    @State private var confettiBurstID = UUID()
    @State private var showWinnerWow = false
    @State private var wowOverlayScale: CGFloat = 1.0
    @State private var showLevelUp: AlphabetLevel?
    @State private var showFocusIntro: String?
    @State private var showDayStreakBanner: Int?
    @State private var showFocusGraduated: String?
    @State private var showStampPop: DailyStamp?
    @State private var screenShake = false
    @State private var delayTask: Task<Void, Never>?
    @State private var sessionEndTask: Task<Void, Never>?
    @State private var winnerCelebrationTask: Task<Void, Never>?
    @State private var isEndingSession = false
    @State private var suppressNextReplayTap = false
    @State private var showWeeklyTestParentGate = false

    init(
        profile: Profile,
        plan: SessionPlan,
        profileManager: ProfileManager,
        restoredSnapshot: GameEngineSnapshot? = nil,
        onExit: @escaping (SessionSummary) -> Void,
        onHome: @escaping () -> Void,
        onWeeklyTestCompletedByParent: @escaping () -> Void
    ) {
        self.profile = profile
        self.onExit = onExit
        self.onHome = onHome
        self.onWeeklyTestCompletedByParent = onWeeklyTestCompletedByParent
        self.plan = plan
        _gameState = StateObject(wrappedValue: AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: profileManager,
            restoredSnapshot: restoredSnapshot
        ))
    }

    var body: some View {
        ZStack {
            BrandBackground(accent: profile.colorTheme).ignoresSafeArea()

            VStack(spacing: 10) {
                cardHeader
                if !gameState.applicableStamps.isEmpty {
                    stampStripThin
                }
                LetterGrid(
                    letters: gameState.displayedLetters,
                    targetLetter: gameState.targetLetter,
                    answerAnimation: answerAnimation,
                    correctLetterIndex: correctLetterIndex,
                    color: profile.colorTheme,
                    onLetterTap: handleLetterTap
                )
                .modifier(ShakeModifier(shake: screenShake))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                bottomControlRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showConfetti {
                ConfettiView(style: confettiStyle)
                    .id(confettiBurstID)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if showWinnerWow {
                WinnerWowOverlay(color: profile.colorTheme, scale: wowOverlayScale)
                    .transition(.opacity)
            }

            if let intro = showFocusIntro {
                NewLetterOverlay(letter: intro, color: profile.colorTheme, avatar: profile.avatarId.emoji) {
                    showFocusIntro = nil
                    playPrompt(after: 0.3)
                }
                .transition(.opacity)
            }

            if let banner = showDayStreakBanner {
                DayStreakBanner(days: banner)
                    .padding(.top, 80)
            }

            if let graduated = showFocusGraduated {
                FocusGraduatedOverlay(letter: graduated, color: profile.colorTheme)
                    .transition(.scale.combined(with: .opacity))
            }

            if let level = showLevelUp {
                LevelUpCelebrationView(level: level) {
                    showLevelUp = nil
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showFocusIntro)
        .animation(.easeInOut(duration: 0.3), value: showLevelUp)
        .animation(.spring(response: 0.4), value: showFocusGraduated)
        .animation(.easeInOut(duration: 0.3), value: showDayStreakBanner)
        .animation(.easeInOut(duration: 0.35), value: showWinnerWow)
        .onAppear { onAppearSetup() }
        .onDisappear {
            persistGameCheckpoint()
            delayTask?.cancel()
            winnerCelebrationTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistGameCheckpoint()
            }
        }
        .sheet(isPresented: $showWeeklyTestParentGate) {
            ParentGateView(
                method: settings.parentGateMethod,
                onSuccess: {
                    showWeeklyTestParentGate = false
                    completeWeeklyTestByParent()
                },
                onCancel: {
                    showWeeklyTestParentGate = false
                }
            )
        }
    }

    private var reduceMotion: Bool { settings.reduceMotionEnabled || systemReduceMotion }
    private var canShowConfetti: Bool { settings.confettiEnabled && !reduceMotion }

    // MARK: - Layout helpers

    /// Card header: `TODAY / Daily letters` on the left, compact controls on
    /// the right so navigation doesn't claim a whole row.
    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardEyebrow.uppercased())
                    .brandEyebrowStyle()
                Text(cardTitle)
                    .font(.brandTitleL(26))
                    .tracking(-0.6)
                    .foregroundColor(.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                homeButton(size: 40)
                HeartsPill(count: gameState.heartsRemaining)
            }
        }
    }

    private func homeButton(size: CGFloat) -> some View {
        Button(action: handleHomeTap) {
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.41, weight: .black))
                .foregroundColor(.slate500)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .overlay(Circle().stroke(Color.creamDeep.opacity(0.9), lineWidth: 1))
                )
                .shadow(color: Color.ink.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("Home")
    }

    private var cardEyebrow: String {
        if plan.mode.practiceLetter != nil { return "Practice" }
        if plan.dailyPracticeKind == .reviewTest { return "Review" }
        return "Today"
    }

    private var cardTitle: String {
        if let letter = plan.mode.practiceLetter {
            return "Practicing \(letter)"
        }
        if plan.dailyPracticeKind == .reviewTest {
            return "Progress check"
        }
        return "Daily letters"
    }

    /// Thin sticker strip sitting under the card header. Iterates only the
    /// session's applicable stamps (not `.allCases`) so the strip never shows
    /// an unreachable slot.
    private var stampStripThin: some View {
        HStack(spacing: 6) {
            ForEach(gameState.applicableStamps) { stamp in
                StampBadge(
                    stamp: stamp,
                    isFilled: gameState.stampsEarned.contains(stamp),
                    isPopping: showStampPop == stamp,
                    color: profile.colorTheme
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Compact bottom strip keeps replay beside progress instead of dedicating
    /// a full footer row to one oversized button.
    private var bottomControlRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if plan.mode == .adaptiveDaily {
                Group {
                    if gameState.hasCompletedDailyGoal {
                        winnerRewardBar
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        dailyGoalProgressStrip
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.hasCompletedDailyGoal)
                .layoutPriority(1)
            } else {
                Spacer(minLength: 0)
                if gameState.hasCompletedDailyGoal {
                    winnerButton
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.hasCompletedDailyGoal)
                }
            }
            compactReplayButton
        }
    }

    private var winnerRewardBar: some View {
        Button(action: handleDoneTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("🏆 WINNER 🏆")
                        .font(.brandTitleL(26))
                        .tracking(-0.8)
                    Text("Tap for your prize")
                        .font(.brandBody(13, weight: .black))
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .black))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.sun, .berry, .leaf],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 2)
            )
            .shadow(color: Color.sun.opacity(0.45), radius: 16, x: 0, y: 8)
            .shadow(color: Color.berry.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Winner. Tap for your prize.")
    }

    private var winnerButton: some View {
        Button(action: handleDoneTap) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                Text("Winner")
                    .tracking(-0.3)
            }
            .font(.brandTitleM(16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [.leaf, .sky],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
            .shadow(color: Color.leaf.opacity(0.35), radius: 10, x: 0, y: 5)
        }
    }

    private var compactReplayButton: some View {
        BrandIconButton(
            systemImage: "play.fill",
            action: replayPrompt,
            size: 58,
            style: .leaf,
            accessibilityLabel: "Replay sound"
        )
        .accessibilityHint(replayButtonAccessibilityHint)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 2.0)
                .onEnded { _ in
                    handleReplayLongPress()
                }
        )
    }

    private var replayButtonAccessibilityHint: String {
        if plan.dailyPracticeKind == .reviewTest {
            return "Tap to replay. Hold for parent confirmation."
        }
        return "Plays the letter sound again"
    }

    /// Mirrors the website hero's progress card composition exactly:
    /// thin track + leaf→sky gradient fill, then `17 / 25` on the left and
    /// `Winner soon` on the right in slate-500 black-weight type.
    private var dailyGoalProgressStrip: some View {
        VStack(spacing: 8) {
            GradientProgressBar(progress: gameState.dailyGoalProgress)
                .accessibilityLabel("Daily progress")
                .accessibilityValue(gameState.dailyGoalAccessibilityText)
            HStack(alignment: .firstTextBaseline) {
                Text(gameState.dailyGoalDisplayText)
                    .font(.brandBody(14, weight: .black))
                    .foregroundColor(.slate500)
                    .monospacedDigit()
                Spacer()
                Text(dailyGoalRightLabel)
                    .font(.brandBody(14, weight: .black))
                    .foregroundColor(.slate500)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
    }

    /// Right-side label under the progress bar. Mirrors the website hero
    /// which says "Winner soon" — switches to "Goal reached" once the daily
    /// goal lights up so the bar feels alive instead of static.
    private var dailyGoalRightLabel: String {
        if gameState.hasCompletedDailyGoal {
            return "Goal reached"
        }
        return "Winner soon"
    }

    // MARK: - Lifecycle

    private func onAppearSetup() {
        HapticService.shared.prepareAll()
        persistGameCheckpoint()

        if let endReason = gameState.sessionEnded {
            scheduleSessionEnd(reason: endReason, immediate: true)
            return
        }
        if plan.introducedNewFocusLetter,
                  let focus = plan.introducedFocusTarget?.displayText
                    ?? plan.dailySpotlightLetter
                    ?? plan.focusTarget?.displayText
                    ?? plan.focusLetter {
            showFocusIntro = focus
        } else {
            playPrompt(after: 0.5)
        }
        if plan.dayStreakIncreased, plan.dayStreakCount >= 2 {
            showDayStreakBanner = plan.dayStreakCount
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    withAnimation { showDayStreakBanner = nil }
                }
            }
        }
    }

    // MARK: - Letter tap

    private func handleLetterTap(_ letter: String, index: Int) {
        guard answerAnimation == .none else { return }
        guard gameState.sessionEnded == nil else { return }

        gameState.commitSessionStartIfNeeded(lowercaseMode: settings.lowercaseMode)
        let outcome = gameState.processAnswer(letter)
        let correctLetter = outcome.correctLetter

        if outcome.wasCorrect {
            answerAnimation = .correct(index: index)
            correctLetterIndex = index
            HapticService.shared.success()
            if settings.sfxEnabled { audioService.playCorrect() }
            confettiStyle = .standard
            confettiBurstID = UUID()
            showConfetti = canShowConfetti

            if let milestone = outcome.streakMilestone {
                switch milestone {
                case .five:
                    if settings.sfxEnabled { audioService.playStreak5() }
                    HapticService.shared.streakMilestone()
                case .ten:
                    if settings.sfxEnabled { audioService.playStreak10() }
                    HapticService.shared.streakMilestone()
                    screenShake = !reduceMotion
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await MainActor.run { screenShake = false }
                    }
                }
            }
        } else {
            let revealIndex = gameState.displayedLetters.firstIndex(of: correctLetter)
            let shouldShowReveal = gameState.secondMissedLetters.contains(correctLetter)
            answerAnimation = .incorrect(index: index)
            correctLetterIndex = shouldShowReveal ? nil : revealIndex
            HapticService.shared.wrongAnswer()
            if settings.sfxEnabled { audioService.playWrong() }
            if shouldShowReveal, let revealIndex {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await MainActor.run {
                        guard answerAnimation == .incorrect(index: index) else { return }
                        correctLetterIndex = revealIndex
                        answerAnimation = .revealing(index: revealIndex)
                        HapticService.shared.tap()
                        if settings.sfxEnabled {
                            playCurrentPrompt()
                        }
                    }
                }
            }
        }

        if let stamp = outcome.stampEarned {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { showStampPop = stamp }
            if settings.sfxEnabled { audioService.playStreak5() }
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run {
                    withAnimation { showStampPop = nil }
                }
            }
        }

        if let graduated = outcome.focusGraduated {
            showFocusGraduated = graduated
            HapticService.shared.streakMilestone()
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation { showFocusGraduated = nil }
                }
            }
        }

        if let level = outcome.leveledUp {
            // Defer level-up overlay slightly so it doesn't collide with focus
            // graduation animation.
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    withAnimation { showLevelUp = level }
                    if settings.sfxEnabled { audioService.playStreak10() }
                }
            }
        }

        if let endReason = outcome.sessionEndReason {
            scheduleSessionEnd(reason: endReason)
            return
        }

        persistGameCheckpoint(advanceToNextRoundOnRestore: true)

        delayTask?.cancel()
        delayTask = Task {
            let revealedMiss = !outcome.wasCorrect && gameState.secondMissedLetters.contains(correctLetter)
            let delay: UInt64 = outcome.wasCorrect ? 1_000_000_000 : (revealedMiss ? 2_000_000_000 : 1_500_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showConfetti = false
                answerAnimation = .none
                correctLetterIndex = nil
                gameState.setupNewRound()
                if let endReason = gameState.sessionEnded {
                    scheduleSessionEnd(reason: endReason, immediate: true)
                    return
                }
                persistGameCheckpoint()
                prewarmCurrentPrompt()
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if settings.sfxEnabled {
                    playCurrentPrompt()
                }
                // Phase 1b/1d: round-start clock begins as soon as the
                // prompt audio dispatches. Distinct from
                // `setupNewRound()` (which prepares the grid) because
                // the child can't reasonably be expected to read until
                // they've heard the prompt.
                gameState.markRoundStarted()
            }
        }
    }

    // MARK: - Session end

    private func handleHomeTap() {
        guard !isEndingSession else { return }
        HapticService.shared.tap()
        isEndingSession = true
        delayTask?.cancel()
        sessionEndTask?.cancel()
        winnerCelebrationTask?.cancel()
        gameState.sessionEnded = .homeTapped
        let summary = gameState.makeSummary(reason: .homeTapped)
        profileManager.endSession(profileId: profile.id, summary: summary)
        checkpointStore.clear(profileId: profile.id)
        onHome()
    }

    private func handleDoneTap() {
        guard !isEndingSession else { return }
        HapticService.shared.success()
        if let milestone = gameState.claimableDailyGoalMilestone {
            profileManager.claimDailyPracticeWinner(profileId: profile.id, milestone: milestone)
        }
        startWinnerCelebration()
        // Hand-off delay tuned to the celebration timeline below: WOW
        // settles ~3.6 s, second confetti wave is still falling at ~5 s,
        // so 4.6 s lets the moment land before the summary screen takes
        // over.
        scheduleSessionEnd(reason: .goalComplete, delayOverride: 4_600_000_000)
    }

    private func startWinnerCelebration() {
        delayTask?.cancel()
        winnerCelebrationTask?.cancel()
        showWinnerWow = false
        confettiStyle = .celebration
        confettiBurstID = UUID()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showConfetti = canShowConfetti
        }

        winnerCelebrationTask = Task {
            // Beat 1 — t=0.45s: WOW punches in, primary haptic, "Wow!" voice
            // starts. Applause is scheduled inside AudioService at +0.55s
            // so it begins under the tail of the voice clip.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                playWowPunch()
                HapticService.shared.streakMilestone()
                if settings.sfxEnabled {
                    audioService.playWinnerCelebration(language: profile.language)
                }
            }

            // Beat 2 — t=0.7s: secondary haptic timed roughly under the
            // first peak of the applause clip so the celebration feels
            // physical, not just visual.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                HapticService.shared.streakMilestone()
            }

            // Beat 3 — t=3.6s: WOW fades out, leaving the second confetti
            // wave to carry the eye until session end at 4.6s.
            try? await Task.sleep(nanoseconds: 2_900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                    showWinnerWow = false
                }
            }
        }
    }

    /// Two-step punch on the WOW overlay: scale 0.4 -> 1.15 -> 1.0 so the
    /// text "pops and settles" instead of arriving on a single spring.
    private func playWowPunch() {
        guard !reduceMotion else {
            showWinnerWow = true
            return
        }
        wowOverlayScale = 0.4
        showWinnerWow = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            wowOverlayScale = 1.15
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                wowOverlayScale = 1.0
            }
        }
    }

    private func scheduleSessionEnd(
        reason: SessionEndReason,
        immediate: Bool = false,
        delayOverride: UInt64? = nil
    ) {
        guard !isEndingSession else { return }
        isEndingSession = true
        delayTask?.cancel()
        sessionEndTask?.cancel()
        gameState.sessionEnded = reason
        let summary = gameState.makeSummary(reason: reason)
        profileManager.endSession(profileId: profile.id, summary: summary)
        checkpointStore.clear(profileId: profile.id)
        let delay: UInt64 = delayOverride ?? (immediate ? 0 : 700_000_000)
        sessionEndTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onExit(summary)
            }
        }
    }

    private func completeWeeklyTestByParent() {
        guard !isEndingSession else { return }
        guard plan.dailyPracticeKind == .reviewTest else { return }
        isEndingSession = true
        delayTask?.cancel()
        sessionEndTask?.cancel()
        winnerCelebrationTask?.cancel()
        _ = profileManager.commitSessionStartIfNeeded(profileId: profile.id, lowercaseMode: settings.lowercaseMode)
        guard profileManager.skipActiveWeeklyAssessment(profileId: profile.id) else {
            isEndingSession = false
            return
        }
        gameState.sessionEnded = .practiceComplete
        let summary = gameState.makeSummary(reason: .practiceComplete)
        profileManager.endSession(profileId: profile.id, summary: summary)
        checkpointStore.clear(profileId: profile.id)
        onWeeklyTestCompletedByParent()
    }

    // MARK: - Audio helpers

    private func replayPrompt() {
        if suppressNextReplayTap {
            suppressNextReplayTap = false
            return
        }
        HapticService.shared.tap()
        // Phase 1c/1d: bump the per-round replay counter so
        // `ProfileManager.recordAnswer` records `didReplayPrompt` and
        // `replayCount` honestly when the answer eventually lands.
        // Distinct from `markRoundStarted()`: replaying the prompt is
        // a child-driven action that happens during an already-started
        // round, so the round-start timestamp is preserved and
        // response-time keeps measuring from the *first* time the
        // prompt fired.
        gameState.didReplayPrompt()
        playCurrentPrompt()
    }

    private func handleReplayLongPress() {
        suppressNextReplayTap = true
        guard plan.dailyPracticeKind == .reviewTest else { return }
        guard !isEndingSession else { return }
        HapticService.shared.tap()
        showWeeklyTestParentGate = true
    }

    private func playPrompt(after seconds: Double) {
        delayTask?.cancel()
        prewarmCurrentPrompt()
        delayTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if settings.sfxEnabled {
                    playCurrentPrompt()
                }
                // Phase 1b/1d: response-time measurement begins from
                // when the prompt fires for the round. Idempotent —
                // `markRoundStarted` keeps the original timestamp on
                // any subsequent invocation, so playing on a delay
                // doesn't reset a clock that's already running.
                gameState.markRoundStarted()
            }
        }
    }

    private var currentPromptTarget: FocusTarget {
        gameState.currentRound?.target ?? .letter(gameState.targetLetter)
    }

    private func prewarmCurrentPrompt() {
        audioService.preloadPrompt(
            for: gameState.currentActivityKind,
            target: currentPromptTarget,
            language: profile.language
        )
    }

    private func playCurrentPrompt() {
        audioService.playPrompt(
            for: gameState.currentActivityKind,
            target: currentPromptTarget,
            language: profile.language
        )
    }

    private func persistGameCheckpoint(advanceToNextRoundOnRestore: Bool = false) {
        guard !isEndingSession else { return }
        guard gameState.sessionEnded == nil else { return }
        let snapshot = gameState.captureSnapshot(advanceToNextRoundOnRestore: advanceToNextRoundOnRestore)
        checkpointStore.save(SessionCheckpointEnvelope(
            profileId: profile.id,
            kind: .game,
            savedAt: Date(),
            sessionPlan: plan,
            game: snapshot
        ))
    }
}

// MARK: - Stamp badge

/// Brand-aligned sticker stamp. Resting state is a soft cream chip with a
/// hairline border; filled state pops into the brand sun-yellow with an ink
/// glyph so a parent and the kid can both tell, at a glance, what's been
/// earned vs what's still up for grabs.
struct StampBadge: View {
    let stamp: DailyStamp
    let isFilled: Bool
    let isPopping: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(isFilled ? Color.sun : Color.white.opacity(0.7))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().stroke(
                        isFilled ? Color.ink.opacity(0.18) : Color.creamDeep,
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: isFilled ? Color.sun.opacity(0.45) : Color.ink.opacity(0.05),
                    radius: isFilled ? 6 : 2,
                    x: 0,
                    y: isFilled ? 3 : 1
                )
            Image(systemName: stamp.icon)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(isFilled ? .ink : Color.slate400.opacity(0.7))
        }
        .scaleEffect(isPopping ? 1.3 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPopping)
    }
}

// MARK: - New Letter Overlay

/// Modal scrim styled with the brand palette. Uses an ink-tinted dim layer
/// (warmer than `Color.black`) and a soft pastel keycap for the introduced
/// letter so the moment feels like a "meet your new friend" intro rather
/// than a system alert.
struct NewLetterOverlay: View {
    let letter: String
    let color: Color
    let avatar: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.ink.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 22) {
                Text(avatar).font(.system(size: 78))
                VStack(spacing: 4) {
                    Text("New today".uppercased())
                        .font(.brandEyebrow())
                        .tracking(2.6)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Meet your letter")
                        .font(.brandTitleL(26))
                        .tracking(-0.6)
                        .foregroundColor(.white)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.amberTint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.5), .clear, Color.ink.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        )
                        .frame(width: 200, height: 200)
                        .letterTileShadow()
                    Text(letter)
                        .font(.system(size: 138, weight: .black, design: .rounded))
                        .tracking(-3)
                        .foregroundColor(.ink)
                }
                Button(action: onDismiss) {
                    Text("Let's go")
                        .font(.brandTitleM(20))
                        .tracking(-0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LinearGradient(colors: [.leaf, .sky], startPoint: .leading, endPoint: .trailing))
                        )
                        .shadow(color: Color.leaf.opacity(0.4), radius: 12, x: 0, y: 6)
                }
            }
            .padding(.horizontal, 24)
        }
        .onTapGesture { onDismiss() }
    }
}

// MARK: - Day streak banner

struct DayStreakBanner: View {
    let days: Int
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.berry)
                Text("Day".uppercased())
                    .brandEyebrowStyle()
                Text("\(days)")
                    .font(.brandTitleL(24))
                    .tracking(-0.6)
                    .foregroundColor(.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.95))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.creamDeep, lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.10), radius: 14, x: 0, y: 6)
            Spacer()
        }
    }
}

// MARK: - Focus graduated overlay

struct FocusGraduatedOverlay: View {
    let letter: String
    let color: Color
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.sun, .berry],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 200, height: 200)
                    .shadow(color: Color.berry.opacity(0.45), radius: 18, x: 0, y: 10)
                Text(letter)
                    .font(.system(size: 110, weight: .black, design: .rounded))
                    .tracking(-3)
                    .foregroundColor(.white)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
                    .offset(x: 64, y: -64)
            }
            Text("You mastered it!")
                .font(.brandTitleL(26))
                .tracking(-0.6)
                .foregroundColor(.ink)
        }
    }
}

// MARK: - Winner celebration overlay

struct WinnerWowOverlay: View {
    let color: Color
    /// Driven externally by the two-step punch animation in
    /// `GameView.playWowPunch()` (0.4 -> 1.15 -> 1.0). Renders directly so
    /// the text "pops and settles" rather than easing in on a single spring.
    var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Soft halo behind the text so WOW reads against any
                // background tint and feels like the celebration is
                // emanating from the center of the screen.
                RadialGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.45),
                        color.opacity(0.18),
                        .clear
                    ]),
                    center: .center,
                    startRadius: 20,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.55
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Text("WOW!")
                        .font(.system(size: min(geometry.size.width * 0.22, 128), weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: color.opacity(0.85), radius: 18, x: 0, y: 8)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    Text("You did it!")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(color.opacity(0.9)))
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .scaleEffect(scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Level Up overlay

struct LevelUpCelebrationView: View {
    let level: AlphabetLevel
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.ink.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 22) {
                Text(level.badgeEmoji)
                    .font(.system(size: 96))
                    .scaleEffect(scale)
                VStack(spacing: 4) {
                    Text("Level up".uppercased())
                        .font(.brandEyebrow())
                        .tracking(2.6)
                        .foregroundColor(.white.opacity(0.7))
                    Text(level.displayName)
                        .font(.brandTitleXL(36))
                        .tracking(-1.2)
                        .foregroundColor(.white)
                }
                Button(action: onDismiss) {
                    Text("Yay!")
                        .font(.brandTitleM(20))
                        .tracking(-0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 38)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LinearGradient(colors: [.leaf, .sky], startPoint: .leading, endPoint: .trailing))
                        )
                        .shadow(color: Color.leaf.opacity(0.4), radius: 12, x: 0, y: 6)
                }
            }
            .padding()
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                    scale = 1.0
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run { onDismiss() }
                }
            }
        }
    }
}

// MARK: - Shake Modifier

struct ShakeModifier: ViewModifier {
    let shake: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: shake ? CGFloat.random(in: -5...5) : 0)
            .animation(
                shake ? Animation.linear(duration: 0.05).repeatCount(10, autoreverses: true) : .default,
                value: shake
            )
    }
}

#Preview {
    let manager = ProfileManager()
    return GameView(
        profile: Profile(avatarId: .lion, language: .english),
        plan: SessionPlan(
            warmupLength: 5,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        ),
        profileManager: manager,
        onExit: { _ in },
        onHome: {},
        onWeeklyTestCompletedByParent: {}
    )
    .environmentObject(manager)
    .environmentObject(AudioService.shared)
    .environmentObject(AppSettings())
    .environmentObject(SessionCheckpointStore())
}
