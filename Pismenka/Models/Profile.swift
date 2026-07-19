//
//  Profile.swift
//  Pismenka
//
//  Per-child profile model. Tracks per-letter mastery (LetterStat), the
//  current focus letter being drilled, day-streak / session-streak data, and
//  the lifetime set of letters that have ever been mastered.
//

import Foundation
import SwiftUI

// MARK: - Profile Model

struct LetterPracticeSummary: Equatable {
    let attemptedLetterCount: Int
    let targetAttempts: Int
    let targetCorrect: Int

    var accuracy: Double {
        guard targetAttempts > 0 else { return 0 }
        return Double(targetCorrect) / Double(targetAttempts)
    }
}

enum WeeklyAssessmentOutcome: String, Codable, Equatable {
    case pending
    case retained
    case watch
    case observed
    case needsReview
}

enum WeeklyAssessmentStrategy: String, Codable, Equatable {
    case legacyCohort
    case adaptiveAudit
}

enum WeeklyAssessmentBucket: String, Codable, Equatable, CaseIterable {
    case cohort
    case slipped
    case emerging
    case solid
    case fluent
    case parentMarked

    var plannedAttempts: Int {
        switch self {
        case .cohort: return 4
        case .slipped: return 3
        case .emerging: return 3
        case .solid, .fluent, .parentMarked: return 1
        }
    }

    var maxExtensions: Int {
        switch self {
        case .parentMarked: return 0
        // Every measuring bucket gets a single extension on a borderline
        // result, so a 4-year-old's one-tap slip never definitively dooms a
        // letter. The borderline triggers are bucket-specific (see
        // `WeeklyAssessmentLetterResult.extendIfNeededAfterLatestAttempt`).
        case .cohort, .slipped, .emerging, .solid, .fluent: return 1
        }
    }

    var displayLabel: String {
        switch self {
        case .cohort: return "New this week"
        case .slipped: return "Slipped"
        case .emerging: return "Emerging"
        case .solid: return "Solid"
        case .fluent: return "Fluent"
        case .parentMarked: return "Parent-marked"
        }
    }

    fileprivate var unresolvedCompletionOutcome: WeeklyAssessmentOutcome {
        switch self {
        case .cohort, .slipped, .emerging:
            return .needsReview
        case .solid, .fluent:
            return .watch
        case .parentMarked:
            return .observed
        }
    }
}

struct WeeklyAssessmentLetterResult: Codable, Equatable {
    static let requiredIndependentAttempts = 4
    static let retainedCorrectThreshold = 3

    var bucket: WeeklyAssessmentBucket
    var plannedAttempts: Int
    var maxExtensions: Int
    var extensionsUsed: Int
    var independentAttempts: Int
    var independentCorrect: Int
    var responseTimes: [TimeInterval]

    init(
        bucket: WeeklyAssessmentBucket = .cohort,
        plannedAttempts: Int? = nil,
        maxExtensions: Int? = nil,
        extensionsUsed: Int = 0,
        independentAttempts: Int = 0,
        independentCorrect: Int = 0,
        responseTimes: [TimeInterval] = []
    ) {
        self.bucket = bucket
        self.plannedAttempts = plannedAttempts ?? bucket.plannedAttempts
        self.maxExtensions = maxExtensions ?? bucket.maxExtensions
        self.extensionsUsed = extensionsUsed
        self.independentAttempts = independentAttempts
        self.independentCorrect = independentCorrect
        self.responseTimes = responseTimes
    }

    var attemptCap: Int {
        plannedAttempts + extensionsUsed
    }

    var needsMoreEvidence: Bool {
        outcome == .pending
    }

    var outcome: WeeklyAssessmentOutcome {
        switch bucket {
        case .cohort:
            guard independentAttempts >= plannedAttempts else { return .pending }
            if independentAttempts == plannedAttempts {
                // 4/4 or 3/4 → retained; 0–1/4 → decisive needsReview.
                // 2/4 is borderline: if an extension was granted by the
                // latest attempt, hold the verdict pending the 5th tap.
                if independentCorrect >= Self.retainedCorrectThreshold { return .retained }
                return extensionsUsed > 0 ? .pending : .needsReview
            }
            // After the bonus 5th attempt (only ever fires from a 2/4 split)
            // the same 3-correct bar settles the call.
            return independentCorrect >= Self.retainedCorrectThreshold ? .retained : .needsReview
        case .slipped:
            guard independentAttempts >= plannedAttempts else { return .pending }
            if independentAttempts == plannedAttempts {
                // 3/3 or 2/3 → retained; 0/3 → decisive needsReview.
                // 1/3 is borderline and earns a bonus 4th tap when the
                // extension budget allows it.
                if independentCorrect >= 2 { return .retained }
                return extensionsUsed > 0 ? .pending : .needsReview
            }
            return independentCorrect >= 2 ? .retained : .needsReview
        case .emerging:
            guard independentAttempts >= plannedAttempts else { return .pending }
            if independentAttempts == plannedAttempts {
                if independentCorrect == plannedAttempts { return .retained }
                if independentCorrect == 0 { return .needsReview }
                return extensionsUsed > 0 ? .pending : .retained
            }
            return independentCorrect >= 2 ? .retained : .needsReview
        case .solid:
            if independentAttempts == 0 { return .pending }
            if independentAttempts == 1 {
                if independentCorrect == 1 { return .retained }
                return extensionsUsed > 0 ? .pending : .needsReview
            }
            return independentCorrect >= 1 ? .retained : .needsReview
        case .fluent:
            if independentAttempts == 0 { return .pending }
            if independentAttempts == 1 {
                if independentCorrect == 1 { return .retained }
                return extensionsUsed > 0 ? .pending : .watch
            }
            return independentCorrect >= 1 ? .retained : .watch
        case .parentMarked:
            guard independentAttempts >= plannedAttempts else { return .pending }
            return .observed
        }
    }

    mutating func recordIndependentAttempt(wasCorrect: Bool, responseTime: TimeInterval?) {
        guard needsMoreEvidence else { return }
        independentAttempts += 1
        if wasCorrect { independentCorrect += 1 }
        if let responseTime {
            responseTimes.append(max(0, responseTime))
        }
        extendIfNeededAfterLatestAttempt()
    }

    private mutating func extendIfNeededAfterLatestAttempt() {
        guard independentAttempts == plannedAttempts,
              extensionsUsed < maxExtensions else {
            return
        }

        // Only fire the bonus attempt on a *borderline* outcome. Decisive
        // wins (no extension needed) and decisive failures (no rescue
        // possible) skip the extension to keep the test honest.
        switch bucket {
        case .cohort:
            if independentCorrect == 2 { extensionsUsed += 1 }
        case .slipped:
            if independentCorrect == 1 { extensionsUsed += 1 }
        case .emerging:
            if independentCorrect == 1 { extensionsUsed += 1 }
        case .solid, .fluent:
            if independentCorrect == 0 { extensionsUsed += 1 }
        case .parentMarked:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bucket, plannedAttempts, maxExtensions, extensionsUsed
        case independentAttempts, independentCorrect, responseTimes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try c.decodeIfPresent(WeeklyAssessmentBucket.self, forKey: .bucket) ?? .cohort
        plannedAttempts = try c.decodeIfPresent(Int.self, forKey: .plannedAttempts) ?? bucket.plannedAttempts
        maxExtensions = try c.decodeIfPresent(Int.self, forKey: .maxExtensions) ?? bucket.maxExtensions
        extensionsUsed = try c.decodeIfPresent(Int.self, forKey: .extensionsUsed) ?? 0
        independentAttempts = try c.decodeIfPresent(Int.self, forKey: .independentAttempts) ?? 0
        independentCorrect = try c.decodeIfPresent(Int.self, forKey: .independentCorrect) ?? 0
        responseTimes = try c.decodeIfPresent([TimeInterval].self, forKey: .responseTimes) ?? []
    }
}

struct WeeklyLetterAssessment: Identifiable, Codable, Equatable {
    /// Minimum visible session length on a review/test day. Set low because
    /// the test should *end* as soon as every audit letter resolves rather
    /// than padding the kid through filler review they don't need.
    static let adaptiveSessionFloor = 8
    /// Hard comfort target for review/test sessions. Progress checks are for small
    /// children, so breadth must yield before the session gets too long.
    static let adaptiveSessionCeiling = 40

    let id: UUID
    let scheduledFor: LocalDay
    let startedOn: LocalDay
    var cohortLetters: [String]
    var strategy: WeeklyAssessmentStrategy
    var assessmentRoundTarget: Int
    var dailyGoalTarget: Int
    var hardRoundCap: Int
    var results: [String: WeeklyAssessmentLetterResult]
    var completedOn: LocalDay?

    init(
        id: UUID = UUID(),
        scheduledFor: LocalDay,
        startedOn: LocalDay,
        cohortLetters: [String],
        strategy: WeeklyAssessmentStrategy = .legacyCohort,
        assessmentRoundTarget: Int? = nil,
        dailyGoalTarget: Int = 50,
        hardRoundCap: Int? = nil,
        results: [String: WeeklyAssessmentLetterResult] = [:],
        completedOn: LocalDay? = nil
    ) {
        self.id = id
        self.scheduledFor = scheduledFor
        self.startedOn = startedOn
        self.cohortLetters = cohortLetters
        self.strategy = strategy
        self.assessmentRoundTarget = assessmentRoundTarget ?? cohortLetters.count * WeeklyAssessmentLetterResult.requiredIndependentAttempts
        self.dailyGoalTarget = dailyGoalTarget
        self.hardRoundCap = hardRoundCap ?? dailyGoalTarget
        self.results = results
        self.completedOn = completedOn
        ensureResultSlots()
    }

    var isCompleted: Bool { completedOn != nil }

    var hasMetEvidenceQuota: Bool {
        !cohortLetters.isEmpty && lettersNeedingEvidence().isEmpty
    }

    var hasCoveredEveryLetter: Bool {
        !cohortLetters.isEmpty && cohortLetters.allSatisfy { letter in
            results[letter, default: WeeklyAssessmentLetterResult()].independentAttempts > 0
        }
    }

    var independentAssessmentAttempts: Int {
        results.values.reduce(0) { $0 + $1.independentAttempts }
    }

    var isAssessmentResolved: Bool {
        hasMetEvidenceQuota
    }

    var retainedLetters: Set<String> {
        Set(cohortLetters.filter { outcome(for: $0) == .retained })
    }

    var needsReviewLetters: Set<String> {
        Set(cohortLetters.filter { outcome(for: $0) == .needsReview })
    }

    var watchLetters: Set<String> {
        Set(cohortLetters.filter { outcome(for: $0) == .watch })
    }

    var observedLetters: Set<String> {
        Set(cohortLetters.filter { outcome(for: $0) == .observed })
    }

    func outcome(for letter: String) -> WeeklyAssessmentOutcome {
        let result = results[letter, default: WeeklyAssessmentLetterResult()]
        if completedOn != nil, result.needsMoreEvidence {
            return strategy == .legacyCohort ? .needsReview : result.bucket.unresolvedCompletionOutcome
        }
        return result.outcome
    }

    func lettersNeedingEvidence() -> [String] {
        cohortLetters.filter { letter in
            results[letter, default: WeeklyAssessmentLetterResult()].needsMoreEvidence
        }
    }

    func result(for letter: String) -> WeeklyAssessmentLetterResult {
        results[letter, default: WeeklyAssessmentLetterResult()]
    }

    mutating func recordIndependentAttempt(
        letter: String,
        wasCorrect: Bool,
        responseTime: TimeInterval?
    ) {
        guard cohortLetters.contains(letter), completedOn == nil else { return }
        var result = results[letter, default: WeeklyAssessmentLetterResult()]
        result.recordIndependentAttempt(wasCorrect: wasCorrect, responseTime: responseTime)
        results[letter] = result
    }

    mutating func complete(on day: LocalDay) {
        guard completedOn == nil else { return }
        completedOn = day
    }

    mutating func enforceQuestionLimit(_ maxQuestions: Int = adaptiveSessionCeiling) {
        guard maxQuestions > 0 else { return }
        guard !cohortLetters.isEmpty else {
            assessmentRoundTarget = 0
            dailyGoalTarget = min(dailyGoalTarget, maxQuestions)
            hardRoundCap = min(hardRoundCap, maxQuestions)
            return
        }

        guard strategy == .adaptiveAudit else {
            assessmentRoundTarget = min(assessmentRoundTarget, maxQuestions)
            dailyGoalTarget = min(dailyGoalTarget, maxQuestions)
            hardRoundCap = min(hardRoundCap, maxQuestions)
            return
        }

        let selectedLetters = cappedCohortLetters(maxQuestions: maxQuestions)
        let selected = Set(selectedLetters)
        cohortLetters = selectedLetters
        results = results.filter { selected.contains($0.key) }
        ensureResultSlots()

        let selectedPlannedAttempts = cohortLetters.reduce(0) { total, letter in
            total + results[letter, default: WeeklyAssessmentLetterResult()].plannedAttempts
        }
        assessmentRoundTarget = min(maxQuestions, max(1, selectedPlannedAttempts))

        let extensionBudget = cohortLetters.reduce(0) { total, letter in
            total + results[letter, default: WeeklyAssessmentLetterResult()].maxExtensions
        }
        let visibleExtensionBuffer = min(extensionBudget, max(0, assessmentRoundTarget / 10))
        let naturalGoal = assessmentRoundTarget + visibleExtensionBuffer
        dailyGoalTarget = min(maxQuestions, max(Self.adaptiveSessionFloor, naturalGoal))
        hardRoundCap = min(maxQuestions, max(dailyGoalTarget, assessmentRoundTarget))
    }

    private func cappedCohortLetters(maxQuestions: Int) -> [String] {
        var selected: [String] = []
        var plannedAttempts = 0

        for letter in cohortLetters {
            let result = results[letter, default: WeeklyAssessmentLetterResult()]
            let alreadyAttempted = result.independentAttempts > 0
            if alreadyAttempted || plannedAttempts + result.plannedAttempts <= maxQuestions {
                selected.append(letter)
                plannedAttempts += result.plannedAttempts
            }
        }

        if selected.isEmpty, let first = cohortLetters.first {
            selected.append(first)
        }

        return selected
    }

    private mutating func ensureResultSlots() {
        for letter in cohortLetters where results[letter] == nil {
            results[letter] = WeeklyAssessmentLetterResult()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, scheduledFor, startedOn, cohortLetters
        case strategy, assessmentRoundTarget, dailyGoalTarget, hardRoundCap
        case results, completedOn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        scheduledFor = try c.decode(LocalDay.self, forKey: .scheduledFor)
        startedOn = try c.decode(LocalDay.self, forKey: .startedOn)
        cohortLetters = try c.decode([String].self, forKey: .cohortLetters)
        strategy = try c.decodeIfPresent(WeeklyAssessmentStrategy.self, forKey: .strategy) ?? .legacyCohort
        results = try c.decodeIfPresent([String: WeeklyAssessmentLetterResult].self, forKey: .results) ?? [:]
        assessmentRoundTarget = try c.decodeIfPresent(Int.self, forKey: .assessmentRoundTarget)
            ?? results.values.reduce(0) { $0 + $1.plannedAttempts }
        dailyGoalTarget = try c.decodeIfPresent(Int.self, forKey: .dailyGoalTarget) ?? 50
        hardRoundCap = try c.decodeIfPresent(Int.self, forKey: .hardRoundCap) ?? dailyGoalTarget
        completedOn = try c.decodeIfPresent(LocalDay.self, forKey: .completedOn)
        ensureResultSlots()
        if assessmentRoundTarget == 0 {
            assessmentRoundTarget = cohortLetters.count * WeeklyAssessmentLetterResult.requiredIndependentAttempts
        }
    }
}

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var avatarId: AvatarType
    var language: GameLanguage
    var modifiedAt: Date

    /// Per-letter mastery stats, keyed by uppercase letter. Populated by
    /// calibration (real answers) and updated by every regular round.
    var letterStats: [String: LetterStat]

    /// Czech reading syllable and word aggregates. These mirror `letterStats`
    /// mechanically but live in separate dictionaries so thresholds and
    /// confusion rules can diverge without key collisions.
    var syllableStats: [String: SyllableStat]
    var wordStats: [String: WordStat]

    /// True after the one-time calibration flow has finished.
    var hasCompletedCalibration: Bool

    /// The letter currently being drilled, if any. Cleared when the letter
    /// graduates (LetterStat.isFocusGraduated) or when the child reaches expert.
    var currentFocusLetter: String?

    /// The local calendar day the *current* focus letter was first
    /// introduced. Cleared together with `focusPracticedDays` when the focus
    /// is reset. Informational — primarily used by the parent dashboard.
    var focusStartedDay: LocalDay?

    /// Set of local-calendar days on which the *current* focus letter has
    /// been practiced. The single source of truth for the
    /// progressive-scaffolding fade — `focusActiveDays` is derived from this.
    ///
    /// Why a set of days instead of a counter? A monotonic `Int` is easy to
    /// drift out of sync with reality: if the app crashes mid-bump, if focus
    /// state is reset, or if the device clock jumps, the integer can become
    /// stale and falsify scaffolding on the next session. A set of `LocalDay`
    /// values is self-validating — duplicates collapse via `Set` semantics,
    /// and the scaffolding ladder is always recoverable by counting the set.
    var focusPracticedDays: Set<LocalDay>

    /// Calendar gate: at most one focus introduction per local-calendar day.
    /// The stored key is `lastNewLetterDay` for migration compatibility, but
    /// the gate now applies to letters, slabiky, and words.
    var lastNewLetterDay: LocalDay?

    /// Daily cap for intentional cameo letters: future letters that appear as
    /// distractors only, without becoming formal focus/target introductions.
    static let dailyCameoExposureLimit = 3

    /// Local-day budget for cameo letters. Same-day "Play again" sessions keep
    /// spending from the same counter; a new local day starts fresh.
    var cameoExposureDay: LocalDay?
    var cameoExposuresToday: Int

    /// Local-day total for the visible daily practice goal. Same-day sessions
    /// accumulate into one counter so the progress bar resumes where the child
    /// left off.
    var dailyPracticeDay: LocalDay?
    var dailyPracticeAttempts: Int
    var dailyPracticeWinnerClaimedDay: LocalDay?
    var dailyPracticeWinnerClaimedMilestone: Int

    /// Per-letter *target ask* counts for the current local day, across all
    /// sittings. Backs the introduction-day "never more than 10 asks of one
    /// letter" cap so it holds per calendar day, not just per app sitting.
    var dailyTargetAskDay: LocalDay?
    var dailyTargetAskCounts: [String: Int]

    /// Practice-count rhythm state: after six completed 25-answer letter
    /// sessions, the next session is a retention check. The cohort set tracks
    /// letters intentionally introduced during that practice cycle.
    var learningCycleStartDay: LocalDay?
    var weeklyIntroducedLetters: Set<String>
    var completedLetterSessionsInCycle: Int
    var activeWeeklyAssessment: WeeklyLetterAssessment?
    var recentWeeklyAssessments: [WeeklyLetterAssessment]

    /// Last calendar day the child played; used for the "is today a new day?"
    /// check that powers the day streak and the focus-active-days bump.
    var lastSessionDay: LocalDay?

    /// Consecutive calendar days played, in a row. Resets to 1 if the child
    /// skips a day. The kid-meaningful "high score".
    var dailyStreakCount: Int

    /// Best `dailyStreakCount` ever — never decremented, never reset by
    /// `resetProgress`. The persistent trophy parents see.
    var bestDailyStreak: Int

    /// Lifetime set of letters that have *ever* satisfied the focus-graduation
    /// rule. Tracked as a Set (not just a counter) so a letter that graduates,
    /// later demotes, then graduates again is only counted once for level
    /// thresholds.
    var everMasteredLetters: Set<String>
    var everMasteredSyllables: Set<String>
    var everMasteredWords: Set<String>

    /// Best in-session correct-streak ever — fun stat, surfaced on the session
    /// end screen.
    var bestSessionStreak: Int

    /// Set of letter storage-keys that have *intentionally* appeared for this
    /// profile — either as a target round (calibration or gameplay) or as
    /// the picked focus letter at session-start.
    ///
    /// Phase 0c (#8 fix). Before this field was persisted, `introducedLetters`
    /// was computed from `letterStats.keys ∪ currentFocusLetter`, which had
    /// a subtle bug: any letter that ever appeared as a *fallback distractor*
    /// — i.e., an accidental leak from the distractor selector when the
    /// known/attempted/calibration/introduced pools all came up empty —
    /// would silently end up in `letterStats` (with `distractorExposures > 0`)
    /// and therefore in `introducedLetters`. That made the "introduced" pool
    /// grow on its own without the app ever choosing to teach those letters,
    /// breaking both the "one new letter per day" rule and the warm-up /
    /// distractor priority hierarchy.
    ///
    /// With this stored set, "introduced" means exactly: "we (the teaching
    /// system) chose to show this letter as a target, or assigned it as the
    /// current focus." Fallback distractor leaks stay tracked separately as
    /// `SessionSummary.unintroducedExposures` and don't pollute the long-term
    /// teaching plan.
    var introducedLetters: Set<String>
    var introducedSyllables: Set<String>
    var introducedWords: Set<String>

    /// Focus letters paused by the stuck-focus escape hatch. They remain in
    /// history and can still be reviewed, but the next-focus picker skips them
    /// for a short cooldown so a hard letter cannot disappear forever.
    var pausedFocusLetters: Set<String>
    var pausedFocusLetterDays: [String: LocalDay]

    var currentSyllableFocus: String?
    var currentWordFocus: String?
    var syllablesUnlockedAt: LocalDay?
    var wordsUnlockedAt: LocalDay?
    var hasCompletedSyllableOnboarding: Bool
    var hasCompletedSyllableCalibration: Bool
    var hasCompletedWordOnboarding: Bool
    var hasCompletedWordCalibration: Bool
    var readingPracticePaused: Bool

    /// Provenance for the most recent focus-letter pick — *why* the picker
    /// chose what it chose. See `FocusSelectionReason` for the reason taxonomy.
    ///
    /// Phase 0d (#18 / addition B). Populated by `ProfileManager` whenever
    /// `commitSessionStartIfNeeded` introduces a fresh focus unit; cleared on
    /// any reset that drops the focus. The parent dashboard (Phase 4b) reads
    /// this to surface a "why this letter?" banner.
    ///
    /// Phase 0 is allowed to only ever produce `.nextInOrder` — that's the
    /// only rule the picker currently runs. Phase 3c rewrites the picker to
    /// fill in the other reasons without changing this field's shape, so
    /// downstream consumers can ship now.
    var lastFocusSelection: FocusSelectionReason?

    /// Rolling FIFO log of the most recent `RoundEvent.maxRetained` round
    /// outcomes (Phase 0e, #14 / addition A). Newest is appended at the
    /// end; once the cap is reached, the oldest is dropped. Use
    /// `appendRoundEvent(_:)` to maintain the cap rather than mutating
    /// the array directly.
    ///
    /// The log serves the parent dashboard (Phase 4b) and the DEBUG-only
    /// adaptive overlay (Phase 4g). It is never used by the round
    /// generator itself; `LetterStat` is the aggregate signal the game
    /// reads from.
    var recentRoundEvents: [RoundEvent]

    /// Parent-written profile note. Informational only; never read by the
    /// adaptive model.
    var parentNote: String?

    /// Highest `AlphabetLevel` this profile has ever reached. Monotonic — never
    /// decreases, never reset by `resetProgress` (a parent-meaningful trophy,
    /// like `bestDailyStreak`).
    ///
    /// Used by the dashboard to show "Best: Intermediate" if it ever diverges
    /// from `alphabetLevel`. The level-up *celebration trigger* is gated by
    /// `celebratedAlphabetLevels` instead — see below.
    var highestAlphabetLevelEverReached: AlphabetLevel

    /// The set of `AlphabetLevel`s for which a level-up celebration has already
    /// been shown to this child. Used as the single source of truth for
    /// "should we fire the celebration now?".
    ///
    /// Why a set rather than threshold arithmetic? Comparing
    /// `afterLevel > beforeLevel` (or against `highestAlphabetLevelEverReached`)
    /// works under the *current* mastery model where `everMasteredLetters`
    /// only grows. But any future change — a demotion path, a backup-restore,
    /// a parent-driven re-tagging of mastery, even a one-off bug that
    /// transiently clears the trophy — could re-cross a threshold and
    /// re-fire the celebration the child has already earned. A set is the
    /// minimal, durable guarantee that each level is celebrated *exactly
    /// once per profile, ever*.
    ///
    /// Preserved through `resetProgress` for the same reason: a parent who
    /// resets the calibration shouldn't make the child re-earn celebrations
    /// they've already seen.
    var celebratedAlphabetLevels: Set<AlphabetLevel>

    /// Last frozen letter-grid size from the most recent session start (4 / 6 /
    /// 8). Powers the ±2 between-session hysteresis in
    /// `AlphabetLevel.letterOptionsPerRound`: once a tier is earned, a single
    /// slipped letter shouldn't shrink the grid for the next session. `nil`
    /// before the first session, in which case the formula falls back to its
    /// promotion-only rule.
    var lastFrozenLetterOptionsPerRound: Int?

    /// Independent recognition outcomes grouped by the number of choices that
    /// were actually displayed. This measures grid skill separately from how
    /// many alphabet letters happen to be known.
    var gridPerformanceStats: [Int: GridPerformanceStat]

    static let maxNameLength = 8
    static let focusPauseCooldownDays = 7

    var colorTheme: Color { avatarId.themeColor }
    var backgroundColor: Color { avatarId.backgroundColor }
    var displayName: String {
        name.isEmpty ? avatarId.displayName : name
    }

    /// Ordered, unique letters from the child's typed name that exist in the
    /// active alphabet. Used only for gentle print/name connections, never as
    /// proof of mastery.
    var nameLetterKeys: [String] {
        var seen: Set<String> = []
        return name.uppercased().compactMap { character in
            let key = String(character)
            guard language.letters.contains(key), !seen.contains(key) else { return nil }
            seen.insert(key)
            return key
        }
    }

    var firstNameLetterKey: String? {
        nameLetterKeys.first
    }

    func cameoExposures(on day: LocalDay = LocalDay.today()) -> Int {
        cameoExposureDay == day ? cameoExposuresToday : 0
    }

    func hasCameoBudget(on day: LocalDay = LocalDay.today()) -> Bool {
        cameoExposures(on: day) < Self.dailyCameoExposureLimit
    }

    func dailyPracticeCount(on day: LocalDay = LocalDay.today()) -> Int {
        dailyPracticeDay == day ? dailyPracticeAttempts : 0
    }

    /// Per-letter target-ask counts for `day`; empty when the stored counts
    /// belong to an earlier local day.
    func dailyTargetAskCounts(on day: LocalDay = LocalDay.today()) -> [String: Int] {
        dailyTargetAskDay == day ? dailyTargetAskCounts : [:]
    }

    mutating func recordDailyTargetAsk(letter: String, on day: LocalDay = LocalDay.today()) {
        if dailyTargetAskDay != day {
            dailyTargetAskDay = day
            dailyTargetAskCounts = [:]
        }
        dailyTargetAskCounts[letter, default: 0] += 1
    }

    func dailyPracticeWinnerClaimedCount(on day: LocalDay = LocalDay.today()) -> Int {
        dailyPracticeWinnerClaimedDay == day ? max(0, dailyPracticeWinnerClaimedMilestone) : 0
    }

    mutating func recordDailyPracticeAttempt(on day: LocalDay = LocalDay.today()) {
        if dailyPracticeDay != day {
            dailyPracticeDay = day
            dailyPracticeAttempts = 0
            dailyPracticeWinnerClaimedDay = day
            dailyPracticeWinnerClaimedMilestone = 0
        }
        dailyPracticeAttempts += 1
    }

    mutating func claimDailyPracticeWinner(milestone: Int, on day: LocalDay = LocalDay.today()) {
        guard milestone > 0 else { return }
        if dailyPracticeWinnerClaimedDay != day {
            dailyPracticeWinnerClaimedDay = day
            dailyPracticeWinnerClaimedMilestone = 0
        }
        dailyPracticeWinnerClaimedMilestone = max(dailyPracticeWinnerClaimedMilestone, milestone)
    }

    func activePausedFocusLetters(on day: LocalDay = LocalDay.today()) -> Set<String> {
        Set(pausedFocusLetters.filter { letter in
            guard let pausedAt = pausedFocusLetterDays[letter] else { return true }
            return day.daysSince(pausedAt) < Self.focusPauseCooldownDays
        })
    }

    mutating func clearExpiredPausedFocusLetters(on day: LocalDay = LocalDay.today()) {
        let active = activePausedFocusLetters(on: day)
        pausedFocusLetters.formIntersection(active)
        pausedFocusLetterDays = pausedFocusLetterDays.filter { active.contains($0.key) }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        avatarId: AvatarType,
        language: GameLanguage = .system,
        modifiedAt: Date = Date(),
        letterStats: [String: LetterStat] = [:],
        syllableStats: [String: SyllableStat] = [:],
        wordStats: [String: WordStat] = [:],
        hasCompletedCalibration: Bool = false,
        currentFocusLetter: String? = nil,
        currentSyllableFocus: String? = nil,
        currentWordFocus: String? = nil,
        focusStartedDay: LocalDay? = nil,
        focusPracticedDays: Set<LocalDay> = [],
        syllablesUnlockedAt: LocalDay? = nil,
        wordsUnlockedAt: LocalDay? = nil,
        hasCompletedSyllableOnboarding: Bool = false,
        hasCompletedSyllableCalibration: Bool = false,
        hasCompletedWordOnboarding: Bool = false,
        hasCompletedWordCalibration: Bool = false,
        readingPracticePaused: Bool = false,
        lastNewLetterDay: LocalDay? = nil,
        cameoExposureDay: LocalDay? = nil,
        cameoExposuresToday: Int = 0,
        dailyPracticeDay: LocalDay? = nil,
        dailyPracticeAttempts: Int = 0,
        dailyPracticeWinnerClaimedDay: LocalDay? = nil,
        dailyPracticeWinnerClaimedMilestone: Int = 0,
        dailyTargetAskDay: LocalDay? = nil,
        dailyTargetAskCounts: [String: Int] = [:],
        learningCycleStartDay: LocalDay? = nil,
        weeklyIntroducedLetters: Set<String> = [],
        completedLetterSessionsInCycle: Int = 0,
        activeWeeklyAssessment: WeeklyLetterAssessment? = nil,
        recentWeeklyAssessments: [WeeklyLetterAssessment] = [],
        lastSessionDay: LocalDay? = nil,
        dailyStreakCount: Int = 0,
        bestDailyStreak: Int = 0,
        everMasteredLetters: Set<String> = [],
        everMasteredSyllables: Set<String> = [],
        everMasteredWords: Set<String> = [],
        bestSessionStreak: Int = 0,
        introducedLetters: Set<String> = [],
        introducedSyllables: Set<String> = [],
        introducedWords: Set<String> = [],
        pausedFocusLetters: Set<String> = [],
        pausedFocusLetterDays: [String: LocalDay] = [:],
        lastFocusSelection: FocusSelectionReason? = nil,
        recentRoundEvents: [RoundEvent] = [],
        highestAlphabetLevelEverReached: AlphabetLevel = .novice,
        celebratedAlphabetLevels: Set<AlphabetLevel> = [.novice],
        lastFrozenLetterOptionsPerRound: Int? = nil,
        gridPerformanceStats: [Int: GridPerformanceStat] = [:],
        parentNote: String? = nil
    ) {
        self.id = id
        self.name = String(name.prefix(Profile.maxNameLength))
        self.avatarId = avatarId
        self.language = language
        self.modifiedAt = modifiedAt
        self.letterStats = letterStats
        self.syllableStats = syllableStats
        self.wordStats = wordStats
        self.hasCompletedCalibration = hasCompletedCalibration
        self.currentFocusLetter = currentFocusLetter
        self.currentSyllableFocus = currentSyllableFocus
        self.currentWordFocus = currentWordFocus
        self.focusStartedDay = focusStartedDay
        self.focusPracticedDays = focusPracticedDays
        self.syllablesUnlockedAt = syllablesUnlockedAt
        self.wordsUnlockedAt = wordsUnlockedAt
        self.hasCompletedSyllableOnboarding = hasCompletedSyllableOnboarding
        self.hasCompletedSyllableCalibration = hasCompletedSyllableCalibration
        self.hasCompletedWordOnboarding = hasCompletedWordOnboarding
        self.hasCompletedWordCalibration = hasCompletedWordCalibration
        self.readingPracticePaused = readingPracticePaused
        self.lastNewLetterDay = lastNewLetterDay
        self.cameoExposureDay = cameoExposureDay
        self.cameoExposuresToday = cameoExposuresToday
        self.dailyPracticeDay = dailyPracticeDay
        self.dailyPracticeAttempts = dailyPracticeAttempts
        self.dailyPracticeWinnerClaimedDay = dailyPracticeWinnerClaimedDay
        self.dailyPracticeWinnerClaimedMilestone = dailyPracticeWinnerClaimedMilestone
        self.dailyTargetAskDay = dailyTargetAskDay
        self.dailyTargetAskCounts = dailyTargetAskCounts
        self.learningCycleStartDay = learningCycleStartDay
        self.weeklyIntroducedLetters = weeklyIntroducedLetters
        self.completedLetterSessionsInCycle = max(0, completedLetterSessionsInCycle)
        self.activeWeeklyAssessment = activeWeeklyAssessment
        self.recentWeeklyAssessments = recentWeeklyAssessments
        self.lastSessionDay = lastSessionDay
        self.dailyStreakCount = dailyStreakCount
        self.bestDailyStreak = bestDailyStreak
        self.everMasteredLetters = everMasteredLetters
        self.everMasteredSyllables = everMasteredSyllables
        self.everMasteredWords = everMasteredWords
        self.bestSessionStreak = bestSessionStreak
        self.introducedLetters = introducedLetters
        self.introducedSyllables = introducedSyllables
        self.introducedWords = introducedWords
        self.pausedFocusLetters = pausedFocusLetters
        self.pausedFocusLetterDays = pausedFocusLetterDays
        self.lastFocusSelection = lastFocusSelection
        self.recentRoundEvents = recentRoundEvents
        self.highestAlphabetLevelEverReached = highestAlphabetLevelEverReached
        self.celebratedAlphabetLevels = celebratedAlphabetLevels
        self.lastFrozenLetterOptionsPerRound = lastFrozenLetterOptionsPerRound
        self.gridPerformanceStats = gridPerformanceStats
        self.parentNote = parentNote
    }

    /// Tolerant decoder: every new field is optional so a partial dev-build
    /// payload still loads cleanly.
    ///
    /// Soft migrations handled here:
    ///   * `focusActiveDays: Int` (very old) → synthesize `focusPracticedDays`
    ///     by rolling back N distinct local days from today, preserving the
    ///     scaffolding ladder.
    ///   * `focusPracticedDays: Set<String>` (older) → decode as
    ///     `Set<LocalDay>`. The on-disk JSON is identical (an array of
    ///     "yyyy-MM-dd" strings) because `LocalDay` encodes to the same
    ///     single-string form, so this typically just works.
    ///   * `lastSessionDate / lastNewLetterDate / focusStartedDate: Date`
    ///     (older) → convert to `LocalDay` via the device calendar. We
    ///     deliberately do *not* keep the original `Date` precision; the
    ///     callers that read these fields all care about day-level identity,
    ///     which is exactly what `LocalDay` exposes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatarId = try c.decode(AvatarType.self, forKey: .avatarId)
        language = try c.decodeIfPresent(GameLanguage.self, forKey: .language) ?? .system
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        letterStats = try c.decodeIfPresent([String: LetterStat].self, forKey: .letterStats) ?? [:]
        syllableStats = try c.decodeIfPresent([String: SyllableStat].self, forKey: .syllableStats) ?? [:]
        wordStats = try c.decodeIfPresent([String: WordStat].self, forKey: .wordStats) ?? [:]
        hasCompletedCalibration = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedCalibration) ?? false
        currentFocusLetter = try c.decodeIfPresent(String.self, forKey: .currentFocusLetter)
        currentSyllableFocus = try c.decodeIfPresent(String.self, forKey: .currentSyllableFocus)
        currentWordFocus = try c.decodeIfPresent(String.self, forKey: .currentWordFocus)

        focusStartedDay = try Profile.decodeLocalDay(
            container: c,
            preferred: .focusStartedDay,
            legacyDate: .focusStartedDate
        )

        if let days = try c.decodeIfPresent(Set<LocalDay>.self, forKey: .focusPracticedDays) {
            focusPracticedDays = days
        } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .focusActiveDays), legacy > 0 {
            focusPracticedDays = Profile.synthesizeLegacyPracticedDays(count: legacy)
        } else {
            focusPracticedDays = []
        }

        lastNewLetterDay = try Profile.decodeLocalDay(
            container: c,
            preferred: .lastNewLetterDay,
            legacyDate: .lastNewLetterDate
        )
        cameoExposureDay = try c.decodeIfPresent(LocalDay.self, forKey: .cameoExposureDay)
        cameoExposuresToday = try c.decodeIfPresent(Int.self, forKey: .cameoExposuresToday) ?? 0
        dailyPracticeDay = try c.decodeIfPresent(LocalDay.self, forKey: .dailyPracticeDay)
        dailyPracticeAttempts = try c.decodeIfPresent(Int.self, forKey: .dailyPracticeAttempts) ?? 0
        dailyPracticeWinnerClaimedDay = try c.decodeIfPresent(LocalDay.self, forKey: .dailyPracticeWinnerClaimedDay)
        dailyPracticeWinnerClaimedMilestone = try c.decodeIfPresent(
            Int.self,
            forKey: .dailyPracticeWinnerClaimedMilestone
        ) ?? 0
        dailyTargetAskDay = try c.decodeIfPresent(LocalDay.self, forKey: .dailyTargetAskDay)
        dailyTargetAskCounts = try c.decodeIfPresent(
            [String: Int].self,
            forKey: .dailyTargetAskCounts
        ) ?? [:]
        learningCycleStartDay = try c.decodeIfPresent(LocalDay.self, forKey: .learningCycleStartDay)
        weeklyIntroducedLetters = try c.decodeIfPresent(Set<String>.self, forKey: .weeklyIntroducedLetters) ?? []
        if let saved = try c.decodeIfPresent(Int.self, forKey: .completedLetterSessionsInCycle) {
            completedLetterSessionsInCycle = max(0, saved)
        } else {
            // The old schema did not persist historical session completion.
            // Only today's claimed 25-answer chunks are trustworthy; neither
            // calendar age nor number of introduced letters proves a session
            // was actually finished.
            completedLetterSessionsInCycle = min(
                6,
                dailyPracticeWinnerClaimedMilestone / 25
            )
        }
        activeWeeklyAssessment = try c.decodeIfPresent(WeeklyLetterAssessment.self, forKey: .activeWeeklyAssessment)
        recentWeeklyAssessments = try c.decodeIfPresent([WeeklyLetterAssessment].self, forKey: .recentWeeklyAssessments) ?? []
        lastSessionDay = try Profile.decodeLocalDay(
            container: c,
            preferred: .lastSessionDay,
            legacyDate: .lastSessionDate
        )
        dailyStreakCount = try c.decodeIfPresent(Int.self, forKey: .dailyStreakCount) ?? 0
        bestDailyStreak = try c.decodeIfPresent(Int.self, forKey: .bestDailyStreak) ?? 0
        everMasteredLetters = try c.decodeIfPresent(Set<String>.self, forKey: .everMasteredLetters) ?? []
        everMasteredSyllables = try c.decodeIfPresent(Set<String>.self, forKey: .everMasteredSyllables) ?? []
        everMasteredWords = try c.decodeIfPresent(Set<String>.self, forKey: .everMasteredWords) ?? []
        bestSessionStreak = try c.decodeIfPresent(Int.self, forKey: .bestSessionStreak) ?? 0
        syllablesUnlockedAt = try Profile.decodeLocalDay(
            container: c,
            preferred: .syllablesUnlockedAt,
            legacyDate: .syllablesUnlockedDate
        )
        wordsUnlockedAt = try Profile.decodeLocalDay(
            container: c,
            preferred: .wordsUnlockedAt,
            legacyDate: .wordsUnlockedDate
        )
        hasCompletedSyllableOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSyllableOnboarding) ?? false
        hasCompletedSyllableCalibration = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSyllableCalibration) ?? false
        hasCompletedWordOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedWordOnboarding) ?? false
        hasCompletedWordCalibration = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedWordCalibration) ?? false
        readingPracticePaused = try c.decodeIfPresent(Bool.self, forKey: .readingPracticePaused)
            ?? (try c.decodeIfPresent(Bool.self, forKey: .postExpertPracticePaused) ?? false)

        // Migration: legacy payloads (saved before `introducedLetters` was
        // persisted) seed the set from the old computed-property formula —
        // every key that ever showed up in `letterStats`, plus the current
        // focus letter. That over-counts on legacy profiles by including
        // letters that were only ever fallback-distractor leaks, but it's
        // strictly safer than under-counting: an over-counted introduced
        // letter is just one we won't pick as the next focus until it's
        // genuinely mastered. From the next save onward, the field is
        // authoritative and only the explicit writers (target rounds,
        // focus introductions) can grow it.
        if let saved = try c.decodeIfPresent(Set<String>.self, forKey: .introducedLetters) {
            introducedLetters = saved
        } else {
            var seed = Set<String>(letterStats.keys)
            if let focus = currentFocusLetter { seed.insert(focus) }
            introducedLetters = seed
        }
        // Repair profiles produced while spotlight graduation was tied to
        // `currentFocusLetter`. The evidence is already present and strict
        // (7/8); only the lifetime bookkeeping entry was missed.
        for (key, stat) in letterStats {
            if introducedLetters.contains(key), stat.isFocusGraduated {
                everMasteredLetters.insert(key)
            }
        }
        introducedSyllables = try c.decodeIfPresent(Set<String>.self, forKey: .introducedSyllables)
            ?? Set(syllableStats.keys).union(currentSyllableFocus.map { [$0] } ?? [])
        introducedWords = try c.decodeIfPresent(Set<String>.self, forKey: .introducedWords)
            ?? Set(wordStats.keys).union(currentWordFocus.map { [$0] } ?? [])
        pausedFocusLetters = try c.decodeIfPresent(Set<String>.self, forKey: .pausedFocusLetters) ?? []
        let savedPausedFocusLetterDays = try c.decodeIfPresent([String: LocalDay].self, forKey: .pausedFocusLetterDays)
        pausedFocusLetterDays = savedPausedFocusLetterDays
            ?? Dictionary(uniqueKeysWithValues: pausedFocusLetters.map { ($0, LocalDay.today()) })

        // Phase 0d: legacy payloads simply have no provenance data — leave
        // the field nil. The next focus introduction will populate it. No
        // synthesis attempted; backfilling a fake reason ("must've been
        // nextInOrder") would lie about how the historic pick happened.
        lastFocusSelection = try c.decodeIfPresent(FocusSelectionReason.self, forKey: .lastFocusSelection)

        // Phase 0e: legacy payloads carry no round-event history; default
        // to an empty log. The cap is re-applied on `appendRoundEvent`,
        // not on decode, so a saved-and-bumped-cap migration would
        // honestly preserve the (oversized) historic log until the next
        // append trims it. Today the cap hasn't moved, so this is moot.
        recentRoundEvents = try c.decodeIfPresent([RoundEvent].self, forKey: .recentRoundEvents) ?? []
        parentNote = try c.decodeIfPresent(String.self, forKey: .parentNote)

        // Migration: profiles saved before this field existed get seeded from
        // their current `everMasteredLetters` count, so their existing badge
        // doesn't appear to "drop" on first load — and so we don't retrigger
        // celebrations for thresholds they already crossed.
        if let saved = try c.decodeIfPresent(AlphabetLevel.self, forKey: .highestAlphabetLevelEverReached)
            ?? (try c.decodeIfPresent(AlphabetLevel.self, forKey: .highestLevelEverReached)) {
            highestAlphabetLevelEverReached = saved
        } else {
            highestAlphabetLevelEverReached = AlphabetLevel.from(
                masteredCount: everMasteredLetters.count,
                language: language
            )
        }

        // Migration: profiles saved before this field existed get every level
        // up to and including `highestAlphabetLevelEverReached` marked as already
        // celebrated, so they cannot retroactively trigger a celebration for
        // a level they've effectively already seen.
        if let saved = try c.decodeIfPresent(Set<AlphabetLevel>.self, forKey: .celebratedAlphabetLevels)
            ?? (try c.decodeIfPresent(Set<AlphabetLevel>.self, forKey: .celebratedLevels)) {
            celebratedAlphabetLevels = saved
        } else {
            // Local-bind the threshold to avoid the closure capturing `self`
            // before `celebratedAlphabetLevels` is initialized.
            let highestRank = highestAlphabetLevelEverReached.rank
            celebratedAlphabetLevels = Set(
                AlphabetLevel.allCases.filter { $0.rank <= highestRank }
            )
        }

        // Legacy payloads simply have no previous frozen grid value. Leaving
        // it nil makes the next session use the promotion-only rule, which
        // matches historic behavior — there's nothing to "hold back to."
        lastFrozenLetterOptionsPerRound = try c.decodeIfPresent(
            Int.self,
            forKey: .lastFrozenLetterOptionsPerRound
        )
        gridPerformanceStats = try c.decodeIfPresent(
            [Int: GridPerformanceStat].self,
            forKey: .gridPerformanceStats
        ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, avatarId, language, modifiedAt
        case letterStats, syllableStats, wordStats, hasCompletedCalibration
        case currentFocusLetter, currentSyllableFocus, currentWordFocus
        // Canonical (LocalDay-typed) keys.
        case focusStartedDay, focusPracticedDays
        case syllablesUnlockedAt, wordsUnlockedAt
        case lastNewLetterDay, cameoExposureDay, cameoExposuresToday
        case dailyPracticeDay, dailyPracticeAttempts
        case dailyPracticeWinnerClaimedDay, dailyPracticeWinnerClaimedMilestone
        case dailyTargetAskDay, dailyTargetAskCounts
        case learningCycleStartDay, weeklyIntroducedLetters, completedLetterSessionsInCycle
        case activeWeeklyAssessment, recentWeeklyAssessments
        case lastSessionDay
        // Legacy keys, decoded only for soft migration. Never written.
        case focusStartedDate
        case syllablesUnlockedDate, wordsUnlockedDate
        case focusActiveDays
        case lastNewLetterDate, lastSessionDate
        case dailyStreakCount, bestDailyStreak
        case everMasteredLetters, everMasteredSyllables, everMasteredWords, bestSessionStreak
        case introducedLetters, introducedSyllables, introducedWords
        case pausedFocusLetters, pausedFocusLetterDays
        case hasCompletedSyllableOnboarding, hasCompletedSyllableCalibration
        case hasCompletedWordOnboarding, hasCompletedWordCalibration
        case readingPracticePaused
        case postExpertPracticePaused
        case lastFocusSelection
        case recentRoundEvents
        case parentNote
        case highestAlphabetLevelEverReached, celebratedAlphabetLevels
        case highestLevelEverReached, celebratedLevels
        case lastFrozenLetterOptionsPerRound
        case gridPerformanceStats
    }

    /// Custom encoder that writes only the canonical fields. The legacy
    /// `focusActiveDays` / `*Date` keys exist in `CodingKeys` purely for the
    /// read-side migration in `init(from:)`; we never want to write them
    /// back, so the on-disk schema converges to the new shape on the first
    /// post-migration save.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(avatarId, forKey: .avatarId)
        try c.encode(language, forKey: .language)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(letterStats, forKey: .letterStats)
        try c.encode(syllableStats, forKey: .syllableStats)
        try c.encode(wordStats, forKey: .wordStats)
        try c.encode(hasCompletedCalibration, forKey: .hasCompletedCalibration)
        try c.encodeIfPresent(currentFocusLetter, forKey: .currentFocusLetter)
        try c.encodeIfPresent(currentSyllableFocus, forKey: .currentSyllableFocus)
        try c.encodeIfPresent(currentWordFocus, forKey: .currentWordFocus)
        try c.encodeIfPresent(focusStartedDay, forKey: .focusStartedDay)
        try c.encode(focusPracticedDays, forKey: .focusPracticedDays)
        try c.encodeIfPresent(syllablesUnlockedAt, forKey: .syllablesUnlockedAt)
        try c.encodeIfPresent(wordsUnlockedAt, forKey: .wordsUnlockedAt)
        try c.encode(hasCompletedSyllableOnboarding, forKey: .hasCompletedSyllableOnboarding)
        try c.encode(hasCompletedSyllableCalibration, forKey: .hasCompletedSyllableCalibration)
        try c.encode(hasCompletedWordOnboarding, forKey: .hasCompletedWordOnboarding)
        try c.encode(hasCompletedWordCalibration, forKey: .hasCompletedWordCalibration)
        try c.encode(readingPracticePaused, forKey: .readingPracticePaused)
        try c.encodeIfPresent(lastNewLetterDay, forKey: .lastNewLetterDay)
        try c.encodeIfPresent(cameoExposureDay, forKey: .cameoExposureDay)
        try c.encode(cameoExposuresToday, forKey: .cameoExposuresToday)
        try c.encodeIfPresent(dailyPracticeDay, forKey: .dailyPracticeDay)
        try c.encode(dailyPracticeAttempts, forKey: .dailyPracticeAttempts)
        try c.encodeIfPresent(dailyPracticeWinnerClaimedDay, forKey: .dailyPracticeWinnerClaimedDay)
        try c.encode(dailyPracticeWinnerClaimedMilestone, forKey: .dailyPracticeWinnerClaimedMilestone)
        try c.encodeIfPresent(dailyTargetAskDay, forKey: .dailyTargetAskDay)
        try c.encode(dailyTargetAskCounts, forKey: .dailyTargetAskCounts)
        try c.encodeIfPresent(learningCycleStartDay, forKey: .learningCycleStartDay)
        try c.encode(weeklyIntroducedLetters, forKey: .weeklyIntroducedLetters)
        try c.encode(completedLetterSessionsInCycle, forKey: .completedLetterSessionsInCycle)
        try c.encodeIfPresent(activeWeeklyAssessment, forKey: .activeWeeklyAssessment)
        try c.encode(recentWeeklyAssessments, forKey: .recentWeeklyAssessments)
        try c.encodeIfPresent(lastSessionDay, forKey: .lastSessionDay)
        try c.encode(dailyStreakCount, forKey: .dailyStreakCount)
        try c.encode(bestDailyStreak, forKey: .bestDailyStreak)
        try c.encode(everMasteredLetters, forKey: .everMasteredLetters)
        try c.encode(everMasteredSyllables, forKey: .everMasteredSyllables)
        try c.encode(everMasteredWords, forKey: .everMasteredWords)
        try c.encode(bestSessionStreak, forKey: .bestSessionStreak)
        try c.encode(introducedLetters, forKey: .introducedLetters)
        try c.encode(introducedSyllables, forKey: .introducedSyllables)
        try c.encode(introducedWords, forKey: .introducedWords)
        try c.encode(pausedFocusLetters, forKey: .pausedFocusLetters)
        try c.encode(pausedFocusLetterDays, forKey: .pausedFocusLetterDays)
        try c.encodeIfPresent(lastFocusSelection, forKey: .lastFocusSelection)
        try c.encode(recentRoundEvents, forKey: .recentRoundEvents)
        try c.encodeIfPresent(parentNote, forKey: .parentNote)
        try c.encode(highestAlphabetLevelEverReached, forKey: .highestAlphabetLevelEverReached)
        try c.encode(celebratedAlphabetLevels, forKey: .celebratedAlphabetLevels)
        try c.encodeIfPresent(lastFrozenLetterOptionsPerRound, forKey: .lastFrozenLetterOptionsPerRound)
        try c.encode(gridPerformanceStats, forKey: .gridPerformanceStats)
    }

    // MARK: - Migration helpers

    /// Reads a `LocalDay?` from `preferred` if present, otherwise falls back
    /// to a legacy `Date?` field and converts it through the device calendar.
    /// Centralizing this keeps the three day fields (`focusStartedDay`,
    /// `lastNewLetterDay`, `lastSessionDay`) consistent.
    private static func decodeLocalDay(
        container c: KeyedDecodingContainer<CodingKeys>,
        preferred: CodingKeys,
        legacyDate: CodingKeys
    ) throws -> LocalDay? {
        if let day = try c.decodeIfPresent(LocalDay.self, forKey: preferred) {
            return day
        }
        if let date = try c.decodeIfPresent(Date.self, forKey: legacyDate) {
            return LocalDay.from(date)
        }
        return nil
    }

    /// Builds `n` distinct `LocalDay`s rolling back from today. Used only for
    /// the legacy `focusActiveDays: Int` migration path so a profile that
    /// previously had `focusActiveDays = 3` ends up with exactly 3 distinct
    /// practice days and the same scaffolding level.
    private static func synthesizeLegacyPracticedDays(count: Int, calendar: Calendar = .current) -> Set<LocalDay> {
        guard count > 0 else { return [] }
        var days = Set<LocalDay>()
        let today = LocalDay.today(calendar: calendar)
        for offset in 0..<count {
            days.insert(today.adding(days: -offset, calendar: calendar))
        }
        return days
    }

    // MARK: - Derived state

    mutating func markModified(at date: Date = Date()) {
        modifiedAt = date
    }

    /// Letters confidently known for review purposes.
    ///
    /// A letter is included when its `LetterStat.effectiveIsKnown` is true,
    /// which means either (a) the data-driven `isKnown` rule is satisfied
    /// (≥ 80% over the last 5 target attempts, min 2 attempts), or (b) the
    /// parent has issued a `.markedKnown` override.
    ///
    /// **Focus exception:** the current focus letter is excluded until it
    /// has formally graduated under the stricter `isFocusGraduated` rule
    /// (≥ 7/8 over the last 8 target attempts). This keeps a letter out of
    /// the warm-up / easy-distractor pools while we're still actively
    /// drilling it. A `.markedKnown` override BYPASSES the focus exception
    /// — when the parent explicitly says "they know it," we don't keep
    /// pretending we still need to teach it.
    ///
    /// **Override interactions:**
    ///   * `.markedKnown` always includes the letter (even if it's the focus).
    ///   * `.reset` always excludes the letter (even if data says known).
    ///   * Neither path touches the underlying performance counters.
    ///
    /// Centralizing the rule here means every consumer (warm-up, scaffolding,
    /// dashboard, focus selection) gets it for free.
    var knownLetters: Set<String> {
        Set(letterStats.compactMap { (key, stat) in
            guard stat.effectiveIsKnown else { return nil }
            // Focus exception applies only to data-driven knowing — an
            // explicit parent override means "stop drilling, they know it."
            if key == currentFocusLetter && !stat.isFocusGraduated {
                if case .markedKnown = stat.parentOverride { return key }
                return nil
            }
            return key
        })
    }

    var knownAlphabetLetterCount: Int {
        knownLetters.intersection(Set(language.letters)).count
    }

    /// Strong-known letters narrowed to the active language's alphabet. Used
    /// alongside `knownAlphabetLetterCount` to gate the 6- and 8-grid
    /// promotions in `AlphabetLevel.letterOptionsPerRound` — widening the
    /// grid only makes sense when the distractor pool is genuinely strong,
    /// not when it just barely clears the loose `isKnown` bar.
    var strongKnownAlphabetLetterCount: Int {
        strongKnownLetters.intersection(Set(language.letters)).count
    }

    var letterOptionsPerRound: Int {
        AlphabetLevel.letterOptionsPerRound(
            knownLetterCount: knownAlphabetLetterCount,
            strongKnownLetterCount: strongKnownAlphabetLetterCount,
            previousValue: lastFrozenLetterOptionsPerRound,
            gridPerformance: gridPerformanceStats,
            language: language
        )
    }

    /// Stronger known tier for hard distractor roles. Parent overrides are
    /// intentionally asymmetric with `knownLetters`:
    /// - `.markedKnown` makes a letter available to the gentle known pool, but
    ///   does not synthesize strong evidence.
    /// - `.reset` removes a letter from strong-known even if history was solid.
    var strongKnownLetters: Set<String> {
        Set(letterStats.compactMap { key, stat in
            if case .reset = stat.parentOverride { return nil }
            guard stat.isStrongKnown else { return nil }
            return key
        })
    }

    /// Hard-role tier: strong accuracy evidence plus stable, quick response
    /// times. Used for confusable distractors, visual-only traps, and other
    /// places where "correct but slow" is not enough.
    var fluentKnownLetters: Set<String> {
        Set(letterStats.compactMap { key, stat in
            if case .reset = stat.parentOverride { return nil }
            guard stat.isFluentKnown else { return nil }
            return key
        })
    }

    /// Parent-declared known letters that have not yet earned strong evidence.
    /// They can appear gently, but the engine treats them as unverified and
    /// keeps them out of proof-heavy roles.
    var parentMarkedKnownButUnverified: Set<String> {
        Set(letterStats.compactMap { key, stat in
            guard case .markedKnown = stat.parentOverride else { return nil }
            return stat.isStrongKnown ? nil : key
        })
    }

    /// Letters whose `LetterStat` *currently* satisfies the strict focus-
    /// graduation rule (≥ 7/8 over the last 8 target attempts). Live signal:
    /// this can shrink if the recent-results window drifts, even though the
    /// lifetime trophy in `everMasteredLetters` won't.
    ///
    /// Used by `ProfileLearningSnapshot.currentlyMasteredLetters` and the
    /// dashboard's nuanced category labels (Phase 4d).
    var currentlyMasteredLetters: Set<String> {
        Set(letterStats.compactMap { (key, stat) in
            stat.isFocusGraduated ? key : nil
        })
    }

    var knownSyllables: Set<String> {
        Set(syllableStats.compactMap { key, stat in
            if key == currentSyllableFocus && !stat.isFocusGraduated { return nil }
            return stat.isKnown ? key : nil
        })
    }

    var knownWords: Set<String> {
        Set(wordStats.compactMap { key, stat in
            if key == currentWordFocus && !stat.isWordGraduated { return nil }
            return stat.isKnown ? key : nil
        })
    }

    var currentlyMasteredSyllables: Set<String> {
        Set(syllableStats.compactMap { key, stat in
            stat.isFocusGraduated ? key : nil
        })
    }

    var currentlyMasteredWords: Set<String> {
        Set(wordStats.compactMap { key, stat in
            stat.isWordGraduated ? key : nil
        })
    }

    /// Letters with at least one target attempt where the child isn't yet
    /// confidently known (under the loose review rule, override-aware). The
    /// "actively learning" pool.
    var learningLetters: Set<String> {
        Set(letterStats.compactMap { (key, stat) in
            (stat.targetAttempts > 0 && !stat.effectiveIsKnown) ? key : nil
        })
    }

    /// Letters in the active language alphabet that have never appeared in
    /// any way for this profile. Used by the dashboard's "Not yet seen"
    /// category and any pre-flight checks that want to know "is there
    /// anything left to introduce?".
    var unseenLetters: Set<String> {
        let alphabet = Set(language.letters)
        return alphabet.subtracting(introducedLetters)
    }

    var unseenSyllables: Set<String> {
        Set(SyllableCurriculum.allKeys(for: language)).subtracting(introducedSyllables)
    }

    var unseenWords: Set<String> {
        Set(WordCurriculum.allKeys(for: language)).subtracting(introducedWords)
    }

    /// True only after the app has intentionally taught and the child has
    /// formally mastered every letter in the active alphabet. This is the
    /// gate for moving from letters into Czech reading units.
    var hasCompletedAlphabetForReading: Bool {
        let alphabet = Set(language.letters)
        return !alphabet.isEmpty
            && alphabet.isSubset(of: introducedLetters)
            && alphabet.isSubset(of: everMasteredLetters)
    }

    var isReadingLayerUnlocked: Bool {
        syllablesUnlockedAt != nil && hasCompletedAlphabetForReading
    }

    /// Pre-computed view of every learning-related fact this profile exposes.
    /// Every consumer that previously asked the profile directly should read
    /// from this snapshot instead — see `ProfileLearningSnapshot` for the
    /// rationale.
    ///
    /// `nextFocusCandidate` uses the same prerequisite-aware picker as the
    /// runtime focus assignment path.
    var snapshot: ProfileLearningSnapshot {
        let known = knownLetters
        let strongKnown = strongKnownLetters
        let instructionalBand = AlphabetLevel.from(
            letterMasteredCount: strongKnown.intersection(everMasteredLetters).count,
            language: language
        )
        let readingStage = ReadingStage.from(
            syllablesUnlocked: isReadingLayerUnlocked,
            syllableMasteredCount: syllableMasteredCount,
            wordMasteredCount: wordMasteredCount
        )
        let nextSelection = LetterDifficulty.nextFocusWithReason(
            language: language,
            known: known,
            learning: learningLetters,
            mastered: everMasteredLetters,
            introduced: introducedLetters,
            letterStats: letterStats,
            lowercaseMode: instructionalBand.allowsAutomaticLowercaseTargets ? .afterUppercaseMastery : .uppercaseOnly,
            blocked: activePausedFocusLetters()
        )
        let now = Date()
        let eligibleIntroduced = introducedLetters.filter {
            LetterDifficulty.isEligibleTarget($0, language: language)
        }
        let dueReviews = eligibleIntroduced.filter { letter in
            letterStats[letter]?.isReviewDue(at: now) == true
        }.sorted { lhs, rhs in
            let left = letterStats[lhs]?.reviewPriority(at: now) ?? 0
            let right = letterStats[rhs]?.reviewPriority(at: now) ?? 0
            return left == right ? lhs < rhs : left > right
        }
        let weakReviews = eligibleIntroduced.filter { letter in
            guard letter != currentFocusLetter, let stat = letterStats[letter] else { return false }
            return stat.targetAttempts > 0 && !known.contains(letter)
        }.sorted { lhs, rhs in
            let left = letterStats[lhs]?.reviewPriority(at: now) ?? 0
            let right = letterStats[rhs]?.reviewPriority(at: now) ?? 0
            return left == right ? lhs < rhs : left > right
        }
        let dueSet = Set(dueReviews)
        let auditReviews = known.subtracting(dueSet).sorted { lhs, rhs in
            let left = letterStats[lhs]
            let right = letterStats[rhs]
            let leftUncertainty = left?.memoryState.uncertainty ?? 1
            let rightUncertainty = right?.memoryState.uncertainty ?? 1
            if leftUncertainty != rightUncertainty { return leftUncertainty > rightUncertainty }
            return (left?.lastTestedAt ?? .distantPast) < (right?.lastTestedAt ?? .distantPast)
        }
        return ProfileLearningSnapshot(
            knownLetters: known,
            strongKnownLetters: strongKnown,
            fluentKnownLetters: fluentKnownLetters,
            parentMarkedKnownButUnverified: parentMarkedKnownButUnverified,
            currentlyMasteredLetters: currentlyMasteredLetters,
            everMasteredLetters: everMasteredLetters,
            knownSyllables: knownSyllables,
            currentlyMasteredSyllables: currentlyMasteredSyllables,
            everMasteredSyllables: everMasteredSyllables,
            knownWords: knownWords,
            currentlyMasteredWords: currentlyMasteredWords,
            everMasteredWords: everMasteredWords,
            learningLetters: learningLetters,
            unseenLetters: unseenLetters,
            unseenSyllables: unseenSyllables,
            unseenWords: unseenWords,
            recentlySlipped: Set(letterStats.compactMap { key, stat in
                (everMasteredLetters.contains(key) && stat.wasKnownBefore && !stat.isKnown) ? key : nil
            }),
            alphabetLevel: alphabetLevel,
            readingStage: readingStage,
            instructionalBand: instructionalBand,
            // Trophy field — read directly, never re-derived from current
            // stats. That's the whole point of having a persisted lifetime
            // best.
            highestAlphabetLevelEver: highestAlphabetLevelEverReached,
            currentFocus: currentFocusLetter,
            currentFocusTarget: currentFocusTarget,
            nextFocusCandidate: nextSelection?.key,
            nextFocusTarget: nextFocusTarget(letterSelection: nextSelection?.key),
            lettersByConfidence: lettersByConfidence,
            lettersByReviewPriority: lettersByReviewPriority,
            dueReviewLetters: dueReviews,
            weakReviewLetters: weakReviews,
            auditReviewLetters: auditReviews,
            totalLettersInLanguage: language.letters.count
        )
    }

    /// Known letters sorted by descending certainty. Used by the parent
    /// dashboard's "how sure are we?" sort, the easy-distractor pool, and any
    /// consumer that wants strength ordering. Correct-but-slow answers remain
    /// correct for mastery, but lower this certainty ordering.
    var lettersByConfidence: [String] {
        knownLetters.sorted { a, b in
            let sa = letterStats[a]?.certaintyScore ?? 0
            let sb = letterStats[b]?.certaintyScore ?? 0
            if sa != sb { return sa > sb }
            let ca = letterStats[a]?.confidenceScore ?? 0
            let cb = letterStats[b]?.confidenceScore ?? 0
            if ca != cb { return ca > cb }
            return a < b // stable tiebreaker
        }
    }

    /// Known letters sorted by descending `LetterStat.reviewPriority`
    /// (the FSRS-inspired scheduler priority: recall risk, weakness, lapse
    /// pressure, uncertainty, overdueness, follow-ups). Drives warm-up
    /// target selection from Phase 2b on. Letters tied on priority (or all
    /// at 0 because they have no recent activity yet) fall back to
    /// descending certainty so the order stays deterministic and "the
    /// strongest letter still tends to come first when nothing else
    /// distinguishes them."
    var lettersByReviewPriority: [String] {
        knownLetters.sorted { a, b in
            let pa = letterStats[a]?.reviewPriority ?? 0
            let pb = letterStats[b]?.reviewPriority ?? 0
            if pa != pb { return pa > pb }
            let sa = letterStats[a]?.certaintyScore ?? 0
            let sb = letterStats[b]?.certaintyScore ?? 0
            if sa != sb { return sa > sb }
            return a < b
        }
    }

    /// Distinct local-calendar days the current focus letter has been
    /// practiced. Derived from `focusPracticedDays` so it can never drift out
    /// of sync with the underlying record.
    var focusActiveDays: Int { focusPracticedDays.count }

    /// 3 → 0; the focus letter gets maximum elimination help on day 1 and
    /// progressively less each day, matching the way a parent would teach a
    /// new symbol.
    var focusScaffoldingLevel: Int {
        max(0, 4 - focusActiveDays)
    }

    var letterMasteredCount: Int { everMasteredLetters.count }
    var syllableMasteredCount: Int { everMasteredSyllables.count }
    var wordMasteredCount: Int { everMasteredWords.count }

    var letterPracticeSummary: LetterPracticeSummary {
        let attemptedStats = letterStats.values.filter { $0.targetAttempts > 0 }
        return LetterPracticeSummary(
            attemptedLetterCount: attemptedStats.count,
            targetAttempts: attemptedStats.reduce(0) { $0 + $1.targetAttempts },
            targetCorrect: attemptedStats.reduce(0) { $0 + $1.targetCorrect }
        )
    }

    var currentFocusTarget: FocusTarget? {
        if let letter = currentFocusLetter { return .letter(letter) }
        return nil
    }

    func nextFocusTarget(
        letterSelection: String?,
        wordAudio: CurriculumAudioAvailability? = nil
    ) -> FocusTarget? {
        _ = wordAudio
        if let letterSelection {
            return .letter(letterSelection)
        }
        return nil
    }

    /// The alphabet level a profile is at *right now*, based on lifetime
    /// letter mastery.
    /// It is monotonic during normal play, but can dip when progress is
    /// explicitly reset — keep `highestAlphabetLevelEverReached` as the trophy.
    var alphabetLevel: AlphabetLevel {
        AlphabetLevel.from(
            letterMasteredCount: letterMasteredCount,
            language: language
        )
    }

    var readingStage: ReadingStage {
        ReadingStage.from(
            syllablesUnlocked: isReadingLayerUnlocked,
            syllableMasteredCount: syllableMasteredCount,
            wordMasteredCount: wordMasteredCount
        )
    }

    // MARK: - Typed-symbol API edge
    //
    // Storage stays `[String: LetterStat]` / `Set<String>` / `String?`.
    // These accessors are the typed boundary new code uses to read per-letter
    // state without re-deriving storage keys by hand. Existing String-based
    // call sites continue to work unchanged because today's bare-letter keys
    // are byte-identical to `LetterSymbol.upper(letter).storageKey`.

    /// Resolve a bare-letter String (the legacy API form) into a typed symbol
    /// for this profile's language. Useful when bridging between String-keyed
    /// storage iteration and typed consumers.
    func symbol(for letter: String) -> LetterSymbol {
        LetterSymbol.decode(storageKey: letter, fallbackLanguage: language)
            ?? LetterSymbol.upper(letter, in: language)
    }

    func displayText(for letter: String) -> String {
        symbol(for: letter).displayText
    }

    /// Append a new `RoundEvent` to the rolling log, enforcing the
    /// `RoundEvent.maxRetained` FIFO cap. The single owner of write
    /// access to `recentRoundEvents` so callers can't accidentally
    /// bypass the cap.
    ///
    /// Phase 0e ships this as the only writer. Phase 1c will start
    /// calling it from `ProfileManager.recordAnswer` once the round-
    /// level signal capture (Phase 1b) is wired up.
    mutating func appendRoundEvent(_ event: RoundEvent) {
        recentRoundEvents.append(event)
        // Trim from the front (oldest first) when over cap. A `while`
        // loop tolerates a future cap reduction that drops the array
        // by more than one entry on a single append.
        while recentRoundEvents.count > RoundEvent.maxRetained {
            recentRoundEvents.removeFirst()
        }
    }

    // MARK: - Per-letter knowledge state

    /// Resolves the journey state of `letter` for this profile.
    ///
    /// Resolution order matters:
    ///   1. **Parent override** (if any) — surfaces the parent's explicit
    ///      action so the dashboard never pretends fake attempts happened.
    ///      `.markedKnown` → `.markedKnown`; `.reset` → `.parentReset`.
    ///   2. `.mastered` — anything ever in `everMasteredLetters` stays
    ///      mastered. (Real lifetime achievement; not parent-shadowable.)
    ///   3. `.focus` — the active drill letter, regardless of accuracy.
    ///   4. Stat-based states (`unseen → exposed → learning → tentative → known`).
    ///
    /// The override is checked first so the parent dashboard can honestly
    /// say "you marked this known on Apr 26" instead of inheriting whatever
    /// label the data would otherwise produce. The raw counters are still
    /// available alongside (`stat.targetAttempts`, `stat.accuracy`, etc.) so
    /// the parent can spot conflicts ("I marked it known but they're 1/5
    /// in real attempts").
    ///
    /// The split between `.tentative` and `.known` lets the parent dashboard
    /// honestly distinguish "they got it right twice in calibration" from
    /// "they get it right reliably across many real sessions." See
    /// `LetterKnowledgeState.confidentSampleThreshold`.
    func knowledgeState(for letter: String) -> LetterKnowledgeState {
        if let stat = letterStats[letter] {
            switch stat.parentOverride {
            case .markedKnown: return .markedKnown
            case .reset: return .parentReset
            case .none: break
            }
        }
        if currentlyMasteredLetters.contains(letter) { return .mastered }
        if everMasteredLetters.contains(letter),
           let stat = letterStats[letter],
           stat.wasKnownBefore,
           !stat.isKnown {
            return .recentlySlipped
        }
        if currentFocusLetter == letter { return .focus }
        guard let stat = letterStats[letter] else { return .unseen }
        if stat.targetAttempts == 0 {
            return stat.distractorExposures > 0 ? .exposed : .unseen
        }
        if stat.isKnown { return .confident }
        if stat.recentAccuracy(window: 5) >= 0.5 { return .gettingThere }
        return .needsHelp
    }
}

// MARK: - Weekly adaptive assessment planning

private struct WeeklyAssessmentPlanEntry {
    let letter: String
    let bucket: WeeklyAssessmentBucket

    var plannedAttempts: Int { bucket.plannedAttempts }
    var maxExtensions: Int { bucket.maxExtensions }
}

extension Profile {
    func buildAdaptiveWeeklyAssessment(
        scheduledFor: LocalDay,
        startedOn: LocalDay,
        legacyDailyGoal: Int = 50
    ) -> WeeklyLetterAssessment {
        let entries = cappedAdaptiveAssessmentPlanEntries(
            adaptiveAssessmentPlanEntries(),
            maxQuestions: WeeklyLetterAssessment.adaptiveSessionCeiling
        )
        let assessmentRoundTarget = entries.reduce(0) { $0 + $1.plannedAttempts }
        let extensionBudget = entries.reduce(0) { $0 + $1.maxExtensions }
        let visibleExtensionBuffer = min(extensionBudget, max(0, assessmentRoundTarget / 10))
        let naturalGoal = assessmentRoundTarget + visibleExtensionBuffer
        let dailyGoalTarget = min(
            WeeklyLetterAssessment.adaptiveSessionCeiling,
            max(WeeklyLetterAssessment.adaptiveSessionFloor, naturalGoal)
        )
        let hardRoundCap = min(
            WeeklyLetterAssessment.adaptiveSessionCeiling,
            max(dailyGoalTarget, assessmentRoundTarget)
        )
        let results = Dictionary(uniqueKeysWithValues: entries.map { entry in
            (
                entry.letter,
                WeeklyAssessmentLetterResult(
                    bucket: entry.bucket,
                    plannedAttempts: entry.plannedAttempts,
                    maxExtensions: entry.maxExtensions
                )
            )
        })

        if entries.isEmpty {
            return WeeklyLetterAssessment(
                scheduledFor: scheduledFor,
                startedOn: startedOn,
                cohortLetters: [],
                strategy: .legacyCohort,
                dailyGoalTarget: legacyDailyGoal
            )
        }

        return WeeklyLetterAssessment(
            scheduledFor: scheduledFor,
            startedOn: startedOn,
            cohortLetters: entries.map(\.letter),
            strategy: .adaptiveAudit,
            assessmentRoundTarget: assessmentRoundTarget,
            dailyGoalTarget: dailyGoalTarget,
            hardRoundCap: hardRoundCap,
            results: results
        )
    }

    private func adaptiveAssessmentPlanEntries() -> [WeeklyAssessmentPlanEntry] {
        // Every letter introduced during the six-session practice cycle is
        // treated as cohort regardless of current strength. High in-session
        // evidence on a spotlight letter says nothing about whether the child
        // retained it across subsequent play sessions. A parent-issued reset
        // still wins, but a normally-strong cohort letter does not skip the
        // four-attempt retention rerun.
        let weeklyCohort = Set(weeklyIntroducedLetters.filter { letter in
            guard LetterDifficulty.isEligibleTarget(letter, language: language) else { return false }
            if case .reset = letterStats[letter]?.parentOverride { return false }
            return true
        })
        let targetIntroduced = introducedLetters
            .union(letterStats.compactMap { letter, stat in
                stat.targetAttempts > 0 ? letter : nil
            })

        let candidates = targetIntroduced
            .union(snapshot.parentMarkedKnownButUnverified)
            .union(weeklyCohort)
            .filter { letter in
                guard LetterDifficulty.isEligibleTarget(letter, language: language) else { return false }
                if case .reset = letterStats[letter]?.parentOverride { return false }
                return true
            }

        let planned = candidates.map { letter in
            WeeklyAssessmentPlanEntry(
                letter: letter,
                bucket: adaptiveAssessmentBucket(for: letter, weeklyCohort: weeklyCohort)
            )
        }
        .sorted(by: adaptiveAssessmentSort)

        return planned
    }

    private func cappedAdaptiveAssessmentPlanEntries(
        _ entries: [WeeklyAssessmentPlanEntry],
        maxQuestions: Int
    ) -> [WeeklyAssessmentPlanEntry] {
        var selected: [WeeklyAssessmentPlanEntry] = []
        var plannedAttempts = 0

        for entry in entries where plannedAttempts + entry.plannedAttempts <= maxQuestions {
            selected.append(entry)
            plannedAttempts += entry.plannedAttempts
        }

        return selected
    }

    private func adaptiveAssessmentBucket(
        for letter: String,
        weeklyCohort: Set<String>
    ) -> WeeklyAssessmentBucket {
        if weeklyCohort.contains(letter) {
            return .cohort
        }
        if let stat = letterStats[letter],
           case .markedKnown = stat.parentOverride,
           !stat.isStrongKnown {
            return .parentMarked
        }
        if snapshot.recentlySlipped.contains(letter) {
            return .slipped
        }
        guard let stat = letterStats[letter] else {
            return .emerging
        }
        if stat.isFluentKnown {
            return .fluent
        }
        if stat.isStrongKnown || stat.evidenceStrength == .solid {
            return .solid
        }
        return .emerging
    }

    private func adaptiveAssessmentSort(
        _ lhs: WeeklyAssessmentPlanEntry,
        _ rhs: WeeklyAssessmentPlanEntry
    ) -> Bool {
        let leftPriority = adaptiveAssessmentPriority(lhs.bucket)
        let rightPriority = adaptiveAssessmentPriority(rhs.bucket)
        if leftPriority != rightPriority { return leftPriority < rightPriority }

        let leftReview = letterStats[lhs.letter]?.reviewPriority ?? 0
        let rightReview = letterStats[rhs.letter]?.reviewPriority ?? 0
        if leftReview != rightReview { return leftReview > rightReview }

        return lhs.letter < rhs.letter
    }

    private func adaptiveAssessmentPriority(_ bucket: WeeklyAssessmentBucket) -> Int {
        switch bucket {
        case .cohort: return 0
        case .slipped: return 1
        case .emerging: return 2
        case .solid: return 3
        case .parentMarked: return 4
        case .fluent: return 5
        }
    }

}

// MARK: - Avatar Type

enum AvatarType: String, Codable, CaseIterable {
    case lion
    case penguin
    case monkey
    case bear
    case giraffe
    case butterfly
    case elephant
    case fox
    case dog
    case cat
    case mouse
    case hamster
    case rabbit
    case panda
    case koala
    case tiger
    case leopard
    case gorilla
    case orangutan
    case raccoon
    case wolf
    case horse
    case donkey
    case unicorn
    case zebra
    case deer
    case moose
    case bison
    case cow
    case pig
    case boar
    case sheep
    case goat
    case camel
    case llama
    case rhinoceros
    case hippopotamus
    case mammoth
    case kangaroo
    case badger
    case skunk
    case otter
    case sloth
    case beaver
    case hedgehog
    case bat
    case turkey
    case chicken
    case duck
    case dove
    case eagle
    case owl
    case swan
    case dodo
    case flamingo
    case peacock
    case parrot
    case goose
    case frog
    case seal
    case whale
    case dolphin
    case fish
    case shark
    case octopus
    case crab
    case lobster
    case shrimp
    case squid
    case oyster
    case jellyfish
    case coral
    case turtle
    case crocodile
    case snake
    case lizard
    case dinosaur
    case dragon
    case snail
    case bee
    case ant
    case beetle
    case ladybug
    case cricket
    case cockroach
    case spider
    case scorpion
    case mosquito
    case fly
    case worm
    case caterpillar

    var displayName: String {
        rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())
    }

    var emoji: String {
        switch self {
        case .lion: return "🦁"
        case .penguin: return "🐧"
        case .monkey: return "🐵"
        case .bear: return "🐻"
        case .giraffe: return "🦒"
        case .butterfly: return "🦋"
        case .elephant: return "🐘"
        case .fox: return "🦊"
        case .dog: return "🐶"
        case .cat: return "🐱"
        case .mouse: return "🐭"
        case .hamster: return "🐹"
        case .rabbit: return "🐰"
        case .panda: return "🐼"
        case .koala: return "🐨"
        case .tiger: return "🐯"
        case .leopard: return "🐆"
        case .gorilla: return "🦍"
        case .orangutan: return "🦧"
        case .raccoon: return "🦝"
        case .wolf: return "🐺"
        case .horse: return "🐴"
        case .donkey: return "🫏"
        case .unicorn: return "🦄"
        case .zebra: return "🦓"
        case .deer: return "🦌"
        case .moose: return "🫎"
        case .bison: return "🦬"
        case .cow: return "🐮"
        case .pig: return "🐷"
        case .boar: return "🐗"
        case .sheep: return "🐑"
        case .goat: return "🐐"
        case .camel: return "🐪"
        case .llama: return "🦙"
        case .rhinoceros: return "🦏"
        case .hippopotamus: return "🦛"
        case .mammoth: return "🦣"
        case .kangaroo: return "🦘"
        case .badger: return "🦡"
        case .skunk: return "🦨"
        case .otter: return "🦦"
        case .sloth: return "🦥"
        case .beaver: return "🦫"
        case .hedgehog: return "🦔"
        case .bat: return "🦇"
        case .turkey: return "🦃"
        case .chicken: return "🐔"
        case .duck: return "🦆"
        case .dove: return "🕊️"
        case .eagle: return "🦅"
        case .owl: return "🦉"
        case .swan: return "🦢"
        case .dodo: return "🦤"
        case .flamingo: return "🦩"
        case .peacock: return "🦚"
        case .parrot: return "🦜"
        case .goose: return "🪿"
        case .frog: return "🐸"
        case .seal: return "🦭"
        case .whale: return "🐳"
        case .dolphin: return "🐬"
        case .fish: return "🐟"
        case .shark: return "🦈"
        case .octopus: return "🐙"
        case .crab: return "🦀"
        case .lobster: return "🦞"
        case .shrimp: return "🦐"
        case .squid: return "🦑"
        case .oyster: return "🦪"
        case .jellyfish: return "🪼"
        case .coral: return "🪸"
        case .turtle: return "🐢"
        case .crocodile: return "🐊"
        case .snake: return "🐍"
        case .lizard: return "🦎"
        case .dinosaur: return "🦖"
        case .dragon: return "🐉"
        case .snail: return "🐌"
        case .bee: return "🐝"
        case .ant: return "🐜"
        case .beetle: return "🪲"
        case .ladybug: return "🐞"
        case .cricket: return "🦗"
        case .cockroach: return "🪳"
        case .spider: return "🕷️"
        case .scorpion: return "🦂"
        case .mosquito: return "🦟"
        case .fly: return "🪰"
        case .worm: return "🪱"
        case .caterpillar: return "🐛"
        }
    }

    var themeColor: Color {
        Self.themePalette[paletteIndex]
    }

    var backgroundColor: Color {
        Self.backgroundPalette[paletteIndex]
    }

    private var paletteIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) % Self.themePalette.count
    }

    // Brand-aligned avatar accent palette. Twelve curated colors derived
    // from the Písmenka brand (sun/leaf/berry/sky/lavender/peach) instead
    // of the previous random hand-mixed hues. Every accent is a member of
    // a clear color family, so the per-avatar identity still reads
    // distinctly while the app as a whole feels designed.
    //
    // Order is preserved so existing profiles keep mapping to the "same
    // animal slot" they did before — the *colors* change, but each child's
    // chosen avatar still owns its slot.
    private static let themePalette: [Color] = [
        .sun,
        .sky,
        Color(red: 0.55, green: 0.40, blue: 0.25),
        Color(red: 0.96, green: 0.50, blue: 0.32),
        Color(red: 0.96, green: 0.65, blue: 0.18),
        Color(red: 0.62, green: 0.50, blue: 0.97),
        Color(red: 0.42, green: 0.52, blue: 0.62),
        .berry,
        .leaf,
        Color(red: 0.97, green: 0.50, blue: 0.70),
        Color(red: 0.40, green: 0.55, blue: 0.92),
        Color(red: 0.72, green: 0.46, blue: 0.85)
    ]

    // Soft, brand-aligned tints that pair with the accents above. Kept
    // available for the rare case a surface wants a per-avatar wash, but
    // the redesigned app primarily uses `BrandBackground()` for full-screen
    // surfaces and a small `accent:` bleed for identity.
    private static let backgroundPalette: [Color] = [
        .amberTint,
        .skyTint,
        .sandTint,
        .peachTint,
        .amberTint,
        .lavenderTint,
        .skyTint,
        .roseTint,
        .mintTint,
        .pinkTint,
        .indigoTint,
        .lavenderTint
    ]
}

// MARK: - Game Language

enum GameLanguage: String, Codable {
    case english = "en"
    case czech = "cz"
    case system

    var displayFlag: String {
        switch self {
        case .english: return "🇺🇸"
        case .czech: return "🇨🇿"
        case .system: return systemLanguage.displayFlag
        }
    }

    var audioPrefix: String {
        switch self {
        case .english: return "en"
        case .czech: return "cz"
        case .system: return systemLanguage.audioPrefix
        }
    }

    var resolvedLanguage: GameLanguage {
        if self == .system {
            return systemLanguage
        }
        return self
    }

    private var systemLanguage: GameLanguage {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        if preferredLanguage.starts(with: "cs") || preferredLanguage.starts(with: "cz") {
            return .czech
        }
        return .english
    }

    /// Letters for each language (extended alphabet with diacritics for Czech).
    var letters: [String] {
        switch resolvedLanguage {
        case .english:
            return (65...90).map { String(UnicodeScalar($0)) }
        case .czech:
            return ["A", "Á", "B", "C", "Č", "D", "Ď", "E", "É", "Ě",
                    "F", "G", "H", "I", "Í", "J", "K", "L", "M", "N",
                    "Ň", "O", "Ó", "P", "Q", "R", "Ř", "S", "Š", "T",
                    "Ť", "U", "Ú", "Ů", "V", "W", "X", "Y", "Ý", "Z", "Ž"]
        case .system:
            return systemLanguage.letters
        }
    }
}
