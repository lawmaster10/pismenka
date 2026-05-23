//
//  RoundEvent.swift
//  Pismenka
//
//  Phase 0e (#14, addition A): rolling per-profile log of recent round
//  outcomes. Each `RoundEvent` is a small immutable record of "we asked
//  for X, showed [A,B,C,D], the child tapped Y, took N seconds, the
//  session governor was at Z." The parent dashboard renders the most
//  recent N entries (Phase 4b) so a parent can see what happened on the
//  last few rounds without launching the game.
//
//  Why an event log on top of `LetterStat`? `LetterStat` is the
//  *aggregate* signal (how the child does on letter X over time);
//  `RoundEvent` is the *narrative* signal (what just happened, in
//  order). They answer different questions and the dashboard wants both.
//
//  ### Pre-declared support enums
//
//  `RoundEvent` references several enums whose *behavior* (trip rules,
//  queue mechanics, etc.) lives in later phases:
//
//  | Enum                | Defined here for | Filled in by |
//  |---------------------|------------------|--------------|
//  | `RoundIntent`       | full case set    | (this phase) |
//  | `MistakeType`       | full case set    | Phase 1b classifies wrong taps |
//  | `LiveDifficulty`    | full case set    | Phase 2c trip / restore rules  |
//  | `RescueDifficulty`  | full case set    | Phase 2a rescue queue logic    |
//
//  Pre-declaring the case set here keeps the `RoundEvent` Codable shape
//  stable from day one — later phases add behavior without a schema bump.
//

import Foundation

// MARK: - RoundIntent (#14, addition A)

/// What pedagogical purpose this round was serving. Plumbed from
/// `AdaptiveGameState.currentRoundIntent` into every persisted
/// `RoundEvent` so the parent dashboard can show "we re-asked B because
/// they got it wrong last round" rather than just "round N: B."
///
/// Phase 0 ships the full case set; round generators in Phase 2/3 will
/// set the appropriate value as they generate each round. Default for
/// any not-yet-tagged round is `.warmupConfidence` (the safest neutral
/// label — confidence-building review is the always-applicable mode).
enum RoundIntent: String, Codable, Equatable, CaseIterable {
    /// Warm-up: known letters chosen to build confidence at session start.
    case warmupConfidence
    /// The current focus letter is the *target* — the child is being
    /// drilled on it.
    case focusTarget
    /// The current focus letter is showing as a *distractor* — the child
    /// shouldn't pick it. Pure exposure (Phase 1c routes this through
    /// `recordDistractorExposure`, no target-attempt accounting).
    case focusDistractorExposure
    /// Re-asking the previous target after a wrong answer. Phase 2a's
    /// rescue queue produces these.
    case rescue
    /// Letter-pair contrast mini-round: explicitly pairing a confused
    /// letter with the letter it's been confused for. Phase 3a.
    case contrastPair
    /// Reviewing a known letter that has gone stale (low recent
    /// activity). Phase 2b's `reviewPriority` raises these.
    case staleReview
    /// Weekly 50-round review/test: target is part of the frozen cohort whose
    /// independent attempts produce retained / needs-review outcomes.
    case weeklyAssessment
    /// Expert-level no-focus round; pure mixed review. Phase 3b.
    case maintenance
    /// The session difficulty governor (Phase 2c) decided to drop this
    /// round to an easier shape. Tracked separately so the dashboard can
    /// label "we made this round easier" honestly.
    case governorEase
    /// Stuck-focus remediation round (Phase 2e); reduced focus-target
    /// frequency, max scaffolding, oversized letter card.
    case remediation
    /// Parent-gated extra practice for a specific letter. Counts real answers
    /// without consuming the adaptive daily-session focus quota.
    case extraPractice
    case syllableCalibration
    case syllableFocus
    case syllableBlending
    case syllableSegmenting
    case wordFocus
    case wordReading
    case wordBuilding
}

// MARK: - MistakeType (Phase 1b — pre-declared here)

/// Classification of a wrong tap. Phase 1b populates this from
/// `AdaptiveGameState.processAnswer` using the adaptive impulse threshold;
/// Phase 1c routes the persistence-layer "should this hit recentResults?"
/// decision off it (R6 fix).
enum MistakeType: String, Codable, Equatable, CaseIterable {
    /// Real confusion: child tapped a different letter while genuinely
    /// trying to read. Counts toward `confusedWith` and `recentResults`.
    case confusion
    /// Sub-threshold tap after grid appearance. Treated as not-trying;
    /// excluded from learning signals (R7 fix). Bumps a separate
    /// `impulsiveSelections` counter so impulse-prone profiles are still
    /// observable.
    case impulsiveTap
    /// No tap arrived within the round timeout. Phase 1b will define the
    /// timeout window; persisted shape lands here so the schema is
    /// already complete.
    case timeout
    /// Default / fallback when the classifier hasn't run yet — for
    /// example, on a correct answer (no mistake to classify) or in code
    /// paths that don't have access to a response time.
    case unknown
}

// MARK: - LiveDifficulty (Phase 2c — pre-declared here)

/// Session-level difficulty governor mode. Phase 2c will define the trip
/// rules (3-of-4 wrong, hearts ≤ 2, focus accuracy < 50%) and the
/// "restored after 2 consecutive correct" recovery; until then every
/// emitted RoundEvent carries `.normal`.
enum LiveDifficulty: String, Codable, Equatable, CaseIterable {
    /// Default state: round generator runs its planned shape.
    case normal
    /// Tripped: focus-as-target frequency halved, distractor pool
    /// restricted to known letters only, rescue queue drained
    /// preferentially. Stays tripped until 2 correct in a row.
    case easierUntilStreak
}

// MARK: - RescueDifficulty (Phase 2a — pre-declared here)

/// Two-tier rescue queue difficulty — Phase 2a will populate the queue
/// itself; this enum lands now so RoundEvent's Codable shape is stable.
enum RescueDifficulty: String, Codable, Equatable, CaseIterable {
    /// Immediate retry: same target, easiest possible distractors (top
    /// 3 strong known letters).
    case easy
    /// Delayed retry 2–3 rounds later if the easy retry was also wrong.
    /// Mid-difficulty distractor pool.
    case mid
}

// MARK: - RoundPlanReason

enum RoundPrimaryGoal: String, Codable, Equatable, CaseIterable {
    case warmupConfidence
    case newFocusPractice
    case assistedRecovery
    case staleReview
    case weeklyAssessment
    case contrastPractice
    case readingBridge
    case wordReading
    case wordBuilding
    case maintenance
    case governorEase
    case extraPractice
}

enum RoundTargetSource: String, Codable, Equatable, CaseIterable {
    case currentFocus
    case knownButSlow
    case knownReview
    case weeklyAssessmentCohort
    case confusedPair
    case rescueQueue
    case bridgePrerequisite
    case playableCurriculum
    case parentPractice
}

enum RoundDistractorPolicy: String, Codable, Equatable, CaseIterable {
    case easyKnown
    case avoidConfusables
    case fluentConfusablesAllowed
    case intentionallyPracticeConfusables
    case audioPlayableOnly
    case tileAssembly
    case governorEased
}

/// Compact machine-readable "why this round exists" payload. `RoundIntent`
/// remains the parent-facing narrative label; this value is for debugging,
/// simulation tests, and future adaptive audits.
struct RoundPlanReason: Codable, Equatable {
    let primaryGoal: RoundPrimaryGoal
    let targetSource: RoundTargetSource
    let distractorPolicy: RoundDistractorPolicy
    let expectedDifficulty: Double
}

// MARK: - AttemptContext

enum AttemptContext: String, Codable, Equatable, CaseIterable {
    case independent
    case immediateRescue
    case delayedRescue
    case revealed
    case extraPractice

    var isAssistedForMastery: Bool {
        switch self {
        case .immediateRescue, .delayedRescue, .revealed:
            return true
        case .independent, .extraPractice:
            return false
        }
    }
}

// MARK: - RoundEvent

/// One round's worth of "what happened" — the narrative complement to
/// `LetterStat`'s aggregate counters.
///
/// Every field that can't be filled in honestly at the time the event
/// is appended is `Optional` rather than synthesized. The parent
/// dashboard would rather show a blank cell than a misleading one.
struct RoundEvent: Codable, Equatable {
    /// Wall-clock moment the round was answered (or timed out).
    let date: Date
    /// Target letter, in `LetterSymbol.storageKey` form.
    let target: String
    /// Typed target metadata for post-letter activities. Older letter-only
    /// events decode as nil and are treated as `.letterRecognition`.
    var unitKind: UnitKind? = nil
    var activityKind: LearningActivityKind? = nil
    /// All options shown on screen, in display order.
    let options: [String]
    /// What the child tapped. Equals `target` on a correct answer, one
    /// of the other `options` on a wrong tap.
    let selected: String
    /// Convenience flag — equals `selected == target`. Persisted as a
    /// field rather than computed-on-read so the dashboard query path
    /// doesn't have to reload `target` to check correctness.
    let wasCorrect: Bool
    /// Time from grid appearance to tap. `nil` on timeouts and on any
    /// path that didn't capture a start timestamp.
    let responseTime: TimeInterval?
    /// Which `RoundPhase` produced this round (warmup / drill / etc.).
    let phase: RoundPhase
    /// Why this round was generated (warmup confidence, focus target,
    /// rescue, contrast, etc.). See `RoundIntent`.
    let intent: RoundIntent
    /// On a wrong tap, what kind of wrong was it? `nil` on correct
    /// answers (no mistake to classify).
    let mistakeType: MistakeType?
    /// `true` if the child tapped the speaker / replay button for this
    /// round at any point.
    let didReplayPrompt: Bool
    /// How many times they replayed (≥ 0). Captured separately from
    /// `didReplayPrompt` so the dashboard can flag "they had to listen
    /// 3 times to get this one."
    let replayCount: Int
    /// `true` when the persistence layer applied an impulse-tap discount
    /// (R6 fix in Phase 1c) — the round is preserved in the log but
    /// excluded from `recentResults` / `targetAttempts`. Surfacing this
    /// in the log lets the dashboard explain "we didn't count this miss
    /// because they tapped instantly."
    let wasDiscounted: Bool
    /// Hearts remaining *after* this round. `nil` on rounds where the
    /// session-end heart accounting was indeterminate (e.g., calibration).
    let heartsAfter: Int?
    /// Session difficulty governor state at the time this round was
    /// generated. Phase 2c starts populating this; before that every
    /// event carries `.normal` or `nil` (caller's choice — both decode
    /// cleanly).
    let liveDifficulty: LiveDifficulty?
    /// `true` if this round came out of the rescue queue (Phase 2a).
    let isRescue: Bool
    /// Difficulty tier for a rescue round; `nil` when `isRescue == false`.
    let rescueDifficulty: RescueDifficulty?
    /// Attempt context controls whether a round produced independent mastery
    /// evidence. `nil` decodes as `.independent` for legacy events.
    var attemptContext: AttemptContext?
    /// Future-letter cameo shown as a distractor, if any.
    var cameoLetter: String?
    /// True when today's active focus appeared as a distractor, even if the
    /// round's primary intent was something else.
    var includedFocusAsDistractor: Bool
    /// Debug/simulation payload explaining target source, distractor policy,
    /// and rough difficulty separately from parent-facing copy.
    var planReason: RoundPlanReason?

    init(
        date: Date,
        target: String,
        unitKind: UnitKind? = nil,
        activityKind: LearningActivityKind? = nil,
        options: [String],
        selected: String,
        wasCorrect: Bool,
        responseTime: TimeInterval?,
        phase: RoundPhase,
        intent: RoundIntent,
        mistakeType: MistakeType?,
        didReplayPrompt: Bool,
        replayCount: Int,
        wasDiscounted: Bool,
        heartsAfter: Int?,
        liveDifficulty: LiveDifficulty?,
        isRescue: Bool,
        rescueDifficulty: RescueDifficulty?,
        attemptContext: AttemptContext? = nil,
        cameoLetter: String? = nil,
        includedFocusAsDistractor: Bool = false,
        planReason: RoundPlanReason? = nil
    ) {
        self.date = date
        self.target = target
        self.unitKind = unitKind
        self.activityKind = activityKind
        self.options = options
        self.selected = selected
        self.wasCorrect = wasCorrect
        self.responseTime = responseTime
        self.phase = phase
        self.intent = intent
        self.mistakeType = mistakeType
        self.didReplayPrompt = didReplayPrompt
        self.replayCount = replayCount
        self.wasDiscounted = wasDiscounted
        self.heartsAfter = heartsAfter
        self.liveDifficulty = liveDifficulty
        self.isRescue = isRescue
        self.rescueDifficulty = rescueDifficulty
        self.attemptContext = attemptContext
        self.cameoLetter = cameoLetter
        self.includedFocusAsDistractor = includedFocusAsDistractor
        self.planReason = planReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        target = try c.decode(String.self, forKey: .target)
        unitKind = try c.decodeIfPresent(UnitKind.self, forKey: .unitKind)
        activityKind = try c.decodeIfPresent(LearningActivityKind.self, forKey: .activityKind)
        options = try c.decode([String].self, forKey: .options)
        selected = try c.decode(String.self, forKey: .selected)
        wasCorrect = try c.decode(Bool.self, forKey: .wasCorrect)
        responseTime = try c.decodeIfPresent(TimeInterval.self, forKey: .responseTime)
        phase = try c.decode(RoundPhase.self, forKey: .phase)
        intent = try c.decode(RoundIntent.self, forKey: .intent)
        mistakeType = try c.decodeIfPresent(MistakeType.self, forKey: .mistakeType)
        didReplayPrompt = try c.decode(Bool.self, forKey: .didReplayPrompt)
        replayCount = try c.decode(Int.self, forKey: .replayCount)
        wasDiscounted = try c.decode(Bool.self, forKey: .wasDiscounted)
        heartsAfter = try c.decodeIfPresent(Int.self, forKey: .heartsAfter)
        liveDifficulty = try c.decodeIfPresent(LiveDifficulty.self, forKey: .liveDifficulty)
        isRescue = try c.decode(Bool.self, forKey: .isRescue)
        rescueDifficulty = try c.decodeIfPresent(RescueDifficulty.self, forKey: .rescueDifficulty)
        attemptContext = try c.decodeIfPresent(AttemptContext.self, forKey: .attemptContext)
        cameoLetter = try c.decodeIfPresent(String.self, forKey: .cameoLetter)
        includedFocusAsDistractor = try c.decodeIfPresent(Bool.self, forKey: .includedFocusAsDistractor) ?? false
        planReason = try c.decodeIfPresent(RoundPlanReason.self, forKey: .planReason)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(target, forKey: .target)
        try c.encodeIfPresent(unitKind, forKey: .unitKind)
        try c.encodeIfPresent(activityKind, forKey: .activityKind)
        try c.encode(options, forKey: .options)
        try c.encode(selected, forKey: .selected)
        try c.encode(wasCorrect, forKey: .wasCorrect)
        try c.encodeIfPresent(responseTime, forKey: .responseTime)
        try c.encode(phase, forKey: .phase)
        try c.encode(intent, forKey: .intent)
        try c.encodeIfPresent(mistakeType, forKey: .mistakeType)
        try c.encode(didReplayPrompt, forKey: .didReplayPrompt)
        try c.encode(replayCount, forKey: .replayCount)
        try c.encode(wasDiscounted, forKey: .wasDiscounted)
        try c.encodeIfPresent(heartsAfter, forKey: .heartsAfter)
        try c.encodeIfPresent(liveDifficulty, forKey: .liveDifficulty)
        try c.encode(isRescue, forKey: .isRescue)
        try c.encodeIfPresent(rescueDifficulty, forKey: .rescueDifficulty)
        try c.encodeIfPresent(attemptContext, forKey: .attemptContext)
        try c.encodeIfPresent(cameoLetter, forKey: .cameoLetter)
        try c.encode(includedFocusAsDistractor, forKey: .includedFocusAsDistractor)
        try c.encodeIfPresent(planReason, forKey: .planReason)
    }

    private enum CodingKeys: String, CodingKey {
        case date, target, unitKind, activityKind, options, selected, wasCorrect
        case responseTime, phase, intent, mistakeType, didReplayPrompt, replayCount
        case wasDiscounted, heartsAfter, liveDifficulty, isRescue, rescueDifficulty
        case attemptContext, cameoLetter, includedFocusAsDistractor, planReason
    }

    var parentExplanations: [String] {
        var notes: [String] = []
        let context = attemptContext ?? .independent

        if mistakeType == .impulsiveTap, wasDiscounted {
            notes.append("Discounted as an impulsive tap.")
        } else if context.isAssistedForMastery, wasDiscounted {
            notes.append("Helped after a miss; not counted as independent practice.")
        }

        if let cameoLetter {
            notes.append("\(cameoLetter) appeared as a preview; it didn't count as a taught letter.")
        }

        if includedFocusAsDistractor || intent == .focusDistractorExposure {
            if intent == .focusDistractorExposure {
                notes.append("Today's focus appeared as a distractor for extra exposure.")
            } else {
                notes.append("Today's focus also appeared here for extra exposure.")
            }
        }

        switch intent {
        case .contrastPair where notes.isEmpty:
            notes.append("Practiced \(target) because of a recent confusion.")
        case .weeklyAssessment where notes.isEmpty:
            notes.append("Weekly review/test evidence for \(target).")
        case .staleReview where notes.isEmpty:
            notes.append("Review of a letter that hadn't been seen in a while.")
        default:
            break
        }

        return notes
    }
}

extension RoundEvent {
    /// Maximum events retained per profile. Beyond this, the oldest
    /// event is dropped (FIFO) when a new one is appended. 200 is enough
    /// for a few weeks of normal usage and small enough that the encoded
    /// payload stays modest in `UserDefaults`.
    static let maxRetained: Int = 200
}
