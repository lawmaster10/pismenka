//
//  GameState.swift
//  Pismenka
//
//  AdaptiveGameState — single-mode session controller. Owns the round
//  selection algorithm (warm-up → drill → plain review), focus-letter
//  scaffolding, hearts / stamps / streak bookkeeping, and rescue rounds.
//

import Foundation

// MARK: - Daily stamps (Today's focus card)

/// The four (or three) stamps a child can earn in a single session,
/// rendered as a "Today's focus card" on the game screen and the session-end
/// view. Always exactly one of the *opener* stamps below is in play per
/// session; which one is chosen is determined at session start by the
/// `SessionPlan` shape and exposed via `AdaptiveGameState.applicableStamps`.
///
/// Opener stamps (mutually exclusive — exactly one per session):
///   * `.warmupStar` — normal session with a real warm-up phase
///                     (`warmupLength > 0`, focus active or in plain review).
///   * `.braveStart` — sparse profile (`warmupLength == 0` because there
///                     are fewer than 3 known letters yet). The session has
///                     no warm-up phase; we celebrate engagement instead.
///   * `.reviewStar` — no current focus unit (expert / no-focus session,
///                     or the day after a focus graduated). Mirrors the
///                     "complete the opening confidently" shape of
///                     `warmupStar` but uses session-correct count since
///                     there's no warm-up phase to gate against.
///
/// The other three stamps (`helloFocus`, `practicePro`, `streakStar`)
/// apply uniformly across opener types, with one carve-out: `helloFocus`
/// only makes sense when there's a focus unit to *say hello to*, so
/// `.reviewStar` sessions display only 3 stamp slots.
enum DailyStamp: String, CaseIterable, Identifiable, Codable {
    case warmupStar    // opener (normal): warm-up phase completed with ≥80% correct
    case braveStart    // opener (sparse): first correct answer in a no-warm-up session
    case reviewStar    // opener (no-focus): 5 correct review rounds
    case helloFocus    // first interaction with today's focus unit
    case practicePro   // 5 correct on focus this session (or 10 total if no focus)
    case streakStar    // 5-correct in a row at any point
    case extraPractice // parent-directed practice session completed

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "helloLetter" {
            self = .helloFocus
            return
        }
        guard let value = DailyStamp(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown DailyStamp: \(raw)")
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// True for the three mutually-exclusive opener stamps. Helpful in tests
    /// and in any UI that wants to render the opener slot specially.
    var isOpener: Bool {
        switch self {
        case .warmupStar, .braveStart, .reviewStar: return true
        case .helloFocus, .practicePro, .streakStar, .extraPractice: return false
        }
    }

    var icon: String {
        switch self {
        case .warmupStar: return "sun.max.fill"
        case .braveStart: return "sparkles"
        case .reviewStar: return "books.vertical.fill"
        case .helloFocus: return "hand.wave.fill"
        case .practicePro: return "star.fill"
        case .streakStar: return "flame.fill"
        case .extraPractice: return "target"
        }
    }

    /// Short label for tooltips and the session-end card.
    var displayName: String {
        switch self {
        case .warmupStar: return "Warm-up"
        case .braveStart: return "Brave Start"
        case .reviewStar: return "Review"
        case .helloFocus: return "Hello!"
        case .practicePro: return "Practice"
        case .streakStar: return "Streak"
        case .extraPractice: return "Extra Practice"
        }
    }
}

// MARK: - Session shape

enum SessionMode: Codable, Equatable {
    case adaptiveDaily
    case extraPractice(letter: String)

    var practiceLetter: String? {
        if case .extraPractice(let letter) = self { return letter }
        return nil
    }
}

enum DailyPracticeKind: String, Codable, Equatable {
    case introduction
    case reviewTest
}

/// Returned by `ProfileManager.previewSessionPlan` / `commitSessionStartIfNeeded`.
/// Tells the view what special UX may apply and the AdaptiveGameState what
/// shape the session should take.
struct SessionPlan: Equatable, Codable {
    /// Length of the warm-up phase in rounds. Adapts to how many letters the
    /// child knows; falls to 0 for very-early profiles to avoid empty pools.
    var warmupLength: Int

    /// True if a focus unit was just freshly introduced this session —
    /// triggers the "New letter today!" overlay.
    var introducedNewFocusLetter: Bool
    var introducedFocusTarget: FocusTarget?

    /// Day streak after this session entry was counted (≥1). The view shows
    /// "Day N!" if `dayStreakIncreased` is true.
    var dayStreakCount: Int
    var dayStreakIncreased: Bool

    var focusLetter: String?
    var focusTarget: FocusTarget?
    var primaryLayer: LearningLayer = .letters
    var activityKind: LearningActivityKind = .letterRecognition
    var focusScaffoldingLevel: Int
    var mode: SessionMode = .adaptiveDaily
    var dailyGoalTarget: Int = 25
    var dailyGoalStartCount: Int = 0
    var dailyGoalClaimedCount: Int = 0
    var dailyPracticeKind: DailyPracticeKind = .introduction
    var weeklyReviewLetters: [String] = []
    var dailySpotlightLetter: String?

    init(
        warmupLength: Int,
        introducedNewFocusLetter: Bool,
        introducedFocusTarget: FocusTarget? = nil,
        dayStreakCount: Int,
        dayStreakIncreased: Bool,
        focusLetter: String?,
        focusTarget: FocusTarget? = nil,
        primaryLayer: LearningLayer = .letters,
        activityKind: LearningActivityKind = .letterRecognition,
        focusScaffoldingLevel: Int,
        mode: SessionMode = .adaptiveDaily,
        dailyGoalTarget: Int = 25,
        dailyGoalStartCount: Int = 0,
        dailyGoalClaimedCount: Int = 0,
        dailyPracticeKind: DailyPracticeKind = .introduction,
        weeklyReviewLetters: [String] = [],
        dailySpotlightLetter: String? = nil
    ) {
        self.warmupLength = warmupLength
        self.introducedNewFocusLetter = introducedNewFocusLetter
        self.introducedFocusTarget = introducedFocusTarget
        self.dayStreakCount = dayStreakCount
        self.dayStreakIncreased = dayStreakIncreased
        self.focusLetter = focusLetter
        self.focusTarget = focusTarget
        self.primaryLayer = primaryLayer
        self.activityKind = activityKind
        self.focusScaffoldingLevel = focusScaffoldingLevel
        self.mode = mode
        self.dailyGoalTarget = dailyGoalTarget
        self.dailyGoalStartCount = dailyGoalStartCount
        self.dailyGoalClaimedCount = dailyGoalClaimedCount
        self.dailyPracticeKind = dailyPracticeKind
        self.weeklyReviewLetters = weeklyReviewLetters
        self.dailySpotlightLetter = dailySpotlightLetter
    }

    private enum CodingKeys: String, CodingKey {
        case warmupLength, introducedNewFocusLetter, introducedFocusTarget, dayStreakCount, dayStreakIncreased
        case focusLetter, focusTarget, primaryLayer, activityKind, focusScaffoldingLevel, mode
        case dailyGoalTarget, dailyGoalStartCount, dailyGoalClaimedCount
        case dailyPracticeKind, weeklyReviewLetters, dailySpotlightLetter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        warmupLength = try c.decode(Int.self, forKey: .warmupLength)
        introducedNewFocusLetter = try c.decode(Bool.self, forKey: .introducedNewFocusLetter)
        introducedFocusTarget = try c.decodeIfPresent(FocusTarget.self, forKey: .introducedFocusTarget)
        dayStreakCount = try c.decode(Int.self, forKey: .dayStreakCount)
        dayStreakIncreased = try c.decode(Bool.self, forKey: .dayStreakIncreased)
        focusLetter = try c.decodeIfPresent(String.self, forKey: .focusLetter)
        focusTarget = try c.decodeIfPresent(FocusTarget.self, forKey: .focusTarget)
        primaryLayer = try c.decodeIfPresent(LearningLayer.self, forKey: .primaryLayer) ?? .letters
        activityKind = try c.decodeIfPresent(LearningActivityKind.self, forKey: .activityKind) ?? .letterRecognition
        focusScaffoldingLevel = try c.decode(Int.self, forKey: .focusScaffoldingLevel)
        mode = try c.decodeIfPresent(SessionMode.self, forKey: .mode) ?? .adaptiveDaily
        dailyGoalTarget = try c.decodeIfPresent(Int.self, forKey: .dailyGoalTarget) ?? 25
        dailyGoalStartCount = try c.decodeIfPresent(Int.self, forKey: .dailyGoalStartCount) ?? 0
        dailyGoalClaimedCount = try c.decodeIfPresent(Int.self, forKey: .dailyGoalClaimedCount) ?? 0
        dailyPracticeKind = try c.decodeIfPresent(DailyPracticeKind.self, forKey: .dailyPracticeKind) ?? .introduction
        weeklyReviewLetters = try c.decodeIfPresent([String].self, forKey: .weeklyReviewLetters) ?? []
        dailySpotlightLetter = try c.decodeIfPresent(String.self, forKey: .dailySpotlightLetter)
    }
}

// MARK: - Round phase

enum RoundPhase: String, Codable, Equatable {
    case warmup
    case drill
    case plainReview
    case rescue       // a brief "ask same target with easier distractors" recovery
    case contrast     // explicit confused-pair discrimination mini-round
    case maintenance  // expert no-focus mixed review
    case syllableCalibration
    case syllableRecognition
    case syllableBlending
    case syllableSegmenting
    case wordReading
    case wordBuilding
}

// MARK: - Focus teaching mode

/// Session-local teaching strategy for the current round generator. This keeps
/// scaffolding, distractor policy, focus frequency, remediation, contrast, and
/// maintenance behavior behind one resolved mode instead of scattering boolean
/// checks across the round builders.
enum FocusTeachingMode: String, Codable, Equatable, CaseIterable {
    /// Standard focus practice after the first scaffolded days.
    case normal
    /// Early focus practice: max easy-elimination scaffolding.
    case scaffolded
    /// Stuck-focus support: max scaffolding, lower focus-target pressure.
    case remediation
    /// Explicit letter-pair discrimination round.
    case contrast
    /// Expert no-focus mixed review.
    case maintenance
}

// MARK: - Answer outcome

/// Side-effects triggered by a single answer, in priority-render order. The
/// view consumes these and chains animations / overlays accordingly.
struct AnswerOutcome: Equatable {
    var wasCorrect: Bool
    var correctLetter: String
    var heartsRemaining: Int
    var streakMilestone: StreakMilestone?
    var stampEarned: DailyStamp?
    var focusGraduated: String?
    var leveledUp: AlphabetLevel?
    var sessionEndReason: SessionEndReason?
}

enum StreakMilestone: Equatable {
    case five
    case ten
}

enum SessionEndReason: String, Codable {
    case goalComplete   // child tapped "I'm done!" after all stamps earned
    case homeTapped     // parent tapped home
    case outOfHearts    // miss budget exhausted
    case tiredSignal    // legacy checkpoint value; adaptive daily no longer auto-ends for mistakes
    case practiceComplete
}

// MARK: - Session summary

/// Snapshot the view passes to `ProfileManager.endSession` and to the
/// `SessionEndView` celebration screen. Pure value type, no logic.
struct SessionSummary: Equatable {
    var profileId: UUID
    var endReason: SessionEndReason
    var stampsEarned: Set<DailyStamp>

    /// Ordered list of stamps that *could* have been earned this session.
    /// Always contains exactly one opener (`warmupStar` / `braveStart` /
    /// `reviewStar`) and may omit `helloFocus` for no-focus sessions, so
    /// the session-end view should iterate this list rather than
    /// `DailyStamp.allCases`.
    var applicableStamps: [DailyStamp]

    var heartsRemaining: Int
    var bestSessionStreak: Int
    var roundsAnswered: Int
    var roundsCorrect: Int
    var focusGraduatedThisSession: String?
    var dayStreakCount: Int
    var bestDailyStreak: Int
    var letterMasteredCount: Int
    var totalLetters: Int
    var nextLevelThreshold: Int
    var currentFocusLetter: String?
    var nextFocusPreview: String?
    var didLevelUp: Bool
    var newLevel: AlphabetLevel

    /// Number of distractor slots that had to be filled with letters the
    /// child has never been formally introduced to (last-resort tier of the
    /// distractor selector). Should be 0 in normal play after calibration —
    /// any positive value here means we silently violated the "one new
    /// letter per day" principle and is worth surfacing for debugging.
    var unintroducedExposures: Int
}

// MARK: - Distractor tiers

/// Deterministic priority order the distractor selector walks when filling
/// the option slots for a round. The tiers exist so sparse profiles (just
/// finished calibration, only 1-2 known letters) have a fully specified
/// fallback path that never silently dips into letters the child hasn't met.
///
/// Pedagogical intent of the ordering:
///   1. `.known` — most informative wrong answer the child can confidently
///      reject. The base case for any well-played profile.
///   2. `.caseVariant` — automatic high-level lowercase/uppercase mixing
///      for letters the child already knows in the other case.
///   3. `.attempted` — letters with target attempts but not yet `isKnown`.
///      Some recognition signal exists, so they're plausible distractors.
///   4. `.calibrationPool` — curated pedagogical "early letters" set. Used
///      before falling through to incidental introductions.
///   5. `.otherIntroduced` — anything else the child has seen at least once
///      (e.g. a focus letter currently being drilled, a letter that's only
///      been a distractor so far).
///   6. `.visualOnly` — non-letter lookalikes, allowed only at high levels.
///   7. `.unintroduced` — last resort. Surfaces a letter the child has
///      never met. Tracked as a "leak" because reaching here means the
///      algorithm couldn't honor the "one new letter per day" promise.
private enum DistractorTier: Int, CaseIterable {
    case known
    case caseVariant
    case attempted
    case calibrationPool
    case otherIntroduced
    case visualOnly
    case unintroduced
}

// MARK: - AdaptiveGameState

@MainActor
final class AdaptiveGameState: ObservableObject {
    // MARK: Published state for the view
    //
    // Everything in this section is **session-local**: it lives only
    // inside one `GameView` lifetime and is reset to the defaults below
    // every time the view (and therefore this `@StateObject`) is
    // re-instantiated. That's the multi-session-same-day contract: hearts,
    // stamps, round counters, and per-session streaks all start fresh on
    // every "Play again" tap. Durable counterparts (`bestSessionStreak`,
    // `everMasteredLetters`, `dailyStreakCount`, `bestDailyStreak`,
    // `letterStats`) live on `Profile` and are mutated through
    // `ProfileManager` so they survive across sessions.

    @Published var targetLetter: String = ""
    @Published var displayedLetters: [String] = []
    @Published var currentActivityKind: LearningActivityKind = .letterRecognition
    @Published var currentRound: LearningRound?
    @Published var currentStreak: Int = 0
    @Published var sessionBestStreak: Int = 0
    @Published var heartsRemaining: Int = 5
    @Published var stampsEarned: Set<DailyStamp> = []
    @Published var phase: RoundPhase = .warmup
    @Published var roundsThisSession: Int = 0
    @Published var roundsCorrect: Int = 0
    @Published var focusGraduatedThisSession: String?
    @Published var lastOutcome: AnswerOutcome?
    @Published var sessionEnded: SessionEndReason?
    @Published var didLevelUpThisSession: Bool = false

    // MARK: Config

    let language: GameLanguage
    let plan: SessionPlan
    private(set) var profileId: UUID
    private let fallbackProfile: Profile
    private weak var profileManager: ProfileManager?

    /// The full list of stamp slots that *can* be filled in this session,
    /// in display order. Decided once at `init` from the (immutable) plan
    /// shape — see `Self.computeApplicableStamps(for:)` for the rules.
    /// The view iterates this rather than `DailyStamp.allCases`, so the
    /// "Today's focus card" UI never shows a slot that isn't actually achievable
    /// (e.g. `helloFocus` in a no-focus session).
    let applicableStamps: [DailyStamp]

    /// Convenience: the opener stamp for this session (always exactly one
    /// of `warmupStar` / `braveStart` / `reviewStar`).
    var openerStamp: DailyStamp { applicableStamps[0] }

    var dailyGoalTotalCount: Int {
        guard plan.dailyGoalTarget > 0 else { return 0 }
        // Ordinary daily practice only credits correct answers, so a wrong tap
        // (deliberate or not) earns no progress toward the Winner button.
        // `roundsThisSession` still drives warmup length, focus-appearance
        // deadlines, and round indexing, so it counts every answered round;
        // the ordinary daily goal instead tracks `roundsCorrect`.
        //
        // The weekly review/test is the deliberate exception: it is a
        // fixed-length retention audit, so every answered round counts toward
        // its goal whether right or wrong — completion is about *coverage*, not
        // a correct-answer quota.
        let progress = plan.dailyPracticeKind == .reviewTest ? roundsThisSession : roundsCorrect
        return max(0, plan.dailyGoalStartCount + progress)
    }

    var dailyGoalCount: Int {
        guard plan.dailyGoalTarget > 0 else { return 0 }
        return min(plan.dailyGoalTarget, dailyGoalTotalCount)
    }

    var dailyGoalExtraCount: Int {
        guard plan.dailyGoalTarget > 0 else { return 0 }
        return max(0, dailyGoalTotalCount - plan.dailyGoalTarget)
    }

    var dailyGoalDisplayText: String {
        guard plan.dailyGoalTarget > 0 else { return "0 / 0" }
        if dailyGoalExtraCount > 0 || plan.dailyGoalClaimedCount >= plan.dailyGoalTarget {
            return "+\(dailyGoalExtraCount)"
        }
        return "\(dailyGoalCount) / \(plan.dailyGoalTarget)"
    }

    var dailyGoalAccessibilityText: String {
        guard plan.dailyGoalTarget > 0 else { return "No daily goal" }
        if dailyGoalExtraCount > 0 || plan.dailyGoalClaimedCount >= plan.dailyGoalTarget {
            return "\(dailyGoalExtraCount) extra after daily goal"
        }
        return "\(dailyGoalCount) of \(plan.dailyGoalTarget)"
    }

    var dailyGoalProgress: Double {
        guard plan.dailyGoalTarget > 0 else { return 0 }
        let claimed = max(0, plan.dailyGoalClaimedCount)
        if claimed >= plan.dailyGoalTarget {
            let countSinceClaim = max(0, dailyGoalTotalCount - claimed)
            return min(1.0, Double(countSinceClaim) / Double(plan.dailyGoalTarget))
        }
        return min(1.0, Double(dailyGoalCount) / Double(plan.dailyGoalTarget))
    }

    var claimableDailyGoalMilestone: Int? {
        guard case .adaptiveDaily = plan.mode,
              plan.activityKind != .syllableCalibration,
              plan.dailyGoalTarget > 0 else {
            return nil
        }
        let completedMilestone = (dailyGoalTotalCount / plan.dailyGoalTarget) * plan.dailyGoalTarget
        let claimed = max(0, plan.dailyGoalClaimedCount)
        return completedMilestone > claimed ? completedMilestone : nil
    }

    private var sessionFocusKey: String? {
        plan.dailySpotlightLetter ?? plan.focusTarget?.rawKey ?? plan.focusLetter
    }

    private func activeDrillFocus(for profile: Profile) -> String? {
        guard plan.dailyPracticeKind != .reviewTest else { return nil }
        if teachingMode == .remediation {
            return profile.currentFocusLetter
        }
        return plan.dailySpotlightLetter ?? profile.currentFocusLetter
    }

    // MARK: Internal session state

    private var previousTarget: String?
    private var recentTargetLetters: [String] = []
    private let recentTargetMemoryLimit = 3

    /// Weighted "good encounters" accumulator that drives the `practicePro`
    /// stamp in focus-letter sessions. See the award block in `processAnswer`
    /// for the per-round contributions. Threshold is `practiceProThreshold`.
    /// Not used in no-focus sessions (those gate `practicePro` on raw correct
    /// review count instead).
    private var practiceProgress: Double = 0.0

    /// Threshold the `practiceProgress` accumulator must reach for the
    /// `practicePro` stamp in focus sessions. Same nominal target as the
    /// previous "5 correct focus answers" rule, just reachable via more
    /// paths so a struggling-but-engaged child isn't locked out.
    private let practiceProThreshold: Double = 5.0

    private var totalCorrectThisSession: Int = 0
    private var warmupCorrectCount: Int = 0
    private var warmupAttemptCount: Int = 0
    private var consecutiveWarmupMisses: Int = 0
    private var helloFocusAwarded: Bool = false
    private var seenWarmupLetters: Set<String> = []

    // MARK: Phase 2a — two-tier rescue queue (#1)
    //
    // The previous single-bool / single-letter pair (`rescueQueued`,
    // `rescueTarget`) only supported one outstanding rescue: any new
    // wrong answer overwrote the pending one and the child never got a
    // second-chance retry on the original mistake. The two-tier queue
    // fixes that — see the structured comment on `RescueItem` for the
    // full lifecycle.

    /// One scheduled rescue retry. The queue (FIFO, capped at
    /// `Self.rescueQueueCap`) holds these in arrival order; on each
    /// `setupNewRound()` we pop the oldest *due* item (`dueAfterRounds
    /// <= 0`), build a rescue round around it, and then advance all
    /// remaining items by one round.
    private struct RescueItem: Equatable, Codable {
        /// Storage-key form of the letter to re-ask. Always equals the
        /// original wrong-target round's `targetLetter`.
        let letterKey: String
        /// Rounds-from-now this rescue should fire. `0` = the very next
        /// round (immediate easy retry); a positive value lets a few
        /// other rounds happen first (delayed mid retry).
        var dueAfterRounds: Int
        /// Easy (top-confidence distractors) vs. mid (any known letters,
        /// `.avoid` confusion policy). The lifecycle below explains
        /// when each is enqueued.
        let difficulty: RescueDifficulty
    }

    /// Pending rescue retries in arrival order. Capped at
    /// `Self.rescueQueueCap`; further enqueues drop the *oldest* item
    /// (`removeFirst`) so the queue tracks the most recent struggles
    /// rather than letting stale rescues languish forever.
    private var rescueQueue: [RescueItem] = []

    /// `true` while the *currently displayed* round was generated as a
    /// rescue. Set inside `setupNewRound()` whenever a queued item
    /// fires; cleared on the next non-rescue round build. The
    /// underlying `phase` field stays at the session's main phase
    /// (warmup/drill/plainReview) — rescue is treated as a temporary
    /// insertion rather than a phase change, so phase-transition rules
    /// in `setupNewRound()` don't get derailed.
    @Published private(set) var currentRoundIsRescue: Bool = false

    /// Difficulty tier of the rescue round currently displayed; `nil`
    /// when `currentRoundIsRescue == false`. Plumbed into the persisted
    /// `RoundEvent.rescueDifficulty` so the parent dashboard can
    /// distinguish "we re-asked with the easiest possible distractors"
    /// from "we re-asked with a harder pool a few rounds later."
    private(set) var currentRescueDifficulty: RescueDifficulty?

    /// Temporary insertion rounds (rescue/contrast) do not permanently move
    /// the main `phase` state machine, but their `RoundEvent.phase` should
    /// still say what actually happened. This override is set by the round
    /// builder for those insertions and consumed in `processAnswer`.
    private var currentRoundPhaseOverride: RoundPhase?

    /// FIFO cap. Three is enough to recover from a brief slump
    /// (one easy + one mid for two distinct letters) without letting
    /// the queue grow into a backlog the child can't realistically
    /// drain in a session.
    private static let rescueQueueCap: Int = 3

    /// Delay range (rounds) for a mid-difficulty retry queued after a
    /// failed easy rescue. Two-to-three rounds gives enough breathing
    /// room that the child has time to settle before the same letter
    /// reappears, but stays close enough that the connection to the
    /// original confusion is still meaningful.
    private static let midRescueDelayRange: ClosedRange<Int> = 2...3

    /// Advanced/expert rounds should often include an explicit similar-shape
    /// option, but not every round needs the same structure.
    private static let similarDistractorSeedProbability: Double = 0.8

    // MARK: Phase 2c — session difficulty governor (#9)

    /// Live difficulty mode for this session. Starts normal, trips into
    /// `.easierUntilStreak` after clear struggle signals, then returns to
    /// `.normal` after two consecutive correct answers. Stamped into every
    /// `RoundEvent` so the dashboard can explain "we made this easier here."
    @Published private(set) var liveDifficulty: LiveDifficulty = .normal

    /// Rolling correctness window for the "3 of last 4 wrong" trip rule.
    private var recentRoundCorrectness: [Bool] = []

    /// Recovery counter while eased. Two consecutive correct answers walk the
    /// governor back by one step (`governorEaseSteps -= 1`); if that drops to
    /// zero, `liveDifficulty` returns to `.normal`.
    private var governorCorrectStreak: Int = 0

    /// Number of governor-driven grid downshifts currently applied. 0 means
    /// the base grid is shown; 1 drops one tier (8→6, 6→4); 2 drops two
    /// tiers (8→4). Capped at 2 because 4 is the practical floor. Walks the
    /// child *into* relief one trip at a time so a struggling 8-tier session
    /// can reach the same floor a 6-tier session does, and walks them back
    /// out one streak at a time so recovery isn't an abrupt 4 → 8 snap.
    private var governorEaseSteps: Int = 0

    /// Focus-target accuracy within this session. Used only for the governor
    /// trip rule; durable learning stats remain in `ProfileManager`.
    private var focusTargetAttemptsThisSession: Int = 0
    private var focusTargetCorrectThisSession: Int = 0

    // MARK: Phase 2d — teaching mode (addition D)

    /// Current round-generator strategy. Updated at the top of
    /// `setupNewRound()` from the latest profile state.
    @Published private(set) var teachingMode: FocusTeachingMode = .normal

    /// Scaffolding actually used by the generator. Unlike
    /// `Profile.focusScaffoldingLevel`, this is derived from
    /// `FocusTeachingMode`, so remediation can force max scaffolding (3)
    /// without pretending the focus is on day 1.
    private(set) var effectiveScaffoldingLevel: Int = 0

    /// Hysteresis state for stuck-focus remediation. Once a focus enters
    /// remediation (< 50% recent accuracy after 5+ active days), it stays
    /// there until recent accuracy reaches 60% so the mode does not flicker
    /// around the threshold.
    private var remediationFocusLetter: String?

    /// Prevents pre-seeding the same focus rescue queue repeatedly every
    /// time `setupNewRound()` resolves `.remediation`.
    private var preseededRemediationFocusLetter: String?

    /// UI hook for Phase 4a: remediation can render the focus card larger /
    /// more obvious without the view needing to re-derive the stuck-focus rule.
    var shouldUseOversizedFocusCard: Bool {
        teachingMode == .remediation
    }

    /// Running count of distractor slots filled from the `.unintroduced` tier
    /// during this session. Should be 0 in well-fed play; positive values
    /// mean the algorithm fell through every preferred tier and exposed a
    /// letter the child has never been formally introduced to. Surfaced via
    /// `SessionSummary.unintroducedExposures` for diagnostics.
    private(set) var unintroducedExposuresThisSession: Int = 0

    /// Intentional future-letter cameos recorded in this session. Unlike
    /// `unintroducedExposuresThisSession`, these are planned low-pressure
    /// distractor exposures and are capped per profile per local day.
    private(set) var cameoExposuresThisSession: Int = 0

    /// The cameo letter, if any, currently displayed as a distractor. This is
    /// reserved when the round is built but only counted if the child answers
    /// and the exposure is actually recorded.
    private var currentRoundCameoLetter: String?

    /// Difficulty band frozen at session start. Unlike `alphabetLevel`, this can
    /// sit lower after slips; unlike live profile data, it won't wobble
    /// mid-session while position history and option counts are in flight.
    private var instructionalBand: AlphabetLevel = .novice

    /// Base letter-grid size frozen at session start. This follows the current
    /// known-letter thresholds, while `instructionalBand` continues to gate
    /// harder distractor and case behavior.
    private var frozenLetterOptionsPerRound: Int = 4

    /// Audio-filtered word pool frozen for word-reading sessions. Every word
    /// option in the session must come from this pool.
    private var sessionPlayableWords: [WordUnit] = []

    // MARK: Phase 1b — round-level signal capture
    //
    // These fields populate on the wire to `ProfileManager.recordAnswer`
    // (Phase 1c) and the per-round `RoundEvent` (Phase 0e). All session-
    // local; reset implicitly on the next `GameView` lifetime.

    /// Timestamp the current round's grid was shown to the child. Set by
    /// `markRoundStarted()` immediately after `setupNewRound()` returns;
    /// read by `processAnswer` to compute `responseTime` for the round.
    /// `nil` when no round is currently in flight (e.g., between session
    /// end and dismiss).
    private var roundStartedAt: Date?

    /// How many times the child re-tapped the speaker / replay button for
    /// the *current* round. Bumped by `didReplayPrompt()` (Phase 1d wires
    /// the speaker button to call this). Read once in `processAnswer` and
    /// then reset to 0 by `setupNewRound()`.
    private var roundReplayCount: Int = 0

    /// Pedagogical intent for the current round. Set by `setupNewRound()`
    /// based on the phase / target / focus shape. Plumbed into the
    /// `RoundEvent` log (Phase 0e) so the parent dashboard can show
    /// "we re-asked this letter because they got it wrong last round"
    /// rather than just "round N." Phase 2/3 round generators (rescue,
    /// contrast, maintenance) override the default to their specific
    /// intent.
    private(set) var currentRoundIntent: RoundIntent = .warmupConfidence
    private var currentPlainReviewIntentOverride: RoundIntent?

    /// Machine-readable explanation for the current generated round. Persisted
    /// into `RoundEvent` for debugging and simulation assertions.
    private(set) var currentRoundPlanReason: RoundPlanReason?

    /// Set of target storage-keys the child has missed *twice* this
    /// session. Phase 4a's "show-me reveal" (correct tile pulses + audio)
    /// fires the second time the same letter is missed; tracking the
    /// set here means a third miss on the same letter still triggers
    /// the reveal (the set has already remembered).
    private(set) var secondMissedLetters: Set<String> = []

    /// Working set of letters that have been missed *once* in this
    /// session — counterpart to `secondMissedLetters`. Used to detect
    /// the second-miss transition without retaining a full miss log.
    private var firstMissedLetters: Set<String> = []

    /// Sparse-data impulse cutoff, in seconds. This and the adaptive
    /// multiplier/clamps below are product-judgment heuristics, not values
    /// measured on real children.
    nonisolated static let impulseThreshold: TimeInterval = 0.5
    private static let adaptiveImpulseMedianMultiplier: TimeInterval = 0.35
    private static let minAdaptiveImpulseThreshold: TimeInterval = 0.35
    private static let maxAdaptiveImpulseThreshold: TimeInterval = 0.9

    /// Sub-`adaptiveImpulseThreshold` response time on a wrong tap = the child
    /// tapped before they could plausibly have read the prompt.
    /// Phase 1c (R6 fix) treats these as not-counted for learning,
    /// and Phase 1d (heart split) preserves the heart on this case
    /// so an accidental tap doesn't drain the budget.

    /// Most recent classification of a wrong tap. Read by `processAnswer`
    /// callers (Phase 1d's heart-loss decision) and stamped into the
    /// outgoing `RoundEvent`. `nil` for correct answers.
    private(set) var lastMistakeType: MistakeType?

    /// Most recent response time for the round just answered. Read by
    /// `recordAnswer` to update the rolling response-time window
    /// (Phase 1c). `nil` when no round-start timestamp was captured
    /// (e.g., calibration-flow rounds, which don't go through
    /// `markRoundStarted`).
    private(set) var lastResponseTime: TimeInterval?

    // MARK: Correct-answer position tracking
    //
    // A pure `.shuffled()` placement of the correct letter on an option
    // grid will, over a session, produce visible streaks: same slot 3+
    // times in a row, corner positions never used, focus letter always in
    // the bottom-right, etc. Toddlers latch onto positional patterns
    // long before they learn the letter shapes, so we have to pick the
    // correct-answer slot deliberately. See `chooseCorrectPosition`.

    /// Last few correct-answer positions in this session. Used to enforce
    /// the "no same position more than twice in a row" rule. We only need
    /// the last two entries for that check, so the array is capped at 2.
    private var recentCorrectPositions: [Int] = []

    /// Subset of `recentCorrectPositions` covering only rounds where the
    /// target WAS the focus letter. We rotate the slot used for fresh-focus
    /// targets so a newly introduced letter doesn't always land in the
    /// same place. Capped at the most-recent entry.
    private var recentFocusCorrectPositions: [Int] = []

    /// Per-position correct-answer count for this session, indexed by slot
    /// 0..<optionsPerRound. Used to keep the distribution roughly even by
    /// preferring the least-used slot(s) among the legal candidates.
    private var sessionCorrectPositionCounts: [Int] = []

    /// Rounds in the warm-up phase before transitioning to drill / plain review.
    private var warmupLength: Int { plan.warmupLength }

    /// 1-based round index by which the focus letter MUST have appeared as a
    /// drill target. If random target selection (which picks focus only ~50%
    /// of the time) hasn't surfaced it by then, `buildDrillRound` forces it.
    ///
    /// Why a deadline at all? `helloFocus` only fires when the focus unit
    /// is the *target* of a round (the audio asks for it). With a 5-heart
    /// budget and unlucky rolls, a child could exhaust hearts on lower-
    /// confidence known letters before ever being asked to find their new
    /// focus unit — and then end the session with the helloFocus slot
    /// permanently unfilled.
    ///
    /// `warmupLength + 2` gives one drill round of natural random selection
    /// before we step in. Concretely:
    ///   * warmupLength = 5 → deadline = 7. Drill rounds are #6 and #7;
    ///     #6 is random, #7 forces focus if it hasn't appeared.
    ///   * warmupLength = 0 (sparse profile) → deadline = 2. Drill rounds
    ///     start at #1; #1 is random, #2 forces.
    private var firstFocusAppearanceDeadline: Int { warmupLength + 2 }

    /// Answer choices scale with the frozen known-letter grid. Reading
    /// activities stay at four choices while those early curricula are
    /// intentionally built around a 1+3 option shape.
    ///
    /// While the difficulty governor is eased, each accumulated
    /// `governorEaseSteps` drops the grid by one tier (2 options), floored
    /// at 4. A struggling 8-tier child therefore reaches 4 after two trips
    /// (8 → 6 → 4) — the same floor a 6-tier child reaches after one — and
    /// recovers symmetrically as the streaks chip the step count back down.
    private var optionsPerRound: Int {
        let base: Int
        if plan.primaryLayer == .syllables || plan.primaryLayer == .words {
            base = 4
        } else {
            base = frozenLetterOptionsPerRound
        }
        guard liveDifficulty == .easierUntilStreak, governorEaseSteps > 0 else { return base }
        let stepped = base - 2 * governorEaseSteps
        return max(4, stepped)
    }

    // MARK: Init

    init(
        profile: Profile,
        plan: SessionPlan,
        profileManager: ProfileManager,
        restoredSnapshot: GameEngineSnapshot? = nil
    ) {
        self.profileId = profile.id
        self.fallbackProfile = profile
        self.language = profile.language
        self.plan = plan
        self.profileManager = profileManager
        self.applicableStamps = AdaptiveGameState.computeApplicableStamps(for: plan)
        let learningSnapshot = profile.snapshot
        let canApplySnapshot = restoredSnapshot.map { $0.profileId == profile.id && $0.plan == plan } ?? false
        self.instructionalBand = canApplySnapshot
            ? (restoredSnapshot?.instructionalBand ?? learningSnapshot.instructionalBand)
            : learningSnapshot.instructionalBand
        self.frozenLetterOptionsPerRound = canApplySnapshot
            ? (restoredSnapshot?.letterOptionsPerRound ?? profile.letterOptionsPerRound)
            : profile.letterOptionsPerRound
        // Persist the freshly-frozen grid size so the next session can apply
        // ±2 hysteresis around it. Idempotent inside ProfileManager — only
        // writes when the value actually changes.
        profileManager.recordSessionFrozenGrid(
            profileId: profile.id,
            value: self.frozenLetterOptionsPerRound
        )
        self.sessionPlayableWords = []
        if canApplySnapshot, let restoredPlayableWords = restoredSnapshot?.sessionPlayableWords {
            self.sessionPlayableWords = restoredPlayableWords
        }
        if self.sessionPlayableWords.isEmpty, plan.primaryLayer == .words {
            self.sessionPlayableWords = WordCurriculum.playableWords(for: profile, audio: AudioService.shared)
        }
        self.sessionPlayableWords = plan.primaryLayer == .words
            ? self.sessionPlayableWords
            : []
        self.sessionCorrectPositionCounts = Array(repeating: 0, count: optionsPerRound)
        if let restoredSnapshot,
           restoredSnapshot.profileId == profile.id,
           restoredSnapshot.plan == plan {
            apply(restoredSnapshot)
            if restoredSnapshot.advanceToNextRoundOnRestore, sessionEnded == nil {
                setupNewRound()
            }
            return
        }
        currentActivityKind = plan.activityKind
        if plan.activityKind == .syllableCalibration {
            if plan.warmupLength != 0 {
                assertionFailure("Reading-layer plans must not promise warm-up until the engine supports it.")
            }
            self.phase = .syllableCalibration
        } else if plan.primaryLayer == .syllables {
            if plan.warmupLength != 0 {
                assertionFailure("Reading-layer plans must not promise warm-up until the engine supports it.")
            }
            self.phase = plan.activityKind == .syllableBlending ? .syllableBlending : .syllableRecognition
        } else if plan.primaryLayer == .words {
            if plan.warmupLength != 0 {
                assertionFailure("Reading-layer plans must not promise warm-up until the engine supports it.")
            }
            self.phase = plan.activityKind == .wordBuilding ? .wordBuilding : .wordReading
        } else {
            // If the child has fewer than ~3 known letters, skip warm-up entirely
            // so we don't try to draw distractors from an empty pool.
            let knownCount = profile.knownLetters.count
            if knownCount < 3, plan.warmupLength > 0 {
                assertionFailure("Planner promised warm-up with fewer than 3 known letters.")
            }
            if plan.warmupLength == 0 || knownCount < 3 {
                self.phase = activeDrillFocus(for: profile) == nil
                    ? (plan.dailyPracticeKind == .reviewTest || profile.alphabetLevel != .expert ? .plainReview : .maintenance)
                    : .drill
            } else {
                self.phase = .warmup
            }
        }
        setupNewRound()
    }

    /// Picks the opener stamp for the session and assembles the full slot
    /// list. Pure function of the plan so it can be reasoned about (and
    /// unit-tested) without touching `AdaptiveGameState` instance state.
    ///
    /// Precedence:
    ///   1. `plan.focusLetter == nil`            → `.reviewStar`
    ///      (no focus to greet, so this is a pure-review session — even if
    ///      `warmupLength > 0`, there's nothing to "warm up *for*")
    ///   2. `plan.warmupLength > 0`              → `.warmupStar`
    ///   3. otherwise (`warmupLength == 0`,
    ///      sparse profile with focus active)    → `.braveStart`
    ///
    /// `helloFocus` is included only when there's a focus unit; in
    /// `.reviewStar` sessions the slot is dropped (3 stamps total, not 4).
    static func computeApplicableStamps(for plan: SessionPlan) -> [DailyStamp] {
        if case .extraPractice = plan.mode {
            return [.extraPractice, .streakStar]
        }
        let opener: DailyStamp
        if plan.activityKind == .syllableCalibration {
            opener = .braveStart
        } else if plan.focusTarget == nil && plan.focusLetter == nil && plan.dailySpotlightLetter == nil {
            opener = .reviewStar
        } else if plan.warmupLength > 0 {
            opener = .warmupStar
        } else {
            opener = .braveStart
        }
        var stamps: [DailyStamp] = [opener]
        if plan.focusTarget != nil || plan.focusLetter != nil || plan.dailySpotlightLetter != nil {
            stamps.append(.helloFocus)
        }
        stamps.append(.practicePro)
        stamps.append(.streakStar)
        return stamps
    }

    func captureSnapshot(advanceToNextRoundOnRestore: Bool = false) -> GameEngineSnapshot {
        GameEngineSnapshot(
            profileId: profileId,
            plan: plan,
            savedAt: Date(),
            targetLetter: targetLetter,
            displayedLetters: displayedLetters,
            currentActivityKind: currentActivityKind,
            currentRound: currentRound,
            currentStreak: currentStreak,
            sessionBestStreak: sessionBestStreak,
            heartsRemaining: heartsRemaining,
            stampsEarned: stampsEarned,
            phase: phase,
            roundsThisSession: roundsThisSession,
            roundsCorrect: roundsCorrect,
            focusGraduatedThisSession: focusGraduatedThisSession,
            sessionEnded: sessionEnded,
            didLevelUpThisSession: didLevelUpThisSession,
            previousTarget: previousTarget,
            practiceProgress: practiceProgress,
            totalCorrectThisSession: totalCorrectThisSession,
            warmupCorrectCount: warmupCorrectCount,
            warmupAttemptCount: warmupAttemptCount,
            consecutiveWarmupMisses: consecutiveWarmupMisses,
            helloFocusAwarded: helloFocusAwarded,
            seenWarmupLetters: seenWarmupLetters,
            rescueQueue: rescueQueue.map {
                RescueItemSnapshot(
                    letterKey: $0.letterKey,
                    dueAfterRounds: $0.dueAfterRounds,
                    difficulty: $0.difficulty
                )
            },
            currentRoundIsRescue: currentRoundIsRescue,
            currentRescueDifficulty: currentRescueDifficulty,
            currentRoundPhaseOverride: currentRoundPhaseOverride,
            instructionalBand: instructionalBand,
            letterOptionsPerRound: frozenLetterOptionsPerRound,
            sessionPlayableWords: sessionPlayableWords,
            liveDifficulty: liveDifficulty,
            recentRoundCorrectness: recentRoundCorrectness,
            governorCorrectStreak: governorCorrectStreak,
            governorEaseSteps: governorEaseSteps,
            focusTargetAttemptsThisSession: focusTargetAttemptsThisSession,
            focusTargetCorrectThisSession: focusTargetCorrectThisSession,
            teachingMode: teachingMode,
            effectiveScaffoldingLevel: effectiveScaffoldingLevel,
            remediationFocusLetter: remediationFocusLetter,
            preseededRemediationFocusLetter: preseededRemediationFocusLetter,
            unintroducedExposuresThisSession: unintroducedExposuresThisSession,
            cameoExposuresThisSession: cameoExposuresThisSession,
            currentRoundCameoLetter: currentRoundCameoLetter,
            roundStartedAt: roundStartedAt,
            roundReplayCount: roundReplayCount,
            currentRoundIntent: currentRoundIntent,
            currentRoundPlanReason: currentRoundPlanReason,
            secondMissedLetters: secondMissedLetters,
            firstMissedLetters: firstMissedLetters,
            lastMistakeType: lastMistakeType,
            lastResponseTime: lastResponseTime,
            recentCorrectPositions: recentCorrectPositions,
            recentFocusCorrectPositions: recentFocusCorrectPositions,
            sessionCorrectPositionCounts: sessionCorrectPositionCounts,
            advanceToNextRoundOnRestore: advanceToNextRoundOnRestore
        )
    }

    private func apply(_ snapshot: GameEngineSnapshot) {
        targetLetter = snapshot.targetLetter
        displayedLetters = snapshot.displayedLetters
        currentActivityKind = snapshot.currentActivityKind ?? plan.activityKind
        currentRound = snapshot.currentRound
        currentStreak = snapshot.currentStreak
        sessionBestStreak = snapshot.sessionBestStreak
        heartsRemaining = snapshot.heartsRemaining
        stampsEarned = snapshot.stampsEarned
        phase = snapshot.phase
        roundsThisSession = snapshot.roundsThisSession
        roundsCorrect = snapshot.roundsCorrect
        focusGraduatedThisSession = snapshot.focusGraduatedThisSession
        if snapshot.sessionEnded == .tiredSignal,
           case .adaptiveDaily = plan.mode {
            sessionEnded = snapshot.heartsRemaining <= 0 ? .outOfHearts : nil
        } else {
            sessionEnded = snapshot.sessionEnded
        }
        didLevelUpThisSession = snapshot.didLevelUpThisSession
        previousTarget = snapshot.previousTarget
        practiceProgress = snapshot.practiceProgress
        totalCorrectThisSession = snapshot.totalCorrectThisSession
        warmupCorrectCount = snapshot.warmupCorrectCount
        warmupAttemptCount = snapshot.warmupAttemptCount
        consecutiveWarmupMisses = snapshot.consecutiveWarmupMisses
        helloFocusAwarded = snapshot.helloFocusAwarded
        seenWarmupLetters = snapshot.seenWarmupLetters
        rescueQueue = snapshot.rescueQueue.map {
            RescueItem(letterKey: $0.letterKey, dueAfterRounds: $0.dueAfterRounds, difficulty: $0.difficulty)
        }
        currentRoundIsRescue = snapshot.currentRoundIsRescue
        currentRescueDifficulty = snapshot.currentRescueDifficulty
        currentRoundPhaseOverride = snapshot.currentRoundPhaseOverride
        if let restoredBand = snapshot.instructionalBand {
            instructionalBand = restoredBand
        }
        if let restoredLetterOptions = snapshot.letterOptionsPerRound {
            frozenLetterOptionsPerRound = restoredLetterOptions
        }
        if let restoredPlayableWords = snapshot.sessionPlayableWords {
            sessionPlayableWords = restoredPlayableWords
        }
        liveDifficulty = snapshot.liveDifficulty
        recentRoundCorrectness = snapshot.recentRoundCorrectness
        governorCorrectStreak = snapshot.governorCorrectStreak
        // Pre-cascade checkpoints have no step count; assume 1 step of relief
        // when the eased state is on, 0 otherwise. That matches the old
        // behavior (single downshift) without re-tripping on restore.
        governorEaseSteps = snapshot.governorEaseSteps ?? (snapshot.liveDifficulty == .easierUntilStreak ? 1 : 0)
        focusTargetAttemptsThisSession = snapshot.focusTargetAttemptsThisSession
        focusTargetCorrectThisSession = snapshot.focusTargetCorrectThisSession
        teachingMode = snapshot.teachingMode
        effectiveScaffoldingLevel = snapshot.effectiveScaffoldingLevel
        remediationFocusLetter = snapshot.remediationFocusLetter
        preseededRemediationFocusLetter = snapshot.preseededRemediationFocusLetter
        unintroducedExposuresThisSession = snapshot.unintroducedExposuresThisSession
        cameoExposuresThisSession = snapshot.cameoExposuresThisSession ?? 0
        currentRoundCameoLetter = snapshot.currentRoundCameoLetter
        roundStartedAt = snapshot.roundStartedAt
        roundReplayCount = snapshot.roundReplayCount
        currentRoundIntent = snapshot.currentRoundIntent
        currentRoundPlanReason = snapshot.currentRoundPlanReason
        secondMissedLetters = snapshot.secondMissedLetters
        firstMissedLetters = snapshot.firstMissedLetters
        lastMistakeType = snapshot.lastMistakeType
        lastResponseTime = snapshot.lastResponseTime
        recentCorrectPositions = snapshot.recentCorrectPositions
        recentFocusCorrectPositions = snapshot.recentFocusCorrectPositions
        if snapshot.sessionCorrectPositionCounts.count == optionsPerRound {
            sessionCorrectPositionCounts = snapshot.sessionCorrectPositionCounts
        }
    }

    // MARK: - Public API

    /// Trigger the next round selection. Idempotent — picks a fresh target +
    /// distractors based on the current phase.
    func setupNewRound() {
        guard let profile = currentProfile() else {
            sessionEnded = .homeTapped
            targetLetter = ""
            displayedLetters = []
            return
        }
        syncCorrectPositionSlots()

        if case .extraPractice(let letter) = plan.mode {
            phase = .plainReview
            updateTeachingContext(profile: profile)
            previousTarget = targetLetter
            currentRoundPhaseOverride = nil
            currentRoundIsRescue = false
            currentRescueDifficulty = nil
            currentRoundPlanReason = nil
            roundStartedAt = nil
            roundReplayCount = 0
            lastMistakeType = nil
            lastResponseTime = nil
            currentRoundCameoLetter = nil
            buildExtraPracticeRound(profile: profile, target: letter)
            currentRoundIntent = .extraPractice
            currentRoundPlanReason = makeRoundPlanReason(profile: profile)
            rememberTargetLetter()
            return
        }

        // Phase transitions
        if phase == .warmup, roundsThisSession >= warmupLength {
            if plan.primaryLayer == .syllables {
                phase = .syllableRecognition
            } else if plan.primaryLayer == .words {
                phase = .wordReading
            } else {
                phase = activeDrillFocus(for: profile) == nil
                ? (plan.dailyPracticeKind == .reviewTest || profile.alphabetLevel != .expert ? .plainReview : .maintenance)
                : .drill
            }
        }
        if phase == .drill, activeDrillFocus(for: profile) == nil {
            phase = plan.dailyPracticeKind == .reviewTest || profile.alphabetLevel != .expert ? .plainReview : .maintenance
        }
        if phase == .plainReview,
           activeDrillFocus(for: profile) == nil,
           plan.dailyPracticeKind != .reviewTest,
           profile.alphabetLevel == .expert {
            phase = .maintenance
        }

        updateTeachingContext(profile: profile)
        previousTarget = targetLetter
        currentRoundPhaseOverride = nil

        // Phase 1b: per-round signal capture resets on every round build.
        // The view's audio-prompt playback is what defines "round started"
        // for the child, so `roundStartedAt` is set by the explicit
        // `markRoundStarted()` call (driven by `GameView`) rather than
        // here. Pre-clearing it forces a fresh stamp every round.
        roundStartedAt = nil
        roundReplayCount = 0
        lastMistakeType = nil
        lastResponseTime = nil
        currentRoundCameoLetter = nil
        currentRoundPlanReason = nil
        currentPlainReviewIntentOverride = nil

        // Phase 2a (#1): queued rescue items take precedence over the
        // session's main phase. We pop the oldest due item, build a
        // rescue round around it, and advance the remaining items by
        // one round. If no item is due, we build the regular round
        // for the current phase and still advance the queue (so a
        // delayed mid retry's clock counts down).
        if liveDifficulty == .easierUntilStreak {
            prioritizeRescueQueueForGovernor()
        }

        if let dueRescue = dequeueDueRescue() {
            currentRoundIsRescue = true
            currentRescueDifficulty = dueRescue.difficulty
            currentRoundPhaseOverride = .rescue
            buildRescueRound(profile: profile, item: dueRescue)
            currentRoundIntent = .rescue
        } else {
            currentRoundIsRescue = false
            currentRescueDifficulty = nil
            switch phase {
            case .warmup:
                buildWarmupRound(profile: profile)
                currentRoundIntent = governedIntent(.warmupConfidence)
            case .drill:
                buildDrillRound(profile: profile)
                // Drill targets are either the focus letter (focus-as-target)
                // or a known letter alongside a focus distractor (focus-as-
                // exposure). The intent reflects which side the round is on.
                if let focus = activeDrillFocus(for: profile), targetLetter == focus {
                    currentRoundIntent = governedIntent(.focusTarget)
                } else {
                    currentRoundIntent = governedIntent(.focusDistractorExposure)
                }
            case .plainReview:
                if shouldBuildContrastRound(profile: profile) {
                    buildContrastRound(profile: profile)
                } else {
                    buildPlainReviewRound(profile: profile)
                    let intent = currentPlainReviewIntentOverride
                        ?? (plan.dailyPracticeKind == .reviewTest ? .weeklyAssessment : .staleReview)
                    currentRoundIntent = governedIntent(intent)
                }
            case .rescue:
                // Defensive: the main phase machine never sets
                // `phase = .rescue` (rescue is queue-driven, not a
                // phase transition). Falling through to plainReview
                // keeps a corrupted state from crashing the round
                // pipeline.
                buildPlainReviewRound(profile: profile)
                currentRoundIntent = governedIntent(.staleReview)
            case .contrast:
                buildPlainReviewRound(profile: profile)
                currentRoundIntent = governedIntent(.staleReview)
            case .maintenance:
                if shouldBuildContrastRound(profile: profile) {
                    buildContrastRound(profile: profile)
                } else {
                    buildMaintenanceRound(profile: profile)
                    currentRoundIntent = governedIntent(.maintenance)
                }
            case .syllableCalibration:
                buildSyllableCalibrationRound(profile: profile)
                currentRoundIntent = .syllableFocus
            case .syllableRecognition:
                buildSyllableRecognitionRound(profile: profile)
                currentRoundIntent = .syllableFocus
            case .syllableBlending:
                buildSyllableRecognitionRound(profile: profile, activity: .syllableBlending)
                currentRoundIntent = .syllableBlending
            case .syllableSegmenting:
                buildWordReadingRound(profile: profile, activity: .syllableSegmenting)
                currentRoundIntent = .syllableSegmenting
            case .wordReading:
                buildWordReadingRound(profile: profile)
                currentRoundIntent = .wordReading
            case .wordBuilding:
                buildWordReadingRound(profile: profile, activity: .wordBuilding)
                currentRoundIntent = .wordBuilding
            }
        }

        currentRoundPlanReason = makeRoundPlanReason(profile: profile)
        rememberTargetLetter()
        advanceRescueQueue()
    }

    private func makeRoundPlanReason(profile: Profile) -> RoundPlanReason {
        let primaryGoal: RoundPrimaryGoal
        switch currentRoundIntent {
        case .warmupConfidence:
            primaryGoal = .warmupConfidence
        case .focusTarget, .focusDistractorExposure:
            primaryGoal = .newFocusPractice
        case .rescue, .remediation:
            primaryGoal = .assistedRecovery
        case .weeklyAssessment:
            primaryGoal = .weeklyAssessment
        case .contrastPair:
            primaryGoal = .contrastPractice
        case .syllableCalibration, .syllableFocus, .syllableBlending, .syllableSegmenting:
            primaryGoal = .readingBridge
        case .wordFocus, .wordReading:
            primaryGoal = .wordReading
        case .wordBuilding:
            primaryGoal = .wordBuilding
        case .maintenance:
            primaryGoal = .maintenance
        case .governorEase:
            primaryGoal = .governorEase
        case .staleReview:
            primaryGoal = .staleReview
        case .extraPractice:
            primaryGoal = .extraPractice
        }

        let targetSource: RoundTargetSource
        if currentRoundIsRescue {
            targetSource = .rescueQueue
        } else if currentRoundIntent == .contrastPair {
            targetSource = .confusedPair
        } else if case .extraPractice = plan.mode {
            targetSource = .parentPractice
        } else if plan.primaryLayer == .syllables {
            targetSource = profile.currentSyllableFocus == targetLetter ? .currentFocus : .bridgePrerequisite
        } else if plan.primaryLayer == .words {
            targetSource = profile.currentWordFocus == targetLetter ? .currentFocus : .playableCurriculum
        } else if currentRoundIntent == .weeklyAssessment,
                  plan.dailyPracticeKind == .reviewTest,
                  plan.weeklyReviewLetters.contains(targetLetter) {
            targetSource = .weeklyAssessmentCohort
        } else if activeDrillFocus(for: profile) == targetLetter {
            targetSource = .currentFocus
        } else if profile.letterStats[targetLetter]?.responseTimeBucket == .slow {
            targetSource = .knownButSlow
        } else {
            targetSource = .knownReview
        }

        let distractorPolicy: RoundDistractorPolicy
        if liveDifficulty == .easierUntilStreak {
            distractorPolicy = .governorEased
        } else if currentActivityKind == .wordBuilding {
            distractorPolicy = .tileAssembly
        } else if plan.primaryLayer == .syllables || plan.primaryLayer == .words {
            distractorPolicy = .audioPlayableOnly
        } else if let focus = activeDrillFocus(for: profile) {
            switch drillDistractorPolicy(forDrillFocus: focus, profile: profile) {
            case .avoid:
                distractorPolicy = currentRoundIsRescue ? .easyKnown : .avoidConfusables
            case .allowFluentPairs:
                distractorPolicy = .fluentConfusablesAllowed
            case .intentionallyPractice:
                distractorPolicy = .intentionallyPracticeConfusables
            }
        } else if plan.dailyPracticeKind == .reviewTest,
                  profile.letterStats[targetLetter]?.isStrongKnown != true {
            distractorPolicy = .avoidConfusables
        } else {
            distractorPolicy = .intentionallyPracticeConfusables
        }

        let difficulty = expectedDifficulty(
            profile: profile,
            primaryGoal: primaryGoal,
            distractorPolicy: distractorPolicy
        )
        return RoundPlanReason(
            primaryGoal: primaryGoal,
            targetSource: targetSource,
            distractorPolicy: distractorPolicy,
            expectedDifficulty: difficulty
        )
    }

    private func expectedDifficulty(
        profile: Profile,
        primaryGoal: RoundPrimaryGoal,
        distractorPolicy: RoundDistractorPolicy
    ) -> Double {
        var value = 0.45
        if profile.knownLetters.contains(targetLetter) { value += 0.12 }
        if profile.fluentKnownLetters.contains(targetLetter) { value += 0.08 }
        if targetLetter == activeDrillFocus(for: profile) || targetLetter == profile.currentSyllableFocus || targetLetter == profile.currentWordFocus {
            value += 0.12
        }
        if optionsPerRound > 4 { value += Double(optionsPerRound - 4) * 0.06 }
        switch distractorPolicy {
        case .easyKnown, .governorEased:
            value -= 0.12
        case .avoidConfusables, .audioPlayableOnly:
            break
        case .fluentConfusablesAllowed:
            value += 0.08
        case .intentionallyPracticeConfusables, .tileAssembly:
            value += 0.14
        }
        if primaryGoal == .assistedRecovery { value -= 0.1 }
        return min(0.95, max(0.1, value))
    }

    // MARK: - Phase 2a rescue queue helpers

    /// Schedule a retry for `letter` at the given difficulty. Honors the
    /// FIFO cap by dropping the oldest pending item when full. Two-tier
    /// usage (see `processAnswer`):
    ///
    /// * **Wrong answer in a non-rescue round** → enqueue
    ///   `(.easy, dueAfterRounds: 1)`. One different round lands first,
    ///   then the easy retry follows.
    /// * **Wrong answer in a rescue round (easy retry failed)** →
    ///   enqueue `(.mid, dueAfterRounds: rand 2…3)`. The child gets
    ///   a few non-rescue rounds in between to breathe.
    private func enqueueRescue(
        letter: String,
        difficulty: RescueDifficulty,
        dueAfterRounds: Int
    ) {
        if rescueQueue.count >= AdaptiveGameState.rescueQueueCap {
            rescueQueue.removeFirst()
        }
        rescueQueue.append(RescueItem(
            letterKey: letter,
            dueAfterRounds: dueAfterRounds,
            difficulty: difficulty
        ))
    }

    /// Pull the oldest queued item whose `dueAfterRounds <= 0`, or
    /// `nil` if no item is due. We scan from the front (oldest first)
    /// so an immediate-easy enqueued in the previous round always
    /// fires before any older delayed-mid that has aged into the
    /// due-window during the same setup.
    private func dequeueDueRescue() -> RescueItem? {
        guard let idx = rescueQueue.firstIndex(where: { $0.dueAfterRounds <= 0 }) else {
            return nil
        }
        return rescueQueue.remove(at: idx)
    }

    /// Decrement every remaining item's `dueAfterRounds` by one,
    /// floored at zero. Called once per round build (after the
    /// dequeue) so each round of play counts as one round of waiting.
    /// Items that reach zero stay there until pulled — they can't
    /// languish in negative territory.
    private func advanceRescueQueue() {
        for i in rescueQueue.indices {
            rescueQueue[i].dueAfterRounds = max(0, rescueQueue[i].dueAfterRounds - 1)
        }
    }

    // MARK: - Phase 2c governor helpers

    /// Non-rescue rounds generated while the governor is eased carry a
    /// specific intent. `RoundEvent.liveDifficulty` is still the canonical
    /// state stamp; this intent gives dashboards a simpler narrative label.
    private func governedIntent(_ base: RoundIntent) -> RoundIntent {
        liveDifficulty == .easierUntilStreak ? .governorEase : base
    }

    /// When the child is struggling, don't make them wait through delayed
    /// rescue timers. This implements the "rescue queue preferentially
    /// drained" part of the governor: all pending rescues become due now,
    /// and the normal FIFO dequeue still decides which one fires first.
    private func prioritizeRescueQueueForGovernor() {
        for i in rescueQueue.indices {
            rescueQueue[i].dueAfterRounds = 0
        }
    }

    /// Update the session-level difficulty governor after the answer's
    /// ordinary session mechanics have run, so it sees the post-answer heart
    /// count and the current session focus accuracy. The new mode affects the
    /// *next* round; the just-recorded `RoundEvent` carries the mode that was
    /// active when its round was generated.
    private func updateDifficultyGovernor(wasCorrect: Bool, target: String) {
        recentRoundCorrectness.append(wasCorrect)
        if recentRoundCorrectness.count > 4 {
            recentRoundCorrectness.removeFirst(recentRoundCorrectness.count - 4)
        }

        let focusKey = sessionFocusKey
        if let focus = focusKey, target == focus {
            focusTargetAttemptsThisSession += 1
            if wasCorrect {
                focusTargetCorrectThisSession += 1
            }
        }

        let lastFourWrongCount = recentRoundCorrectness.filter { !$0 }.count
        let threeOfLastFourWrong = recentRoundCorrectness.count == 4 && lastFourWrongCount >= 3
        let heartsLow = heartsRemaining <= 2
        let focusAccuracyLow: Bool
        if focusKey != nil,
           roundsThisSession >= 4,
           focusTargetAttemptsThisSession >= 2 {
            let accuracy = Double(focusTargetCorrectThisSession) / Double(focusTargetAttemptsThisSession)
            focusAccuracyLow = accuracy < 0.5
        } else {
            focusAccuracyLow = false
        }
        let tripTriggered = threeOfLastFourWrong || heartsLow || focusAccuracyLow

        if liveDifficulty == .easierUntilStreak {
            if wasCorrect {
                governorCorrectStreak += 1
                if governorCorrectStreak >= 2 {
                    governorCorrectStreak = 0
                    if governorEaseSteps > 1 {
                        // Recover one tier at a time so an 8-tier session that
                        // tripped twice walks back through 4 → 6 → 8 instead
                        // of snapping straight from 4 to 8.
                        governorEaseSteps -= 1
                    } else {
                        governorEaseSteps = 0
                        liveDifficulty = .normal
                    }
                }
                return
            }
            governorCorrectStreak = 0
            // Re-trip while already eased deepens the step (max 2 = 4-grid
            // floor). Clear the rolling window so the same wrongs that
            // caused the first trip can't cascade us straight to step 2.
            if tripTriggered, governorEaseSteps < 2 {
                governorEaseSteps += 1
                recentRoundCorrectness.removeAll()
                prioritizeRescueQueueForGovernor()
            }
            return
        }

        // A correct answer must never make the grid harder. `heartsLow` and
        // `focusAccuracyLow` are sticky latches (hearts only fall within a
        // session and the focus accuracy is a slow cumulative average), so
        // without the `!wasCorrect` guard the round right after a streak
        // recovery would re-trip purely from a stale latch — producing the
        // "got one right and the options dropped from 6 back to 4" flicker.
        // Easing is a response to struggle, and a correct answer is not
        // struggle; the next genuine miss will re-trip if the child is still
        // having a hard time.
        if tripTriggered, !wasCorrect {
            liveDifficulty = .easierUntilStreak
            governorEaseSteps = 1
            governorCorrectStreak = 0
            recentRoundCorrectness.removeAll()
            prioritizeRescueQueueForGovernor()
        }
    }

    private func updateTeachingContext(profile: Profile) {
        let previousMode = teachingMode
        teachingMode = resolveTeachingMode(profile: profile)
        effectiveScaffoldingLevel = scaffoldingLevel(for: teachingMode, profile: profile)
        if teachingMode == .remediation,
           let focus = profile.currentFocusLetter,
           preseededRemediationFocusLetter != focus {
            preseedRemediationQueue(for: focus)
            preseededRemediationFocusLetter = focus
        } else if previousMode == .remediation,
                  teachingMode != .remediation {
            preseededRemediationFocusLetter = nil
        }
    }

    private func resolveTeachingMode(profile: Profile) -> FocusTeachingMode {
        if profile.currentFocusLetter == nil {
            remediationFocusLetter = nil
            return profile.alphabetLevel == .expert ? .maintenance : .normal
        }
        if shouldUseRemediation(profile: profile) {
            return .remediation
        }
        return profile.focusActiveDays <= 2 ? .scaffolded : .normal
    }

    private func scaffoldingLevel(for mode: FocusTeachingMode, profile: Profile) -> Int {
        switch mode {
        case .scaffolded, .remediation:
            // R5 fix: remediation goes to MAX scaffolding, not zero.
            return 3
        case .normal:
            return max(0, 3 - profile.focusActiveDays + 1)
        case .contrast, .maintenance:
            return 0
        }
    }

    /// Phase 2e stuck-focus rule with hysteresis:
    ///
    /// * Enter remediation after 5+ active focus days and < 50% recent
    ///   accuracy.
    /// * Stay there until the same focus reaches >= 60% recent accuracy.
    private func shouldUseRemediation(profile: Profile) -> Bool {
        guard let focus = profile.currentFocusLetter,
              let stat = profile.letterStats[focus],
              profile.focusActiveDays >= 5 else {
            remediationFocusLetter = nil
            return false
        }
        let recentAccuracy = stat.recentAccuracy(window: 5)
        if remediationFocusLetter == focus {
            if recentAccuracy >= 0.6 {
                remediationFocusLetter = nil
                return false
            }
            return true
        }
        if recentAccuracy < 0.5 {
            remediationFocusLetter = focus
            return true
        }
        return false
    }

    /// "High rescue aggressiveness" for remediation: make the stuck focus
    /// immediately available as an easy win, then schedule a mid retry shortly
    /// after. Duplicate entries are skipped so entering remediation is a
    /// single nudge, not a queue flood.
    private func preseedRemediationQueue(for focus: String) {
        if !rescueQueue.contains(where: { $0.letterKey == focus && $0.difficulty == .easy }) {
            enqueueRescue(letter: focus, difficulty: .easy, dueAfterRounds: 0)
        }
        if !rescueQueue.contains(where: { $0.letterKey == focus && $0.difficulty == .mid }) {
            enqueueRescue(letter: focus, difficulty: .mid, dueAfterRounds: 2)
        }
    }

    private func focusTargetChance() -> Double {
        let base: Double
        switch teachingMode {
        case .scaffolded:
            base = 0.45
        case .remediation:
            base = 0.20
        case .normal:
            base = 0.35
        case .contrast, .maintenance:
            base = 0.0
        }
        return liveDifficulty == .easierUntilStreak ? base * 0.5 : base
    }

    private func scaffoldingLevel(forDrillFocus focus: String, profile: Profile) -> Int {
        if focus == profile.currentFocusLetter {
            return effectiveScaffoldingLevel
        }
        guard let stat = profile.letterStats[focus], stat.targetAttempts > 0 else {
            return 3
        }
        if stat.targetAttempts < 3 || stat.recentAccuracy(window: 5) < 0.5 {
            return 3
        }
        if !stat.isKnown {
            return 2
        }
        return stat.isStrongKnown ? 0 : 1
    }

    private func drillDistractorPolicy(
        forDrillFocus focus: String,
        profile: Profile
    ) -> LetterDifficulty.ConfusionPolicy {
        if liveDifficulty == .easierUntilStreak { return .avoid }
        if focus != profile.currentFocusLetter {
            return profile.letterStats[focus]?.isStrongKnown == true ? .allowFluentPairs : .avoid
        }
        let basePolicy: LetterDifficulty.ConfusionPolicy
        switch teachingMode {
        case .scaffolded, .remediation:
            basePolicy = .avoid
        case .normal:
            basePolicy = profile.focusActiveDays >= 3 ? .allowFluentPairs : .avoid
        case .contrast, .maintenance:
            basePolicy = .intentionallyPractice
        }
        return levelAdjustedPolicy(basePolicy)
    }

    private func levelAdjustedPolicy(
        _ basePolicy: LetterDifficulty.ConfusionPolicy
    ) -> LetterDifficulty.ConfusionPolicy {
        guard liveDifficulty != .easierUntilStreak else { return .avoid }
        if basePolicy == .avoid { return .avoid }

        switch instructionalBand.confusionStage {
        case .gentle:
            return .avoid
        case .safeKnownPairs:
            return .allowFluentPairs
        case .intentionalPractice, .mixedCaseReview:
            return .intentionallyPractice
        }
    }

    // MARK: - Phase 1b round-signal API
    //
    // These three entry points are the only way the view should drive
    // round-level signal capture. Keeping them on `AdaptiveGameState`
    // (rather than scattered booleans on the view) means everyone
    // observes a consistent timeline regardless of what other animation
    // sequences happen to overlap on screen.

    /// Records that the round's prompt has finished playing and the
    /// child can now tap. `GameView` calls this after the audio
    /// completes (or immediately, for rounds without audio) so
    /// response-time classification ignores the audio-playback window.
    /// Idempotent: calling twice on the same round leaves the original
    /// timestamp in place so a stray invocation can't reset the clock.
    func markRoundStarted() {
        if roundStartedAt == nil {
            roundStartedAt = Date()
        }
    }

    /// Commits day-streak and focus-day bookkeeping on the first real answer.
    /// Merely opening the game uses a preview plan and leaves profile history
    /// untouched, which keeps parent test launches from counting as practice.
    func commitSessionStartIfNeeded(lowercaseMode: LowercaseMode = .uppercaseOnly) {
        guard roundsThisSession == 0 else { return }
        guard case .adaptiveDaily = plan.mode else { return }
        _ = profileManager?.commitSessionStartIfNeeded(profileId: profileId, lowercaseMode: lowercaseMode)
    }

    /// Bump the per-round replay counter. Called by `GameView`'s
    /// speaker-button handler each time the child re-taps to hear the
    /// prompt again. Phase 4a's long-press slowed-replay also routes
    /// through this so a slow replay counts as a replay.
    func didReplayPrompt() {
        roundReplayCount += 1
    }

    /// Pure classifier mapping (was-correct, response-time) → `MistakeType`.
    /// Static so it can be unit-tested without an `AdaptiveGameState`
    /// instance.
    ///
    /// * `nil` response time → `.unknown` (we don't have evidence to
    ///   classify; can't honestly call it impulse or confusion).
    /// * Sub-`impulseThreshold` wrong tap → `.impulsiveTap`.
    /// * Otherwise wrong → `.confusion`.
    /// * Correct → `.unknown` (mistakeType only meaningful for wrong
    ///   answers; Phase 0e's `RoundEvent.mistakeType` carries `nil`
    ///   for correct rounds via the call site).
    nonisolated static func classifyMistake(
        wasCorrect: Bool,
        responseTime: TimeInterval?,
        impulseThreshold: TimeInterval = AdaptiveGameState.impulseThreshold
    ) -> MistakeType {
        if wasCorrect { return .unknown }
        guard let rt = responseTime else { return .unknown }
        if rt < impulseThreshold { return .impulsiveTap }
        return .confusion
    }

    private func adaptiveImpulseThreshold(profile: Profile?) -> TimeInterval {
        guard let profile else { return Self.impulseThreshold }
        let samples = profile.letterStats.values.flatMap(\.recentResponseTimes)
        guard samples.count >= 4 else { return Self.impulseThreshold }
        let sorted = samples.sorted()
        let median: TimeInterval
        if sorted.count % 2 == 1 {
            median = sorted[sorted.count / 2]
        } else {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return min(
            Self.maxAdaptiveImpulseThreshold,
            max(Self.minAdaptiveImpulseThreshold, median * Self.adaptiveImpulseMedianMultiplier)
        )
    }

    /// Process a tap on a letter button. Returns a `AnswerOutcome` that the
    /// view chains animations off of.
    func processAnswer(_ selected: String) -> AnswerOutcome {
        let roundTarget = currentRound?.target ?? .letter(targetLetter)
        let selectedTarget: FocusTarget
        switch roundTarget.kind {
        case .letter:
            selectedTarget = .letter(selected)
        case .syllable:
            selectedTarget = .syllable(selected)
        case .word:
            selectedTarget = .word(selected)
        }
        let wasCorrect = selectedTarget == roundTarget
        let correctLetter = targetLetter
        let target = targetLetter
        let wasRevealedAtRoundStart = secondMissedLetters.contains(target)
        let attemptContext: AttemptContext
        if wasRevealedAtRoundStart {
            attemptContext = .revealed
        } else if currentRoundIsRescue {
            attemptContext = currentRescueDifficulty == .easy ? .immediateRescue : .delayedRescue
        } else if case .extraPractice = plan.mode {
            attemptContext = .extraPractice
        } else {
            attemptContext = .independent
        }
        let focusKey = sessionFocusKey ?? currentProfile()?.currentFocusTarget?.rawKey
        let includedFocusAsDistractor = focusKey.map { displayedLetters.contains($0) && $0 != target } ?? false

        // Phase 1b: capture per-round signals before forwarding the
        // result anywhere. `responseTime` is the seconds elapsed since
        // `markRoundStarted()`; if the view forgot to call it (or the
        // call hasn't yet fired in some edge case), we leave it `nil`
        // so the classifier produces `.unknown` rather than a falsely
        // tiny number.
        let responseTime: TimeInterval? = roundStartedAt.map { Date().timeIntervalSince($0) }
        let profileAtAnswer = currentProfile()
        let rawMistakeType = AdaptiveGameState.classifyMistake(
            wasCorrect: wasCorrect,
            responseTime: responseTime,
            impulseThreshold: adaptiveImpulseThreshold(profile: profileAtAnswer)
        )
        let mistakeType: MistakeType
        if !wasCorrect,
           attemptContext.isAssistedForMastery,
           rawMistakeType == .impulsiveTap {
            // Assisted retries are teaching/diagnostic moments. They are
            // discounted for mastery, but a wrong answer still reflects a
            // real confusion and should cost a heart like any other miss.
            mistakeType = .confusion
        } else {
            mistakeType = rawMistakeType
        }
        lastResponseTime = responseTime
        lastMistakeType = wasCorrect ? nil : mistakeType

        // Phase 1b: track first-miss / second-miss transitions. The set
        // is keyed by target letter so a child who misses B then misses
        // M then misses B again triggers `secondMissedLetters` on the
        // *second* B miss, not the second miss overall. Phase 4a's
        // show-me reveal animation reads `secondMissedLetters` to know
        // when to fire.
        if !wasCorrect {
            if firstMissedLetters.contains(target) {
                secondMissedLetters.insert(target)
            } else {
                firstMissedLetters.insert(target)
            }
        }

        guard let manager = profileManager else {
            return AnswerOutcome(
                wasCorrect: wasCorrect,
                correctLetter: correctLetter,
                heartsRemaining: heartsRemaining
            )
        }

        // Phase 1c: forward the per-round signals captured in Phase 1b
        // (response time, mistake type, replay count, intent, phase,
        // hearts state, rescue metadata) through the recorder. The
        // manager uses these to drive the impulse-discount split (R6),
        // the confused-with vs. impulsive-selections routing (R7), and
        // the full-shape RoundEvent log entry (Phase 0e). Hearts are
        // reported *as currently observed* — Phase 1d will adjust the
        // value based on `mistakeType` before the next round is
        // generated, but this snapshot is what the round itself ended
        // with from the persistence-layer's point of view.
        let answerPhase = currentRoundPhaseOverride ?? (currentRoundIsRescue ? .rescue : phase)
        let managerOutcome: RecordedAnswer = manager.withDeferredSaves {
            let recordedAnswer: RecordedAnswer
            if roundTarget.kind == .letter {
                recordedAnswer = manager.recordAnswer(
                    profileId: profileId,
                    letter: target,
                    wasCorrect: wasCorrect,
                    asTarget: true,
                    responseTime: responseTime,
                    didReplayPrompt: roundReplayCount > 0,
                    replayCount: roundReplayCount,
                    mistakeType: wasCorrect ? .unknown : mistakeType,
                    selectedWrongLetter: wasCorrect ? nil : selected,
                    optionsShown: displayedLetters,
                    intent: currentRoundIntent,
                    phaseAtAnswer: answerPhase,
                    heartsAfter: heartsRemaining,
                    liveDifficulty: liveDifficulty,
                    isRescue: currentRoundIsRescue,
                    rescueDifficulty: currentRescueDifficulty,
                    attemptContext: attemptContext,
                    cameoLetter: currentRoundCameoLetter,
                    includedFocusAsDistractor: includedFocusAsDistractor,
                    planReason: currentRoundPlanReason,
                    countsTowardDailyPractice: plan.mode == .adaptiveDaily
                )
            } else {
                recordedAnswer = manager.recordAnswer(
                    profileId: profileId,
                    target: roundTarget,
                    wasCorrect: wasCorrect,
                    asTarget: true,
                    responseTime: responseTime,
                    didReplayPrompt: roundReplayCount > 0,
                    replayCount: roundReplayCount,
                    mistakeType: wasCorrect ? .unknown : mistakeType,
                    selectedWrongTarget: wasCorrect ? nil : selectedTarget,
                    optionsShown: currentRound?.options ?? displayedLetters.map { FocusTarget(kind: roundTarget.kind, key: $0) },
                    intent: currentRoundIntent,
                    phaseAtAnswer: answerPhase,
                    activityKind: currentActivityKind,
                    heartsAfter: heartsRemaining,
                    liveDifficulty: liveDifficulty,
                    isRescue: currentRoundIsRescue,
                    rescueDifficulty: currentRescueDifficulty,
                    attemptContext: attemptContext,
                    includedFocusAsDistractor: includedFocusAsDistractor,
                    planReason: currentRoundPlanReason,
                    countsTowardDailyPractice: plan.mode == .adaptiveDaily
                )
            }

            // Record exposure for the letters that were on screen but not chosen,
            // so the parent dashboard can show "seen X times".
            for shown in displayedLetters where shown != target {
                if roundTarget.kind == .letter {
                    if !LetterDifficulty.isVisualOnlyDistractor(shown) {
                        if shown == currentRoundCameoLetter {
                            if manager.recordCameoExposure(profileId: profileId, letter: shown) {
                                cameoExposuresThisSession += 1
                            } else {
                                manager.recordExposure(profileId: profileId, letter: shown)
                            }
                        } else {
                            manager.recordExposure(profileId: profileId, letter: shown)
                        }
                    }
                } else {
                    manager.recordExposure(profileId: profileId, target: FocusTarget(kind: roundTarget.kind, key: shown))
                }
            }
            return recordedAnswer
        }

        roundsThisSession += 1
        if phase == .warmup {
            warmupAttemptCount += 1
            seenWarmupLetters.insert(target)
        }

        var streakMilestone: StreakMilestone?
        var stampEarned: DailyStamp?
        var focusGraduatedNow: String?
        var leveledUp: AlphabetLevel?
        var sessionEnd: SessionEndReason?

        if wasCorrect {
            currentStreak += 1
            sessionBestStreak = max(sessionBestStreak, currentStreak)
            roundsCorrect += 1
            totalCorrectThisSession += 1
            consecutiveWarmupMisses = 0
            if phase == .warmup { warmupCorrectCount += 1 }

            // Streak milestones
            if currentStreak == 5 {
                streakMilestone = .five
            } else if currentStreak == 10 || (currentStreak > 10 && currentStreak % 10 == 0) {
                streakMilestone = .ten
            }

            // Hello-letter stamp: first interaction with the focus letter.
            let focusKey = sessionFocusKey
            if let focus = focusKey, target == focus, !helloFocusAwarded {
                helloFocusAwarded = true
                stampEarned = awardStamp(.helloFocus)
            }

            // Focus letter graduates? (handled by manager; we surface it.)
            if let graduated = managerOutcome.focusGraduated {
                focusGraduatedNow = graduated
                focusGraduatedThisSession = graduated
            }

            // Practice-pro stamp: weighted "good encounters" with the focus
            // letter (focus sessions), or raw correct-count (no-focus
            // sessions).
            //
            // Focus sessions — per-round contribution to `practiceProgress`:
            //   * target == focus, correct (drill or rescue) → +1.0
            //   * target != focus, focus on screen as
            //     distractor, correct                         → +0.5
            //   * target == focus, incorrect                  → 0
            //          (no credit on its own; can be redeemed by the
            //          subsequent rescue round, whose correct answer
            //          lands the regular +1.0 because rescueTarget == focus)
            //
            // The +0.5 path matches the focus-as-exposure design: every
            // time the child sees the focus letter and correctly avoids
            // tapping it, they're learning to tell it apart from known
            // letters. That's worth half a credit toward "you know your
            // new letter today." Threshold = `practiceProThreshold` (5.0).
            //
            // No-focus sessions: there's no focus to weight against, so we
            // fall back to "10 correct review answers in the session" —
            // unchanged from before. Awarded once when the count first
            // reaches 10, not each time we re-cross.
            if let focus = focusKey {
                if target == focus {
                    practiceProgress += 1.0
                } else if displayedLetters.contains(focus) {
                    practiceProgress += 0.5
                }
                if practiceProgress >= practiceProThreshold,
                   !stampsEarned.contains(.practicePro) {
                    stampEarned = awardStamp(.practicePro) ?? stampEarned
                }
            } else if totalCorrectThisSession == 10,
                      !stampsEarned.contains(.practicePro) {
                stampEarned = awardStamp(.practicePro) ?? stampEarned
            }

            // Streak-star stamp: 5-in-a-row.
            if currentStreak == 5, !stampsEarned.contains(.streakStar) {
                stampEarned = awardStamp(.streakStar) ?? stampEarned
            }

            // Level-up celebration.
            if let newLevel = managerOutcome.leveledUp {
                leveledUp = newLevel
                didLevelUpThisSession = true
            }

            // Opener stamp (warmupStar / braveStart / reviewStar). Exactly
            // one of these is in play per session — see
            // `computeApplicableStamps(for:)`. Each has its own award rule:
            //
            //   * warmupStar — completed the warm-up window
            //                  (warmupAttemptCount >= warmupLength) AND
            //                  warmupCorrectCount / warmupAttemptCount >= 0.8.
            //                  Concrete examples for warmupLength == 5:
            //                    5/5, 4/5  → award.
            //                    3/5 or worse → no award (warm-up ends without
            //                    the stamp; the child still keeps playing).
            //
            //   * braveStart — first correct answer in the session.
            //                  Sparse profiles (<3 known letters) skip the
            //                  warm-up phase entirely, so accuracy isn't a
            //                  meaningful gate; we celebrate the moment the
            //                  child gets *anything* right.
            //
            //   * reviewStar — 5 correct rounds in the session.
            //                  No-focus / expert sessions have no warm-up
            //                  phase to gate against, so we mirror the
            //                  warmupStar shape using session-correct count
            //                  as the proxy for "settled in confidently."
            if !stampsEarned.contains(openerStamp) {
                switch openerStamp {
                case .warmupStar:
                    if phase == .warmup,
                       warmupAttemptCount >= warmupLength {
                        let ratio = Double(warmupCorrectCount) / Double(max(1, warmupAttemptCount))
                        if ratio >= 0.8 {
                            stampEarned = awardStamp(.warmupStar) ?? stampEarned
                        }
                    }
                case .braveStart:
                    if totalCorrectThisSession == 1 {
                        stampEarned = awardStamp(.braveStart) ?? stampEarned
                    }
                case .reviewStar:
                    if totalCorrectThisSession == 5 {
                        stampEarned = awardStamp(.reviewStar) ?? stampEarned
                    }
                default:
                    break
                }
            }
        } else {
            currentStreak = 0
            // Phase 1d (R6 fix): the session-mechanics heart cost runs on
            // the same impulse classification as the persistence-layer
            // discount in `ProfileManager.recordAnswer` — both layers
            // reach for the same `MistakeType` independently. An impulse
            // tap (sub-`impulseThreshold` after grid appearance) is
            // treated as "didn't actually try", so we don't punish it
            // with a heart. The child still gets a rescue round below
            // (we still want them to land the correct answer), the
            // streak still resets (a wrong tap is a wrong tap), and the
            // tired-signal still considers it a warm-up miss. Only the
            // heart-budget is shielded.
            let shouldLoseHeart = mistakeType != .impulsiveTap
            if shouldLoseHeart {
                heartsRemaining = max(0, heartsRemaining - 1)
            }

            // Hello-letter stamp also lights up on a wrong tap *for* the focus
            // letter — point of the stamp is exposure, not correctness.
            let focusKey = sessionFocusKey
            if let focus = focusKey, target == focus, !helloFocusAwarded {
                helloFocusAwarded = true
                stampEarned = awardStamp(.helloFocus)
            }

            if phase == .warmup {
                consecutiveWarmupMisses += 1
            }

            if heartsRemaining == 0 {
                sessionEnd = .outOfHearts
            } else if roundTarget.kind == .letter {
                // Phase 2a (#1): two-tier rescue queue.
                //
                // * If the round we just answered was *itself* a rescue
                //   round, the easy-difficulty retry already failed.
                //   Schedule a mid-difficulty retry 2–3 rounds out
                //   so the child has a few normal rounds to settle
                //   first, then meets the same letter again with a
                //   harder pool.
                // * Otherwise it's a fresh wrong target → queue an
                //   easy retry after one intervening round.
                if currentRoundIsRescue {
                    enqueueRescue(
                        letter: target,
                        difficulty: .mid,
                        dueAfterRounds: Int.random(in: AdaptiveGameState.midRescueDelayRange)
                    )
                } else {
                    enqueueRescue(
                        letter: target,
                        difficulty: .easy,
                        dueAfterRounds: 1
                    )
                }
            }
        }

        if phase == .syllableCalibration,
           roundsThisSession >= 12,
           sessionEnd == nil {
            manager.completeSyllableCalibration(profileId: profileId)
            sessionEnd = .goalComplete
        }

        if case .extraPractice = plan.mode {
            if roundsThisSession >= 8 || roundsCorrect >= 5 {
                stampEarned = awardStamp(.extraPractice) ?? stampEarned
                sessionEnd = .practiceComplete
            }
        }

        updateDifficultyGovernor(wasCorrect: wasCorrect, target: target)

        let outcome = AnswerOutcome(
            wasCorrect: wasCorrect,
            correctLetter: correctLetter,
            heartsRemaining: heartsRemaining,
            streakMilestone: streakMilestone,
            stampEarned: stampEarned,
            focusGraduated: focusGraduatedNow,
            leveledUp: leveledUp,
            sessionEndReason: sessionEnd
        )
        lastOutcome = outcome
        if let end = sessionEnd { sessionEnded = end }
        return outcome
    }

    /// Whether the next unclaimed daily-goal milestone has been reached —
    /// used to show the "WINNER" button next to the replay button.
    var hasCompletedDailyGoal: Bool {
        guard case .adaptiveDaily = plan.mode,
              plan.activityKind != .syllableCalibration else {
            return applicableStamps.allSatisfy { stampsEarned.contains($0) }
        }
        return claimableDailyGoalMilestone != nil
    }

    /// Captures the in-memory session totals for `ProfileManager.endSession`
    /// and `SessionEndView`. Always returns a value, never nil — the session
    /// always ended somehow.
    func makeSummary(reason: SessionEndReason) -> SessionSummary {
        let profile = currentProfile() ?? fallbackProfile
        let total = profile.language.letters.count
        let nextLevel = profile.alphabetLevel
        let threshold = nextLevel.threshold(language: profile.language)
        let nextFocusPreview: String?
        if let focus = profile.currentFocusLetter, focusGraduatedThisSession == nil {
            nextFocusPreview = focus
        } else {
            nextFocusPreview = nextUnintroducedLetter(profile: profile)
        }
        return SessionSummary(
            profileId: profileId,
            endReason: reason,
            stampsEarned: stampsEarned,
            applicableStamps: applicableStamps,
            heartsRemaining: heartsRemaining,
            bestSessionStreak: sessionBestStreak,
            roundsAnswered: roundsThisSession,
            roundsCorrect: roundsCorrect,
            focusGraduatedThisSession: focusGraduatedThisSession,
            dayStreakCount: profile.dailyStreakCount,
            bestDailyStreak: profile.bestDailyStreak,
            letterMasteredCount: profile.letterMasteredCount,
            totalLetters: total,
            nextLevelThreshold: threshold,
            currentFocusLetter: profile.currentFocusLetter,
            nextFocusPreview: nextFocusPreview,
            didLevelUp: didLevelUpThisSession,
            newLevel: nextLevel,
            unintroducedExposures: unintroducedExposuresThisSession
        )
    }

    // MARK: - Round building

    private func currentProfile() -> Profile? {
        guard var profile = profileManager?.profiles.first(where: { $0.id == profileId }) else {
            return nil
        }
        guard case .adaptiveDaily = plan.mode else {
            return profile
        }

        var hasPreviewFocus = false
        if let previewTarget = plan.focusTarget {
            hasPreviewFocus = true
            switch previewTarget {
            case .letter(let previewFocus):
                let persistedFocus = profile.currentFocusLetter
                guard persistedFocus == nil || persistedFocus == previewFocus else { return profile }
                profile.currentFocusLetter = previewFocus
                profile.introducedLetters.insert(previewFocus)
            case .syllable, .word:
                return profile
            }
        } else if let previewFocus = plan.focusLetter {
            hasPreviewFocus = true
            let persistedFocus = profile.currentFocusLetter
            guard persistedFocus == nil || persistedFocus == previewFocus else { return profile }
            profile.currentFocusLetter = previewFocus
            profile.introducedLetters.insert(previewFocus)
        }
        if let spotlight = plan.dailySpotlightLetter {
            profile.introducedLetters.insert(spotlight)
        }

        if hasPreviewFocus {
            profile.focusStartedDay = profile.focusStartedDay ?? LocalDay.today()
            profile.focusPracticedDays.insert(LocalDay.today())
        }
        return profile
    }

    private func syncCorrectPositionSlots() {
        let expectedCount = optionsPerRound
        guard sessionCorrectPositionCounts.count != expectedCount else { return }

        if sessionCorrectPositionCounts.count < expectedCount {
            sessionCorrectPositionCounts.append(contentsOf: Array(repeating: 0, count: expectedCount - sessionCorrectPositionCounts.count))
        } else {
            sessionCorrectPositionCounts = Array(sessionCorrectPositionCounts.prefix(expectedCount))
            recentCorrectPositions.removeAll { $0 >= expectedCount }
            recentFocusCorrectPositions.removeAll { $0 >= expectedCount }
        }
    }

    private func eligibleTargetCandidates(_ candidates: [String]) -> [String] {
        candidates.filter { LetterDifficulty.isEligibleTarget($0, language: language) }
    }

    private func uniqueEligibleTargets(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard LetterDifficulty.isEligibleTarget(candidate, language: language),
                  !seen.contains(candidate) else {
                return nil
            }
            seen.insert(candidate)
            return candidate
        }
    }

    private func preferNotRecentlyTargeted(_ candidates: [String]) -> String? {
        let eligible = uniqueEligibleTargets(candidates)
        guard !eligible.isEmpty else { return nil }
        let recent = Set(recentTargetLetters)
        return eligible.first(where: { !recent.contains($0) && $0 != previousTarget })
            ?? eligible.first(where: { !recent.contains($0) })
            ?? eligible.first(where: { $0 != previousTarget })
            ?? eligible.first
    }

    private func rememberTargetLetter() {
        guard !targetLetter.isEmpty else { return }
        recentTargetLetters.append(targetLetter)
        if recentTargetLetters.count > recentTargetMemoryLimit {
            recentTargetLetters.removeFirst(recentTargetLetters.count - recentTargetMemoryLimit)
        }
    }

    private func setTargetLetter(
        _ candidate: String,
        profile: Profile,
        fallbackCandidates: [String] = []
    ) {
        let fallback = fallbackCandidates
            + profile.lettersByConfidence
            + LetterDifficulty.calibrationPool(
                for: language,
                nameLetter: profile.firstNameLetterKey
            )
            + language.letters
        targetLetter = ([candidate] + fallback).first {
            LetterDifficulty.isEligibleTarget($0, language: language)
        } ?? "A"
    }

    private func buildWarmupRound(profile: Profile) {
        // Phase 2b (#2): warm-up target selection ranks known letters by
        // `reviewPriority` (weakness + staleness + slowness) instead of by
        // raw confidence. The child still only sees letters they already
        // know — `knownLetters` is unchanged — but within that pool we lead
        // with the one most worth re-checking today: the one they were
        // slowest on, hadn't seen in a while, or recently slipped on.
        // Confidence-only ordering hid those signals behind the same handful
        // of "always strong" letters every morning.
        //
        // Distractors continue to be drawn from the confidence-ordered pool
        // because there we *want* the strongest letters (easy elimination is
        // the whole point of warm-up).
        let priorityOrder = eligibleTargetCandidates(profile.snapshot.lettersByReviewPriority)
        let confidence = profile.lettersByConfidence
        guard !priorityOrder.isEmpty else {
            buildPlainReviewRound(profile: profile)
            return
        }
        // Sweep through the highest-priority half before allowing repeats so
        // the child still sees variety. `max(3, count/2)` keeps the pool
        // usable when the child only knows a handful of letters.
        let topHalf = Array(priorityOrder.prefix(max(3, priorityOrder.count / 2)))
        let pool = topHalf.filter { !seenWarmupLetters.contains($0) }
        let candidate = (pool.randomElement() ?? topHalf.randomElement() ?? priorityOrder.first!)
        let targetCandidate = (candidate == previousTarget && topHalf.count > 1)
            ? (topHalf.first(where: { $0 != previousTarget }) ?? candidate)
            : candidate
        setTargetLetter(targetCandidate, profile: profile, fallbackCandidates: priorityOrder)
        let target = targetLetter

        // Distractors: enough other known letters from the confidence-ordered
        // pool to fill the current level's grid, never the focus letter.
        let pool0 = Set(confidence).subtracting([target, activeDrillFocus(for: profile) ?? ""])
        let chosen = pickFiltered(from: Array(pool0), count: optionsPerRound - 1, target: target, profile: profile)
        // Warm-up never uses focus as the target, so isFocusTarget = false.
        displayedLetters = placeAnswer(target: target, distractors: chosen, isFocusTarget: false)
    }

    private func buildDrillRound(profile: Profile) {
        guard let focus = activeDrillFocus(for: profile) else {
            buildPlainReviewRound(profile: profile)
            return
        }
        let confidence = profile.lettersByConfidence
        let scaffolding = scaffoldingLevel(forDrillFocus: focus, profile: profile)

        // Target: usually 50% focus / 35% lower-confidence known /
        // 15% high-confidence known, but with one override:
        //
        //   * If the helloFocus stamp is still unearned and we're at or past
        //     `firstFocusAppearanceDeadline`, force the focus letter as the
        //     target. This guarantees the child gets *asked* to find their
        //     new letter at least once before the heart budget can run out.
        //
        // Note `roundsThisSession` is the count *before* this round is played,
        // so when we're building round number K (1-indexed), it equals K-1.
        // The deadline check `roundsThisSession + 1 >= deadline` therefore
        // fires on the round number equal to the deadline.
        let mustForceFocus = !helloFocusAwarded
            && (roundsThisSession + 1) >= firstFocusAppearanceDeadline
        let targetCandidate: String = mustForceFocus
            ? focus
            : chooseDrillTarget(focus: focus, confidence: confidence)
        setTargetLetter(targetCandidate, profile: profile, fallbackCandidates: confidence + [focus])
        let target = targetLetter

        var distractors: [String] = []
        // Phase-based confusion policy for drill (§15):
        //   * Day 1–2 of the focus letter — `.avoid`. The child is still
        //     forming a stable mental shape; pairing it with a near-twin
        //     just teaches confusion.
        //   * Day 3+ — `.allowFluentPairs`. The shape has held up over
        //     a couple of days, so confusable distractors can come in IF
        //     both letters are already known to the child.
        // Easy / scaffolding slots stay on `.avoid` regardless of day —
        // they exist to make the round winnable, not to teach
        // discrimination.
        let normalPolicy = drillDistractorPolicy(forDrillFocus: focus, profile: profile)

        if target == focus {
            // Distractors split between easy (top of confidence) and normal
            // (rest of knownLetters), never including focus itself.
            let easyCount = min(scaffolding, optionsPerRound - 1)
            let normalCount = (optionsPerRound - 1) - easyCount
            distractors.append(contentsOf: pickEasyDistractors(profile: profile, target: target, exclude: [focus], count: easyCount))
            distractors.append(contentsOf: pickNormalDistractors(profile: profile, target: target, exclude: Set(distractors).union([focus]), count: normalCount, policy: normalPolicy))
        } else {
            // Target is a known letter. Focus occupies one slot (the "expose
            // them wrongly" trick); the remaining slots split easy/normal.
            distractors.append(focus)
            let easyCount = min(scaffolding, optionsPerRound - 2)
            let normalCount = (optionsPerRound - 2) - easyCount
            distractors.append(contentsOf: pickEasyDistractors(profile: profile, target: target, exclude: Set([focus]), count: easyCount))
            distractors.append(contentsOf: pickNormalDistractors(profile: profile, target: target, exclude: Set(distractors), count: normalCount, policy: normalPolicy))
            distractors = maybeInjectCameoLetter(
                into: distractors,
                target: target,
                profile: profile,
                phase: .drill,
                confusionPolicy: normalPolicy
            )
        }

        displayedLetters = placeAnswer(
            target: target,
            distractors: distractors,
            isFocusTarget: target == focus
        )
    }

    private func buildPlainReviewRound(profile: Profile) {
        let reviewCandidates: [String]
        let assessmentTarget: String?
        let assessmentBucket: WeeklyAssessmentBucket?
        if plan.dailyPracticeKind == .reviewTest {
            assessmentTarget = chooseWeeklyAssessmentTarget(profile: profile)
            assessmentBucket = assessmentTarget.flatMap { profile.activeWeeklyAssessment?.result(for: $0).bucket }
            if let assessmentTarget {
                currentPlainReviewIntentOverride = .weeklyAssessment
                reviewCandidates = uniqueEligibleTargets([assessmentTarget])
            } else {
                currentPlainReviewIntentOverride = .staleReview
                reviewCandidates = uniqueEligibleTargets(
                    profile.snapshot.lettersByReviewPriority
                        + profile.lettersByConfidence
                        + plan.weeklyReviewLetters
                        + Array(profile.learningLetters).sorted()
                )
            }
        } else {
            assessmentTarget = nil
            assessmentBucket = nil
            reviewCandidates = eligibleTargetCandidates(profile.lettersByConfidence)
        }

        guard !reviewCandidates.isEmpty else {
            // No known letters and no focus — extremely unusual (would mean a
            // profile that finished calibration without success). Pick anything
            // from the calibration pool to avoid a deadlocked screen.
            let pool = LetterDifficulty.calibrationPool(
                for: language,
                nameLetter: profile.firstNameLetterKey
            )
            let targetCandidate = pool.randomElement() ?? "A"
            setTargetLetter(targetCandidate, profile: profile, fallbackCandidates: pool)
            let target = targetLetter
            let distractors = Array(pool.filter { $0 != target }.shuffled().prefix(optionsPerRound - 1))
            // Plain review only happens when there's no focus letter in play,
            // so isFocusTarget is always false here.
            displayedLetters = placeAnswer(target: target, distractors: distractors, isFocusTarget: false)
            return
        }
        // Bias toward weaker known letters (they need the practice).
        let weighted = plan.dailyPracticeKind == .reviewTest ? reviewCandidates : Array(reviewCandidates.reversed())
        var target = assessmentTarget ?? preferNotRecentlyTargeted(Array(weighted)) ?? reviewCandidates[0]
        if reviewCandidates.count > 1, target == previousTarget {
            target = reviewCandidates.first(where: { $0 != previousTarget }) ?? target
        }
        setTargetLetter(target, profile: profile, fallbackCandidates: reviewCandidates)
        target = targetLetter
        // Plain review only runs in no-focus / expert sessions, on letters
        // the child has already proven they know. This is exactly the
        // "later review" stage from §15, so we actively prefer confusable
        // distractors when the target is known to push purpose-built
        // discrimination training (B/D, M/W, …). Weak targets still fall
        // back to `.avoid` so we don't compound difficulty unfairly.
        let reviewPolicy: LetterDifficulty.ConfusionPolicy
        if liveDifficulty == .easierUntilStreak {
            reviewPolicy = .avoid
        } else if currentPlainReviewIntentOverride == .weeklyAssessment {
            switch assessmentBucket {
            case .fluent where profile.letterStats[target]?.isStrongKnown == true:
                reviewPolicy = .allowFluentPairs
            default:
                reviewPolicy = .avoid
            }
        } else if plan.dailyPracticeKind == .reviewTest {
            reviewPolicy = profile.letterStats[target]?.isStrongKnown == true ? .allowFluentPairs : .avoid
        } else {
            reviewPolicy = levelAdjustedPolicy(profile.knownLetters.contains(target) ? .intentionallyPractice : .avoid)
        }
        let distractors = maybeInjectCameoLetter(
            into: pickNormalDistractors(profile: profile, target: target, exclude: [], count: optionsPerRound - 1, policy: reviewPolicy),
            target: target,
            profile: profile,
            phase: .plainReview,
            confusionPolicy: reviewPolicy
        )
        displayedLetters = placeAnswer(target: target, distractors: distractors, isFocusTarget: false)
    }

    private func chooseWeeklyAssessmentTarget(profile: Profile) -> String? {
        guard let assessment = profile.activeWeeklyAssessment,
              !assessment.isCompleted else {
            return nil
        }

        let candidates = assessment.lettersNeedingEvidence()
            .filter { plan.weeklyReviewLetters.contains($0) }
        guard !candidates.isEmpty else { return nil }

        // Open the test with a confident "warm win" the first time we ask
        // anything today: a fluent (or, failing that, solid) audit letter
        // gives the kid an easy success before the cohort grind begins.
        // Only the very first round of the day gets this treatment so the
        // momentum boost lands when it matters most without skewing the
        // overall ordering.
        if profile.dailyPracticeCount() == 0 {
            let warmCandidates = candidates.filter { letter in
                let bucket = assessment.result(for: letter).bucket
                return bucket == .fluent || bucket == .solid
            }
            if let warm = preferredWarmWinLetter(from: warmCandidates, assessment: assessment) {
                return warm
            }
        }

        if let coverageTarget = assessmentCoverageDeadlineTarget(
            from: candidates,
            assessment: assessment,
            profile: profile
        ) {
            return coverageTarget
        }

        let scored = candidates
            .map { letter -> (letter: String, score: Double) in
                let result = assessment.result(for: letter)
                let remaining = max(1, result.attemptCap - result.independentAttempts)
                let misses = max(0, result.independentAttempts - result.independentCorrect)
                let recencyPenalty = recentTargetLetters.contains(letter) ? 0.7 : 0
                return (
                    letter,
                    Double(remaining)
                        + Double(misses) * 0.5
                        + assessmentBucketWeight(result.bucket)
                        + (profile.letterStats[letter]?.reviewPriority ?? 0)
                        - recencyPenalty
                )
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.letter < $1.letter
            }
            .map(\.letter)

        return preferNotRecentlyTargeted(scored) ?? scored.first
    }

    private func assessmentCoverageDeadlineTarget(
        from candidates: [String],
        assessment: WeeklyLetterAssessment,
        profile: Profile
    ) -> String? {
        let unattempted = candidates.filter { letter in
            assessment.result(for: letter).independentAttempts == 0
        }
        guard !unattempted.isEmpty else { return nil }

        let remainingPlannedSlots = max(
            0,
            assessment.assessmentRoundTarget - assessment.independentAssessmentAttempts
        )
        guard remainingPlannedSlots <= unattempted.count else { return nil }

        let ordered = unattempted.sorted { lhs, rhs in
            let leftPriority = assessmentCoveragePriority(assessment.result(for: lhs).bucket)
            let rightPriority = assessmentCoveragePriority(assessment.result(for: rhs).bucket)
            if leftPriority != rightPriority { return leftPriority < rightPriority }

            let leftReview = profile.letterStats[lhs]?.reviewPriority ?? 0
            let rightReview = profile.letterStats[rhs]?.reviewPriority ?? 0
            if leftReview != rightReview { return leftReview > rightReview }

            return lhs < rhs
        }

        return preferNotRecentlyTargeted(ordered) ?? ordered.first
    }

    /// Picks the strongest warm-up audit letter from the supplied pool:
    /// fluent beats solid, then `recentTargetLetters` is used as a tiebreak
    /// so the very first prompt isn't a letter the child just saw, then
    /// alphabetical order for determinism.
    private func preferredWarmWinLetter(
        from candidates: [String],
        assessment: WeeklyLetterAssessment
    ) -> String? {
        guard !candidates.isEmpty else { return nil }
        let recent = Set(recentTargetLetters)
        return candidates.sorted { lhs, rhs in
            let lBucket = assessment.result(for: lhs).bucket
            let rBucket = assessment.result(for: rhs).bucket
            if lBucket != rBucket {
                return lBucket == .fluent
            }
            let lRecent = recent.contains(lhs)
            let rRecent = recent.contains(rhs)
            if lRecent != rRecent {
                return !lRecent
            }
            return lhs < rhs
        }.first
    }

    private func assessmentBucketWeight(_ bucket: WeeklyAssessmentBucket) -> Double {
        switch bucket {
        case .cohort: return 1.5
        case .slipped: return 1.3
        case .emerging: return 1.1
        case .solid, .parentMarked: return 1.0
        case .fluent: return 0.9
        }
    }

    private func assessmentCoveragePriority(_ bucket: WeeklyAssessmentBucket) -> Int {
        switch bucket {
        case .cohort: return 0
        case .slipped: return 1
        case .emerging: return 2
        case .solid: return 3
        case .parentMarked: return 4
        case .fluent: return 5
        }
    }

    private func buildMaintenanceRound(profile: Profile) {
        let priorityOrder = eligibleTargetCandidates(profile.snapshot.lettersByReviewPriority)
        guard !priorityOrder.isEmpty else {
            buildPlainReviewRound(profile: profile)
            return
        }
        var target = priorityOrder.first ?? priorityOrder[0]
        if priorityOrder.count > 1, target == previousTarget {
            target = priorityOrder.first(where: { $0 != previousTarget }) ?? target
        }
        setTargetLetter(target, profile: profile, fallbackCandidates: priorityOrder)
        target = targetLetter
        let policy = levelAdjustedPolicy(.intentionallyPractice)
        let distractors = maybeInjectCameoLetter(
            into: pickNormalDistractors(
                profile: profile,
                target: target,
                exclude: [],
                count: optionsPerRound - 1,
                policy: policy
            ),
            target: target,
            profile: profile,
            phase: .maintenance,
            confusionPolicy: policy
        )
        displayedLetters = placeAnswer(target: target, distractors: distractors, isFocusTarget: false)
    }

    private func buildExtraPracticeRound(profile: Profile, target: String) {
        setTargetLetter(target, profile: profile)
        let target = targetLetter
        let basePolicy: LetterDifficulty.ConfusionPolicy = profile.knownLetters.contains(target) ? .intentionallyPractice : .avoid
        let policy = levelAdjustedPolicy(basePolicy)
        let distractors = pickNormalDistractors(
            profile: profile,
            target: target,
            exclude: [],
            count: optionsPerRound - 1,
            policy: policy
        )
        displayedLetters = placeAnswer(target: target, distractors: distractors, isFocusTarget: false)
    }

    private func buildSyllableRecognitionRound(
        profile: Profile,
        activity: LearningActivityKind = .syllableRecognition
    ) {
        let focus = profile.currentSyllableFocus
        let available = playableSyllables(profile: profile)
        let warmupPool = Array(profile.knownSyllables).filter {
            available.contains($0)
        }
        let target = focus
            ?? warmupPool.randomElement()
            ?? available.first
            ?? "MA"
        let stage = syllableDistractorStage(profile: profile, target: target)
        let distractors = SyllableCurriculum.distractors(
            for: target,
            profile: profile,
            count: max(0, optionsPerRound - 1),
            stage: stage
        ).filter { AudioService.shared.hasSyllableAssets($0, language: profile.language) }
        let fallback = available.filter { $0 != target && !distractors.contains($0) }
        let chosen = Array((distractors + fallback).prefix(max(0, optionsPerRound - 1)))
        targetLetter = target
        displayedLetters = placeAnswer(target: target, distractors: chosen, isFocusTarget: focus == target)
        currentActivityKind = activity
        let unit = SyllableCurriculum.unit(target, language: profile.language)
        let segments: [FocusTarget] = activity == .syllableBlending
            ? [unit?.consonant, unit?.vowel].compactMap { $0 }.map { .letter($0) }
            : []
        currentRound = LearningRound(
            target: .syllable(target),
            options: displayedLetters.map { .syllable($0) },
            activityKind: activity,
            segments: segments,
            expectedSequence: segments
        )
    }

    private func buildSyllableCalibrationRound(profile: Profile) {
        let available = SyllableCurriculum.calibrationTargets(profile: profile)
            .filter { AudioService.shared.hasSyllableAssets($0, language: profile.language) }
        let target = available.isEmpty
            ? "MA"
            : available[roundsThisSession % available.count]
        let distractors = SyllableCurriculum.distractors(
            for: target,
            profile: profile,
            count: max(0, optionsPerRound - 1),
            stage: .onboardingCalibration
        ).filter { AudioService.shared.hasSyllableAssets($0, language: profile.language) }
        let fallback = available.filter { $0 != target && !distractors.contains($0) }
        let chosen = Array((distractors + fallback).prefix(max(0, optionsPerRound - 1)))
        targetLetter = target
        displayedLetters = placeAnswer(target: target, distractors: chosen, isFocusTarget: false)
        currentActivityKind = .syllableCalibration
        currentRound = LearningRound(
            target: .syllable(target),
            options: displayedLetters.map { .syllable($0) },
            activityKind: .syllableCalibration
        )
    }

    private func playableSyllables(profile: Profile) -> [String] {
        guard profile.hasCompletedAlphabetForReading else { return [] }
        return SyllableCurriculum.allKeys(for: profile.language).filter {
            SyllableCurriculum.prerequisitesMet(for: $0, profile: profile)
                && AudioService.shared.hasSyllableAssets($0, language: profile.language)
        }
    }

    private func syllableDistractorStage(profile: Profile, target: String) -> SyllableCurriculum.DistractorStage {
        if liveDifficulty == .easierUntilStreak || currentRoundIsRescue {
            return .rescueEased
        }
        guard let focus = profile.currentSyllableFocus, focus == target else {
            return .reviewMaintenance
        }
        switch profile.focusActiveDays {
        case 0...1:
            return .focusDay1
        case 2:
            return .focusDay2
        default:
            return .focusDay3Plus
        }
    }

    private func buildWordReadingRound(
        profile: Profile,
        activity: LearningActivityKind = .wordReading
    ) {
        if sessionPlayableWords.isEmpty {
            sessionPlayableWords = WordCurriculum.playableWords(for: profile, audio: AudioService.shared)
        }
        let available = sessionPlayableWords.map(\.key)
        let focus = profile.currentWordFocus.flatMap { available.contains($0) ? $0 : nil }
        let nextPlayableFocus = sessionPlayableWords.first { unit in
            !profile.everMasteredWords.contains(unit.key)
                && !profile.knownWords.contains(unit.key)
        }?.key
        let target = focus
            ?? nextPlayableFocus
            ?? profile.knownWords.filter { available.contains($0) }.randomElement()
            ?? available.first
            ?? WordCurriculum.allKeys(for: profile.language).first
            ?? "MÁMA"

        if activity == .wordBuilding, let unit = WordCurriculum.unit(target, language: profile.language) {
            let distractors = SyllableCurriculum.allKeys(for: profile.language)
                .filter { !unit.syllables.contains($0) && SyllableCurriculum.prerequisitesMet(for: $0, profile: profile) }
            let options = Array((unit.syllables + distractors).prefix(optionsPerRound)).shuffled()
            targetLetter = target
            displayedLetters = options
            currentActivityKind = activity
            currentRound = LearningRound(
                target: .word(target),
                options: options.map { .syllable($0) },
                activityKind: activity,
                segments: unit.syllables.map { .syllable($0) },
                expectedSequence: unit.syllables.map { .syllable($0) }
            )
            return
        }

        let distractors = WordCurriculum.distractors(
            for: target,
            candidates: sessionPlayableWords,
            profile: profile,
            count: max(0, optionsPerRound - 1)
        )
        let fallback = available.filter { $0 != target && !distractors.contains($0) }
        let chosen = Array((distractors + fallback).prefix(max(0, optionsPerRound - 1)))
        targetLetter = target
        displayedLetters = placeAnswer(target: target, distractors: chosen, isFocusTarget: focus == target)
        currentActivityKind = activity
        currentRound = LearningRound(
            target: .word(target),
            options: displayedLetters.map { .word($0) },
            activityKind: activity,
            segments: WordCurriculum.unit(target, language: profile.language)?.syllables.map { .syllable($0) } ?? []
        )
    }

    private func shouldBuildContrastRound(profile: Profile) -> Bool {
        guard plan.dailyPracticeKind != .reviewTest,
              liveDifficulty == .normal,
              instructionalBand.confusionStage != .gentle,
              !eligibleContrastPairs(profile: profile).isEmpty else {
            return false
        }
        return Int.random(in: 1...5) == 1
    }

    private func eligibleContrastPairs(profile: Profile) -> [(target: String, confused: String)] {
        var pairs: [(target: String, confused: String)] = []
        for (targetKey, stat) in profile.letterStats where stat.targetAttempts >= 5 && LetterDifficulty.isEligibleTarget(targetKey, language: language) {
            for (otherKey, count) in stat.confusedWith where count >= 2 {
                guard let otherStat = profile.letterStats[otherKey],
                      otherStat.targetAttempts >= 5,
                      LetterDifficulty.isEligibleTarget(otherKey, language: language),
                      profile.snapshot.fluentKnownLetters.contains(targetKey),
                      profile.snapshot.fluentKnownLetters.contains(otherKey) else {
                    continue
                }
                pairs.append((target: targetKey, confused: otherKey))
            }
        }
        return pairs
    }

    private func buildContrastRound(profile: Profile) {
        guard let pair = eligibleContrastPairs(profile: profile).randomElement() else {
            buildPlainReviewRound(profile: profile)
            currentRoundIntent = governedIntent(.staleReview)
            return
        }
        teachingMode = .contrast
        effectiveScaffoldingLevel = 0
        currentRoundPhaseOverride = .contrast
        currentRoundIntent = .contrastPair
        setTargetLetter(pair.target, profile: profile, fallbackCandidates: [pair.target])
        let target = targetLetter

        let strongKnown = profile.lettersByConfidence.filter {
            $0 != target && $0 != pair.confused
        }
        let extras = pickFiltered(
            from: strongKnown,
            count: optionsPerRound - 2,
            target: target,
            profile: profile,
            policy: .intentionallyPractice,
            excludeAdditional: [pair.confused]
        )
        let distractors = [pair.confused] + extras
        displayedLetters = placeAnswer(target: target, distractors: distractors, isFocusTarget: false)
    }

    /// Build a rescue round around the queued `item`. Difficulty
    /// drives distractor selection:
    ///
    /// * `.easy` → top-confidence letters via `pickEasyDistractors`,
    ///   strict `.avoid` policy. This is the immediate retry shape:
    ///   stack the deck after a fresh miss so the child can land the
    ///   correct answer and rebuild momentum.
    /// * `.mid` → all known letters via `pickNormalDistractors`, still
    ///   `.avoid` to skip visually-confusing pairs. The 2–3 round
    ///   delay before this fires gives the child breathing room; once
    ///   it does fire, the easier-pool training-wheels are off but
    ///   we're not yet asking them to discriminate against
    ///   easily-confusable shapes.
    private func buildRescueRound(profile: Profile, item: RescueItem) {
        setTargetLetter(item.letterKey, profile: profile)
        let target = targetLetter
        let distractors: [String]
        switch item.difficulty {
        case .easy:
            distractors = pickEasyDistractors(
                profile: profile,
                target: target,
                exclude: [],
                count: optionsPerRound - 1
            )
        case .mid:
            distractors = pickNormalDistractors(
                profile: profile,
                target: target,
                exclude: [],
                count: optionsPerRound - 1,
                policy: .avoid
            )
        }
        // Rescue can hit the focus letter when it's the previous wrong target,
        // so feed `isFocusTarget` through honestly so the slot-rotation
        // rule applies.
        displayedLetters = placeAnswer(
            target: target,
            distractors: distractors,
            isFocusTarget: target == activeDrillFocus(for: profile)
        )
    }

    // MARK: - Correct-answer placement

    /// Lays out the round grid with `target` placed at a deliberately-chosen
    /// position (see `chooseCorrectPosition`). Distractors are randomly
    /// shuffled into the remaining slots.
    ///
    /// Replaces the previous `([target] + distractors).shuffled()` idiom in
    /// every round builder so we can avoid positional patterns: same slot
    /// 3× in a row, lopsided session distribution, fresh focus always
    /// landing in the same slot, etc.
    ///
    /// `isFocusTarget` should be `true` when `target` is the profile's
    /// current focus letter; this turns on the focus-position-rotation
    /// rule so a newly introduced letter doesn't keep landing in the
    /// same spot day after day.
    private func placeAnswer(
        target: String,
        distractors: [String],
        isFocusTarget: Bool
    ) -> [String] {
        let pool = Array(distractors.prefix(optionsPerRound - 1)).shuffled()
        let position = chooseCorrectPosition(isFocusTarget: isFocusTarget)
        var grid = pool
        grid.insert(target, at: min(position, grid.count))
        recordCorrectPosition(position, isFocusTarget: isFocusTarget)
        return grid
    }

    /// Picks the slot index (0..<optionsPerRound) where the correct answer
    /// will be placed for the next round.
    ///
    /// Rules, in priority order:
    ///   1. **No same correct position more than twice in a row.** If the
    ///      last two correct answers were both at slot S, exclude S.
    ///   2. **Rotate the focus-target slot.** If this round's target is
    ///      the focus letter and we have history of where focus has
    ///      landed before, exclude the most-recent focus-correct slot
    ///      so a newly introduced letter doesn't always appear in the
    ///      same place.
    ///   3. **Distribution evenness.** From the remaining legal
    ///      candidates, prefer the slot(s) with the lowest session-correct
    ///      count. Random-tiebreak among ties.
    ///
    /// We always keep at least one legal candidate by relaxing the focus
    /// rule (but never the "twice-in-a-row" rule) if needed.
    private func chooseCorrectPosition(isFocusTarget: Bool) -> Int {
        var legal = Set(0..<optionsPerRound)

        // Rule 1: forbid a third repeat.
        if recentCorrectPositions.count >= 2,
           let a = recentCorrectPositions.last,
           recentCorrectPositions[recentCorrectPositions.count - 2] == a {
            legal.remove(a)
        }

        // Rule 2: rotate fresh focus across slots.
        if isFocusTarget,
           let lastFocusPos = recentFocusCorrectPositions.last,
           legal.count > 1 {
            legal.remove(lastFocusPos)
        }

        // Rule 3: prefer least-used slot(s).
        let minCount = legal.map { sessionCorrectPositionCounts[$0] }.min() ?? 0
        let candidates = legal.filter { sessionCorrectPositionCounts[$0] == minCount }
        return candidates.randomElement() ?? Int.random(in: 0..<optionsPerRound)
    }

    /// Records the chosen correct-answer position into the rolling history
    /// and per-session histogram. Call once per round, after `placeAnswer`
    /// has decided where the correct letter went.
    private func recordCorrectPosition(_ position: Int, isFocusTarget: Bool) {
        recentCorrectPositions.append(position)
        if recentCorrectPositions.count > 2 {
            recentCorrectPositions.removeFirst(recentCorrectPositions.count - 2)
        }
        if isFocusTarget {
            recentFocusCorrectPositions.append(position)
            if recentFocusCorrectPositions.count > 1 {
                recentFocusCorrectPositions.removeFirst(recentFocusCorrectPositions.count - 1)
            }
        }
        if position >= 0 && position < sessionCorrectPositionCounts.count {
            sessionCorrectPositionCounts[position] += 1
        }
    }

    private func chooseDrillTarget(focus: String, confidence: [String]) -> String {
        let roll = Double.random(in: 0..<1)
        // Ask the focus regularly, but keep the last few targets varied so
        // daily practice feels less like the same prompt on a loop.
        let focusChance = focusTargetChance()
        let lowerConfidenceChance = liveDifficulty == .easierUntilStreak ? 0.75 : 0.85

        if roll < focusChance {
            if recentTargetLetters.contains(focus), !confidence.isEmpty {
                return preferNotRecentlyTargeted(confidence) ?? confidence.randomElement() ?? focus
            }
            return focus
        }
        // Lower-confidence known review.
        if roll < lowerConfidenceChance, !confidence.isEmpty {
            let lowerHalf = Array(confidence.suffix(max(1, confidence.count / 2)))
            return preferNotRecentlyTargeted(lowerHalf) ?? lowerHalf.randomElement() ?? focus
        }
        // 15% high-confidence known
        if !confidence.isEmpty {
            let topHalf = Array(confidence.prefix(max(1, confidence.count / 2)))
            return preferNotRecentlyTargeted(topHalf) ?? topHalf.randomElement() ?? focus
        }
        return focus
    }

    // MARK: - Distractor pickers (with fallbacks)

    private func pickEasyDistractors(
        profile: Profile,
        target: String,
        exclude: Set<String>,
        count: Int,
        policy: LetterDifficulty.ConfusionPolicy = .avoid
    ) -> [String] {
        guard count > 0 else { return [] }
        let confidence = profile.lettersByConfidence
        let topHalf = Array(confidence.prefix(max(3, confidence.count / 2)))
        let fluentKnown = profile.snapshot.fluentKnownLetters
        let fluentFirst = confidence.filter {
            fluentKnown.contains($0) && $0 != target && !exclude.contains($0)
        }
        if !fluentFirst.isEmpty {
            let fluentPicks = pickFiltered(
                from: fluentFirst,
                count: min(count, fluentFirst.count),
                target: target,
                profile: profile,
                policy: policy,
                excludeAdditional: exclude
            )
            if fluentPicks.count >= count {
                return Array(fluentPicks.prefix(count))
            }
            let fillCandidates = topHalf.filter { !fluentPicks.contains($0) }
            let fill = pickFiltered(
                from: fillCandidates,
                count: count - fluentPicks.count,
                target: target,
                profile: profile,
                policy: policy,
                excludeAdditional: exclude.union(fluentPicks)
            )
            return fluentPicks + fill
        }
        let candidates = topHalf.reduce(into: [String]()) { result, candidate in
            guard candidate != target,
                  !exclude.contains(candidate),
                  !result.contains(candidate) else {
                return
            }
            result.append(candidate)
        }
        return pickFiltered(
            from: candidates,
            count: count,
            target: target,
            profile: profile,
            policy: policy,
            excludeAdditional: exclude
        )
    }

    private func pickNormalDistractors(
        profile: Profile,
        target: String,
        exclude: Set<String>,
        count: Int,
        policy: LetterDifficulty.ConfusionPolicy = .avoid
    ) -> [String] {
        guard count > 0 else { return [] }
        let known = Array(profile.knownLetters)
        let candidates = known.filter { $0 != target && !exclude.contains($0) }
        return pickFiltered(
            from: candidates,
            count: count,
            target: target,
            profile: profile,
            policy: policy,
            excludeAdditional: exclude
        )
    }

    private func maybeInjectCameoLetter(
        into distractors: [String],
        target: String,
        profile: Profile,
        phase: RoundPhase,
        confusionPolicy: LetterDifficulty.ConfusionPolicy
    ) -> [String] {
        guard profileManager != nil,
              liveDifficulty == .normal,
              teachingMode != .remediation,
              profile.hasCameoBudget(),
              profile.knownLetters.count >= max(optionsPerRound, 5),
              !distractors.isEmpty else {
            return distractors
        }

        let focus = activeDrillFocus(for: profile)
        switch phase {
        case .drill:
            guard let focus,
                  target != focus,
                  helloFocusAwarded,
                  profile.knownLetters.contains(target),
                  distractors.contains(focus) else {
                return distractors
            }
        case .plainReview, .maintenance:
            guard focus == nil else { return distractors }
        default:
            return distractors
        }

        let replaceableIndices = distractors.indices.filter { index in
            distractors[index] != focus
        }
        guard !replaceableIndices.isEmpty else { return distractors }

        let preferredReplacementIndices: [Array<String>.Index]
        if confusionPolicy == .intentionallyPractice {
            preferredReplacementIndices = replaceableIndices.filter { index in
                !LetterDifficulty.areVisuallyConfusing(distractors[index], target)
            }
        } else {
            preferredReplacementIndices = replaceableIndices
        }
        guard let replacementIndex = (preferredReplacementIndices.last ?? replaceableIndices.last) else {
            return distractors
        }

        let shown = Set(distractors).union([target])
        let known = profile.knownLetters
        let candidates = LetterDifficulty.introductionOrder(for: language).filter { candidate in
            guard LetterDifficulty.isEligibleTarget(candidate, language: language),
                  !LetterDifficulty.isVisualOnlyDistractor(candidate),
                  !profile.introducedLetters.contains(candidate),
                  !known.contains(candidate),
                  !shown.contains(candidate),
                  !LetterDifficulty.areVisuallyConfusing(candidate, target) else {
                return false
            }
            if let focus, LetterDifficulty.areVisuallyConfusing(candidate, focus) {
                return false
            }
            if let base = LetterDifficulty.diacriticBase[candidate] {
                return known.contains(base)
            }
            return true
        }

        let nameLetters = profile.nameLetterKeys
        guard let cameo = candidates.min(by: { lhs, rhs in
            let lhsNameIndex = nameLetters.firstIndex(of: lhs) ?? Int.max
            let rhsNameIndex = nameLetters.firstIndex(of: rhs) ?? Int.max
            if lhsNameIndex != rhsNameIndex { return lhsNameIndex < rhsNameIndex }
            let lhsExposures = profile.letterStats[lhs]?.distractorExposures ?? 0
            let rhsExposures = profile.letterStats[rhs]?.distractorExposures ?? 0
            if lhsExposures != rhsExposures { return lhsExposures < rhsExposures }
            return false
        }) else {
            return distractors
        }

        var adjusted = distractors
        adjusted[replacementIndex] = cameo
        currentRoundCameoLetter = cameo
        return adjusted
    }

    private func automaticCaseDistractorPool(
        profile: Profile,
        target: String,
        exclude: Set<String>
    ) -> [String] {
        guard instructionalBand.allowsAutomaticLowercaseDistractors else { return [] }

        let knownUppercase = Set(profile.fluentKnownLetters.map {
            LetterDifficulty.uppercaseBaseKey(for: $0)
        }).intersection(language.letters)
        var candidates: Set<String> = []

        for uppercase in knownUppercase {
            candidates.insert(LetterDifficulty.lowercaseKey(for: uppercase, language: language))
        }
        if LetterDifficulty.isLowercaseKey(target) {
            let uppercase = LetterDifficulty.uppercaseBaseKey(for: target)
            if knownUppercase.contains(uppercase) {
                candidates.insert(uppercase)
            }
        }

        candidates.remove(target)
        candidates.subtract(exclude)
        return Array(candidates)
    }

    private func visualOnlyDistractorPool(
        target: String,
        exclude: Set<String>
    ) -> [String] {
        guard instructionalBand.allowsVisualOnlyDistractors else { return [] }
        return Array(LetterDifficulty.visualOnlyDistractors
            .intersection(LetterDifficulty.visualOnlyDistractors(for: target))
            .subtracting(exclude)
            .filter { $0 != target })
    }

    /// Picks `count` distinct distractors for the given `target` by walking a
    /// fixed priority hierarchy of letter tiers. Designed so sparse profiles
    /// have a fully specified, deterministic fallback chain instead of
    /// silently dipping into the full alphabet.
    ///
    /// Tier order (see `DistractorTier`):
    ///   1. `.known` — high-confidence "real" wrong answers. The caller's
    ///      `candidates` are tried first within this tier so callers can
    ///      bias toward (e.g.) top-confidence letters for easy distractors.
    ///   2. `.attempted` — letters with target attempts but not yet `isKnown`.
    ///   3. `.calibrationPool` — curated friendly set, even if not yet
    ///      formally introduced for this profile.
    ///   4. `.otherIntroduced` — anything else the child has seen at least
    ///      once (any kind of exposure).
    ///   5. `.unintroduced` — last resort; tracked as a leak. Intentional
    ///      cameo letters are injected after normal picking and do not use
    ///      this tier, so the leak audit keeps its original meaning.
    ///
    /// Sparse-pool guarantees:
    ///   * `knownLetters.count == 0` → all 3 distractors come from
    ///     `.attempted` / `.calibrationPool` / `.otherIntroduced` before
    ///     ever touching `.unintroduced`.
    ///   * `knownLetters.count == 1, 2, 3` → exhausts known first, then walks
    ///     the rest of the chain in order. Same shape as the post-calibration
    ///     happy path with the upper tier just shorter.
    ///   * If after walking the full chain we're still short, a final
    ///     visual-confusion-relaxed pass tries again. Only then can a
    ///     visually-confusable letter sneak in, and even then we prefer
    ///     introduced letters over unintroduced ones.
    ///
    /// `policy` controls how visually-confusing pairs (B/D, M/W, …) are
    /// treated relative to `target`:
    ///   * `.avoid` — strict exclusion (default; matches calibration & day-1
    ///     focus drilling behavior).
    ///   * `.allowFluentPairs` — confusable letters are admitted only
    ///     when both target and candidate are already in `fluentKnownLetters`.
    ///   * `.intentionallyPractice` — same legality as
    ///     `.allowFluentPairs`, but confusables are pulled to the front
    ///     of each tier pool so they're picked first when available.
    private func pickFiltered(
        from candidates: [String],
        count: Int,
        target: String,
        profile: Profile,
        policy: LetterDifficulty.ConfusionPolicy = .avoid,
        excludeAdditional: Set<String> = []
    ) -> [String] {
        guard count > 0 else { return [] }
        let confusing = LetterDifficulty.visuallyConfusingPairs[target] ?? []
        let specialDistractorsAllowed = policy != .avoid && liveDifficulty != .easierUntilStreak

        // Build the tier pools. Each subsequent tier subtracts everything
        // covered above it so a letter never appears in two tiers and the
        // walk visits each candidate at most once.
        let parentUnverified = profile.snapshot.parentMarkedKnownButUnverified
        let known = profile.knownLetters.subtracting(parentUnverified)
        let fluentKnown = profile.snapshot.fluentKnownLetters
        func isFluentEquivalent(_ key: String) -> Bool {
            fluentKnown.contains(key) || fluentKnown.contains(LetterDifficulty.uppercaseBaseKey(for: key))
        }
        let targetIsFluent = isFluentEquivalent(target)
        let caseVariantPool = specialDistractorsAllowed
            ? automaticCaseDistractorPool(profile: profile, target: target, exclude: excludeAdditional)
            : []
        let caseVariantSet = Set(caseVariantPool)
        let visualOnlyPool = specialDistractorsAllowed && policy == .intentionallyPractice
            ? visualOnlyDistractorPool(target: target, exclude: excludeAdditional)
            : []
        let visualOnlySet = Set(visualOnlyPool)
        let attempted = Set(profile.letterStats.compactMap { (letter, stat) -> String? in
            (stat.targetAttempts > 0
                && !known.contains(letter)
                && !caseVariantSet.contains(letter)
                && !LetterDifficulty.isVisualOnlyDistractor(letter)) ? letter : nil
        })
        let calibrationPool = Set(LetterDifficulty.calibrationPool(
                for: language,
                nameLetter: profile.firstNameLetterKey
            ))
            .subtracting(known).subtracting(attempted)
        let otherIntroduced = profile.introducedLetters
            .subtracting(known).subtracting(caseVariantSet).subtracting(attempted).subtracting(calibrationPool)
        let unintroduced = Set(language.letters)
            .subtracting(known).subtracting(attempted).subtracting(calibrationPool).subtracting(otherIntroduced)

        // Per-policy legality predicate. Returns true when `candidate` is a
        // confusable letter that the current policy is NOT willing to admit
        // (so the pass-1 filter should drop it). Non-confusables are never
        // blocked here.
        func policyBlocks(_ candidate: String) -> Bool {
            guard confusing.contains(candidate) else { return false }
            switch policy {
            case .avoid:
                return true
            case .allowFluentPairs:
                // Need BOTH sides strong before we let the discrimination
                // moment land. Otherwise the kid is just guessing between
                // two unfamiliar shapes.
                return !(targetIsFluent && isFluentEquivalent(candidate))
            case .intentionallyPractice:
                if visualOnlySet.contains(candidate) {
                    return !targetIsFluent
                }
                if instructionalBand.allowsAutomaticLowercaseDistractors,
                   caseVariantSet.contains(candidate) {
                    return false
                }
                return !(targetIsFluent && isFluentEquivalent(candidate))
            }
        }

        // Caller's preferred sub-pool (e.g. top-confidence letters) is tried
        // first within the .known tier; the rest of known fills any remainder.
        let preferredKnown = candidates.filter { known.contains($0) }
        let remainingKnown = Array(known).filter { !preferredKnown.contains($0) }

        let knownOnlyWalkOrder: [(tier: DistractorTier, pool: [String])] = [
            (.known, preferredKnown),
            (.known, remainingKnown),
        ]
        let parentMarkedWalkOrder: [(tier: DistractorTier, pool: [String])] = {
            let cautious = Array(parentUnverified
                .subtracting(excludeAdditional)
                .filter { $0 != target }
                .sorted()
                .prefix(1))
            return cautious.isEmpty ? [] : [(.known, cautious)]
        }()
        let caseVariantWalkOrder: [(tier: DistractorTier, pool: [String])] =
            caseVariantPool.isEmpty ? [] : [(.caseVariant, caseVariantPool)]
        let visualOnlyWalkOrder: [(tier: DistractorTier, pool: [String])] =
            visualOnlyPool.isEmpty ? [] : [(.visualOnly, visualOnlyPool)]
        let fullWalkOrder: [(tier: DistractorTier, pool: [String])] = knownOnlyWalkOrder + parentMarkedWalkOrder + caseVariantWalkOrder + [
            (.attempted, Array(attempted)),
            (.calibrationPool, Array(calibrationPool)),
            (.otherIntroduced, Array(otherIntroduced)),
        ] + visualOnlyWalkOrder + [
            (.unintroduced, Array(unintroduced)),
        ]
        let walkOrder = liveDifficulty == .easierUntilStreak ? knownOnlyWalkOrder : fullWalkOrder

        var picked: [String] = []
        var seen: Set<String> = Set([target]).union(excludeAdditional)
        var leakedUnintroduced = 0

        func isSimilarCandidate(_ candidate: String) -> Bool {
            confusing.contains(candidate) || visualOnlySet.contains(candidate)
        }

        if policy == .intentionallyPractice,
           Double.random(in: 0..<1) < Self.similarDistractorSeedProbability {
            let confusablePools = fullWalkOrder.map { step in
                step.pool.filter { !seen.contains($0) && isSimilarCandidate($0) && !policyBlocks($0) }
            }
            if let seeded = confusablePools.first(where: { !$0.isEmpty })?.randomElement() {
                picked.append(seeded)
                seen.insert(seeded)
            }
        }

        // Pass 1: walk all tiers with the policy-aware confusion filter
        // applied. Within each tier pool, shuffle for variety, then in
        // `.intentionallyPractice` mode pull confusable-but-allowed letters
        // to the front so they're picked first.
        for step in walkOrder {
            if picked.count >= count { break }
            var pool = step.pool.filter { !seen.contains($0) && !policyBlocks($0) }
            pool.shuffle()
            if policy == .intentionallyPractice {
                let confusables = pool.filter { isSimilarCandidate($0) }
                let rest = pool.filter { !isSimilarCandidate($0) }
                pool = confusables + rest
            }
            for l in pool {
                if picked.count >= count { break }
                picked.append(l)
                seen.insert(l)
                if step.tier == .unintroduced { leakedUnintroduced += 1 }
            }
        }

        // Pass 2: if still short, walk the same priority order again. Strict
        // Fluent-pair policies keep their legality filter even in fallback;
        // only `.avoid` relaxes so sparse profiles can still fill the grid.
        if picked.count < count {
            let relaxesPolicyInFallback = policy == .avoid
            for step in fullWalkOrder {
                if picked.count >= count { break }
                let pool = step.pool.filter {
                    !seen.contains($0)
                        && (relaxesPolicyInFallback || !policyBlocks($0))
                }
                for l in pool.shuffled() {
                    if picked.count >= count { break }
                    picked.append(l)
                    seen.insert(l)
                    if step.tier == .unintroduced { leakedUnintroduced += 1 }
                }
            }
        }

        if leakedUnintroduced > 0 {
            unintroducedExposuresThisSession += leakedUnintroduced
            #if DEBUG
            print("⚠️ Distractor selector leaked \(leakedUnintroduced) unintroduced letter(s) " +
                  "for target=\(target) (known=\(known.count), attempted=\(attempted.count))")
            #endif
        }

        return picked
    }

    // MARK: - Stamp helper

    @discardableResult
    private func awardStamp(_ stamp: DailyStamp) -> DailyStamp? {
        guard !stampsEarned.contains(stamp) else { return nil }
        stampsEarned.insert(stamp)
        return stamp
    }

    // MARK: - Tomorrow cameo helper

    private func nextUnintroducedLetter(profile: Profile) -> String? {
        let order = LetterDifficulty.introductionOrder(for: language)
        let introduced = profile.introducedLetters
        return order.first(where: { !introduced.contains($0) })
    }
}
