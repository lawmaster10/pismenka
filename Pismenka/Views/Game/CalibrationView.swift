//
//  CalibrationView.swift
//  Pismenka
//
//  One-time calibration that runs the very first time a profile enters the
//  game. It can stop early after a clear 10-12 round read, otherwise it keeps
//  going up to ~20-22 rounds drawn from a generalized early-recognition pool
//  (`LetterDifficulty.earlyRecognitionLetters` plus the first letter of the
//  child's name when it isn't already in that set), so the kid starts on
//  letters most preschoolers know first and on a personally meaningful one.
//  Records every answer through `ProfileManager.recordAnswer` so `isKnown` is
//  determined by real performance, never assumed.
//

import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var audioService: AudioService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var checkpointStore: SessionCheckpointStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let profile: Profile
    /// Which learning layer this calibration measures. `.letters` runs the
    /// classic letter pool; `.numbers` runs `NumberDifficulty.calibrationPool`
    /// (1…10) and flips `hasCompletedNumberCalibration` on completion.
    let layer: LearningLayer
    let restoredSnapshot: CalibrationSnapshot?
    let onComplete: () -> Void
    let onHome: () -> Void

    @State private var schedule: [String] = []
    @State private var currentIndex: Int = 0
    @State private var displayedLetters: [String] = []
    @State private var answerAnimation: AnswerAnimationState = .none
    @State private var correctLetterIndex: Int?
    @State private var showIntro = true
    @State private var showFinale = false
    @State private var roundsAnswered = 0
    @State private var calibrationResults: [Bool] = []
    @State private var showConfetti = false
    @State private var delayTask: Task<Void, Never>?
    @State private var isCompleting = false

    init(
        profile: Profile,
        layer: LearningLayer = .letters,
        restoredSnapshot: CalibrationSnapshot? = nil,
        onComplete: @escaping () -> Void,
        onHome: @escaping () -> Void
    ) {
        self.profile = profile
        self.layer = layer
        self.restoredSnapshot = restoredSnapshot
        self.onComplete = onComplete
        self.onHome = onHome
    }

    private var isNumbersLayer: Bool { layer == .numbers }

    private var hasCompletedLayerCalibration: Bool {
        isNumbersLayer ? profile.hasCompletedNumberCalibration : profile.hasCompletedCalibration
    }

    private var layerCalibrationPool: [String] {
        isNumbersLayer
            ? NumberDifficulty.calibrationPool()
            : LetterDifficulty.calibrationPool(
                for: profile.language,
                nameLetter: profile.firstNameLetterKey
            )
    }

    private func playTargetAudio() {
        if isNumbersLayer {
            audioService.playNumber(targetLetter, language: profile.language)
        } else {
            audioService.playLetter(targetLetter, language: profile.language)
        }
    }

    private var totalRounds: Int { schedule.count }
    private var reduceMotion: Bool { settings.reduceMotionEnabled || systemReduceMotion }
    private var canShowConfetti: Bool { settings.confettiEnabled && !reduceMotion }

    private var targetLetter: String {
        guard currentIndex < schedule.count else { return "A" }
        return schedule[currentIndex]
    }

    var body: some View {
        ZStack {
            BrandBackground(accent: profile.colorTheme).ignoresSafeArea()

            if showIntro {
                introCard
                    .transition(.opacity)
            } else if showFinale {
                finaleCard
                    .transition(.opacity)
            } else {
                gameContent
                    .transition(.opacity)
            }

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showIntro)
        .animation(.easeInOut(duration: 0.3), value: showFinale)
        .onAppear {
            restoreOrBuildSchedule()
            persistCalibrationCheckpoint()
        }
        .onDisappear {
            persistCalibrationCheckpoint()
            delayTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistCalibrationCheckpoint()
            }
        }
    }

    // MARK: - Intro card

    private var introCard: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(profile.colorTheme)
                    .frame(width: 150, height: 150)
                    .shadow(color: profile.colorTheme.opacity(0.35), radius: 16, x: 0, y: 10)
                Text(profile.avatarId.emoji)
                    .font(.system(size: 92))
            }

            VStack(spacing: 6) {
                Text("Welcome".uppercased())
                    .brandEyebrowStyle()
                Text("Hi \(profile.displayName)")
                    .font(.brandTitleXL(36))
                    .tracking(-1.2)
                    .foregroundColor(.ink)
                Text("Let's see what you know")
                    .font(.brandBody(18, weight: .semibold))
                    .foregroundColor(.slate500)
            }

            Spacer()

            BrandIconButton(
                systemImage: "play.fill",
                action: {
                    HapticService.shared.tap()
                    withAnimation { showIntro = false }
                    playPrompt(after: 0.4)
                },
                size: 90,
                style: .leaf,
                accessibilityLabel: "Start calibration"
            )
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Game content

    /// Mirrors `GameView`'s session chrome: title + home up top, progress strip
    /// and replay play button along the bottom — so first-time calibration
    /// feels identical to the ordinary daily test.
    private var gameContent: some View {
        VStack(spacing: 10) {
            calibrationHeader
            LetterGrid(
                letters: displayedLetters,
                targetLetter: targetLetter,
                answerAnimation: answerAnimation,
                correctLetterIndex: correctLetterIndex,
                color: profile.colorTheme,
                onLetterTap: handleLetterTap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            bottomControlRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calibrationHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calibrationEyebrow.uppercased())
                    .brandEyebrowStyle()
                Text(calibrationTitle)
                    .font(.brandTitleL(26))
                    .tracking(-0.6)
                    .foregroundColor(.ink)
            }
            Spacer()
            homeButton(size: 40)
        }
    }

    private var calibrationEyebrow: String { "Assessment" }

    private var calibrationTitle: String {
        isNumbersLayer ? "Numbers" : "Letters"
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

    private var bottomControlRow: some View {
        HStack(alignment: .center, spacing: 12) {
            calibrationProgressStrip
                .layoutPriority(1)
            BrandIconButton(
                systemImage: "play.fill",
                action: {
                    HapticService.shared.tap()
                    playTargetAudio()
                },
                size: 58,
                style: .leaf,
                accessibilityLabel: "Replay sound"
            )
        }
    }

    private var calibrationProgress: Double {
        guard totalRounds > 0 else { return 0 }
        return Double(roundsAnswered) / Double(totalRounds)
    }

    private var calibrationProgressDisplayText: String {
        "\(roundsAnswered) / \(totalRounds)"
    }

    private var calibrationProgressStrip: some View {
        VStack(spacing: 8) {
            GradientProgressBar(progress: calibrationProgress)
                .accessibilityLabel("Assessment progress")
                .accessibilityValue(calibrationProgressDisplayText)
            HStack(alignment: .firstTextBaseline) {
                Text(calibrationProgressDisplayText)
                    .font(.brandBody(14, weight: .black))
                    .foregroundColor(.slate500)
                    .monospacedDigit()
                Spacer()
                Text("Keep going")
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

    private func handleHomeTap() {
        guard !isCompleting else { return }
        HapticService.shared.tap()
        isCompleting = true
        delayTask?.cancel()
        checkpointStore.clear(profileId: profile.id, layer: layer)
        onHome()
    }

    // MARK: - Finale

    private var finaleCard: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(profile.colorTheme)
                    .frame(width: 150, height: 150)
                    .shadow(color: profile.colorTheme.opacity(0.35), radius: 16, x: 0, y: 10)
                Text(profile.avatarId.emoji)
                    .font(.system(size: 92))
            }
            VStack(spacing: 6) {
                Text("Calibration".uppercased())
                    .brandEyebrowStyle()
                Text("Great job!")
                    .font(.brandTitleXL(40))
                    .tracking(-1.4)
                    .foregroundColor(.ink)
                Text("Let's play")
                    .font(.brandBody(18, weight: .semibold))
                    .foregroundColor(.slate500)
            }
            Spacer()
            BrandIconButton(
                systemImage: "arrow.right",
                action: {
                    HapticService.shared.tap()
                    isCompleting = true
                    checkpointStore.clear(profileId: profile.id, layer: layer)
                    if isNumbersLayer {
                        profileManager.markNumberCalibrationComplete(profileId: profile.id)
                    } else {
                        profileManager.markCalibrationComplete(profileId: profile.id)
                    }
                    onComplete()
                },
                size: 90,
                style: .leaf,
                accessibilityLabel: "Start playing"
            )
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .onAppear {
            HapticService.shared.success()
            if settings.sfxEnabled {
                audioService.playStreak10()
            }
            withAnimation(reduceMotion ? nil : .default) { showConfetti = canShowConfetti }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { showConfetti = false }
            }
        }
    }

    // MARK: - Schedule + round building

    private func restoreOrBuildSchedule() {
        if let restoredSnapshot {
            guard isValidRestoredSnapshot(restoredSnapshot) else {
                checkpointStore.clear(profileId: profile.id, layer: layer)
                buildSchedule()
                return
            }
            schedule = restoredSnapshot.schedule
            currentIndex = restoredSnapshot.currentIndex
            displayedLetters = restoredSnapshot.displayedLetters
            roundsAnswered = restoredSnapshot.roundsAnswered
            showIntro = restoredSnapshot.showIntro
            showFinale = restoredSnapshot.showFinale
            if restoredSnapshot.advanceToNextRoundOnRestore {
                advance()
            }
            return
        }
        buildSchedule()
    }

    private func isValidRestoredSnapshot(_ snapshot: CalibrationSnapshot) -> Bool {
        guard snapshot.learningLayer == layer,
              !snapshot.schedule.isEmpty,
              snapshot.currentIndex >= 0,
              snapshot.currentIndex <= snapshot.schedule.count,
              snapshot.roundsAnswered >= 0,
              snapshot.roundsAnswered <= snapshot.schedule.count else {
            return false
        }

        let pool = Set(layerCalibrationPool)
        guard snapshot.schedule.allSatisfy({ pool.contains($0) }) else { return false }

        if snapshot.showFinale || snapshot.currentIndex == snapshot.schedule.count {
            return true
        }

        let target = snapshot.schedule[snapshot.currentIndex]
        let displayed = snapshot.displayedLetters
        return displayed.count == 4
            && Set(displayed).count == displayed.count
            && displayed.contains(target)
            && displayed.allSatisfy { pool.contains($0) }
    }

    private func buildSchedule() {
        let pool = layerCalibrationPool
        let nameLetter = isNumbersLayer
            ? nil
            : LetterDifficulty.nameLetterForCalibration(
                profile.firstNameLetterKey,
                language: profile.language
            )

        // Every pool letter appears exactly twice. With the standard 10-letter
        // pool that's 20 rounds; when the child's name letter adds an 11th,
        // it's 22. Early-stop logic in `shouldStopCalibrationEarly` wraps
        // things up after ~10-12 rounds when confidence is already clear, so
        // the extra two rounds only show for kids whose evidence is genuinely
        // mixed.
        var draft = (pool + pool).shuffled()

        // Soft "no two consecutive same" pass — keeps the cadence varied
        // without forcing a strict permutation (which would over-constrain
        // the small pool and bias toward a predictable pattern).
        for i in 1..<draft.count {
            if draft[i] == draft[i - 1] {
                if let swapIndex = (i + 1..<draft.count).first(where: { draft[$0] != draft[i - 1] }) {
                    draft.swapAt(i, swapIndex)
                }
            }
        }

        // Front-load the child's name letter so the very first round is a
        // personally meaningful, high-confidence prompt — only if doing so
        // doesn't immediately create a consecutive duplicate at position 1.
        if let nameLetter,
           draft.count >= 2,
           draft.first != nameLetter,
           draft[1] != nameLetter,
           let nameIndex = draft.firstIndex(of: nameLetter) {
            draft.swapAt(0, nameIndex)
        }

        schedule = draft
        if let first = schedule.first {
            displayedLetters = buildOptions(target: first, pool: pool)
        }
    }

    private func buildOptions(target: String, pool: [String]) -> [String] {
        let candidates: [String]
        if isNumbersLayer {
            candidates = pool.filter { $0 != target && !NumberDifficulty.isHardConfusable(target, $0) }
        } else {
            let confusing = LetterDifficulty.visuallyConfusingPairs[target] ?? []
            candidates = pool.filter { $0 != target && !confusing.contains($0) }
        }
        var distractors = Array(candidates.shuffled().prefix(3))
        if distractors.count < 3 {
            // Top up from the full pool ignoring the confusing filter.
            let extra = pool.filter { $0 != target && !distractors.contains($0) }.shuffled()
            distractors.append(contentsOf: extra.prefix(3 - distractors.count))
        }
        return ([target] + distractors).shuffled()
    }

    // MARK: - Letter tap handling

    private func handleLetterTap(_ letter: String, index: Int) {
        guard answerAnimation == .none else { return }
        let isCorrect = letter == targetLetter
        if isCorrect {
            answerAnimation = .correct(index: index)
            correctLetterIndex = index
            HapticService.shared.success()
            if settings.sfxEnabled { audioService.playCorrect() }
            withAnimation(reduceMotion ? nil : .default) { showConfetti = canShowConfetti }
        } else {
            answerAnimation = .incorrect(index: index)
            correctLetterIndex = displayedLetters.firstIndex(of: targetLetter)
            HapticService.shared.wrongAnswer()
            if settings.sfxEnabled { audioService.playWrong() }
        }

        if isNumbersLayer {
            profileManager.recordAnswer(
                profileId: profile.id,
                target: .number(targetLetter),
                wasCorrect: isCorrect,
                asTarget: true,
                selectedWrongTarget: isCorrect ? nil : .number(letter),
                optionsShown: displayedLetters.map { .number($0) },
                activityKind: .numberRecognition
            )
            for shown in displayedLetters where shown != targetLetter {
                profileManager.recordExposure(profileId: profile.id, target: .number(shown))
            }
        } else {
            profileManager.recordAnswer(
                profileId: profile.id,
                letter: targetLetter,
                wasCorrect: isCorrect,
                asTarget: true
            )
            for shown in displayedLetters where shown != targetLetter {
                profileManager.recordExposure(profileId: profile.id, letter: shown)
            }
        }

        roundsAnswered += 1
        calibrationResults.append(isCorrect)
        if calibrationResults.count > 12 {
            calibrationResults.removeFirst(calibrationResults.count - 12)
        }
        persistCalibrationCheckpoint(advanceToNextRoundOnRestore: true)

        delayTask?.cancel()
        delayTask = Task {
            let delay: UInt64 = isCorrect ? 1_000_000_000 : 1_500_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { advance() }
        }
    }

    private func advance() {
        showConfetti = false
        answerAnimation = .none
        correctLetterIndex = nil
        currentIndex += 1

        if shouldStopCalibrationEarly {
            persistCalibrationCheckpoint()
            withAnimation { showFinale = true }
            return
        }

        if currentIndex >= schedule.count {
            persistCalibrationCheckpoint()
            withAnimation { showFinale = true }
            return
        }
        displayedLetters = buildOptions(target: schedule[currentIndex], pool: layerCalibrationPool)
        persistCalibrationCheckpoint()
        playPrompt(after: 0.3)
    }

    private var shouldStopCalibrationEarly: Bool {
        guard roundsAnswered >= 10 else { return false }
        let totalCorrect = calibrationResults.filter { $0 }.count
        let accuracy = Double(totalCorrect) / Double(max(1, calibrationResults.count))
        if roundsAnswered >= 10, accuracy >= 0.8 || accuracy <= 0.3 {
            return true
        }
        let lastFive = calibrationResults.suffix(5)
        if lastFive.count == 5 && lastFive.filter({ !$0 }).count >= 3 {
            return true
        }
        return roundsAnswered >= 12 && (accuracy >= 0.75 || accuracy <= 0.4)
    }

    private func playPrompt(after seconds: Double) {
        delayTask?.cancel()
        delayTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if settings.sfxEnabled {
                    if isNumbersLayer {
                        audioService.playNumber(targetLetter, language: profile.language)
                    } else {
                        audioService.playFindPrompt(letter: targetLetter, language: profile.language)
                    }
                }
            }
        }
    }

    private func persistCalibrationCheckpoint(advanceToNextRoundOnRestore: Bool = false) {
        guard !hasCompletedLayerCalibration, !isCompleting else { return }
        profileManager.flushPendingSave()
        let snapshot = CalibrationSnapshot(
            schedule: schedule,
            currentIndex: currentIndex,
            displayedLetters: displayedLetters,
            roundsAnswered: roundsAnswered,
            showIntro: showIntro,
            showFinale: showFinale,
            advanceToNextRoundOnRestore: advanceToNextRoundOnRestore,
            learningLayer: layer
        )
        checkpointStore.save(
            SessionCheckpointEnvelope(
                profileId: profile.id,
                kind: .calibration,
                learningLayer: layer,
                savedAt: Date(),
                calibration: snapshot
            ),
            layer: layer
        )
    }
}

#Preview {
    CalibrationView(
        profile: Profile(avatarId: .lion, language: .english),
        onComplete: {},
        onHome: {}
    )
    .environmentObject(ProfileManager())
    .environmentObject(AudioService.shared)
    .environmentObject(AppSettings())
    .environmentObject(SessionCheckpointStore())
}
