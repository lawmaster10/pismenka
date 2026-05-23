//
//  LetterStat.swift
//  Pismenka
//
//  Per-letter mastery stats. Drives adaptive round selection (confidence ranking)
//  and the parent dashboard (certainty score + confidence label).
//
//  ## Target attempts vs. distractor exposures
//
//  This file enforces a strict separation between the two ways a letter can
//  appear in a round:
//
//  * **Target attempt** — the letter was the *answer* the child was asked to
//    identify. Recorded via `record(correct:asTarget: true)`. These are the
//    only events that move the recent-results window, contribute to lifetime
//    correctness, or count toward `targetAttempts`. Mastery ("isKnown",
//    "isFocusGraduated") is judged solely on these.
//
//  * **Distractor exposure** — the letter was on screen as a wrong-answer
//    option. Recorded via `record(correct:asTarget: false)`. These bump
//    `distractorExposures` and refresh `lastSeenAt` only. They never affect
//    accuracy or mastery — selecting another letter correctly is *not* a wrong
//    answer for the distractor.
//
//  This distinction is what makes the "focus letter as a clearly-wrong
//  distractor" pattern safe pedagogically: the child gets exposure to the new
//  shape, but their score on that letter is never penalized for a round in
//  which they were never asked about it.
//

import Foundation
import SwiftUI

// MARK: - Knowledge state

/// The journey state of a single letter for a single child. This is a
/// modeling-level concept, distinct from raw accuracy. It exists so the parent
/// dashboard can speak honestly:
///
/// * `2/2` from calibration → `.tentative` ("Looks familiar"), not `.known`.
/// * Repeated success in regular play upgrades `.tentative` → `.known`.
/// * The current drill letter is `.focus` regardless of accuracy.
/// * A letter that ever satisfied the strict focus-graduation rule is
///   `.mastered` for life — even if it later demotes in `recentResults`.
///
/// The resolver lives on `Profile.knowledgeState(for:)` because mastered/focus
/// state requires profile-level context.
enum LetterKnowledgeState: String, Codable, CaseIterable {
    case unseen
    case exposed
    case learning
    case tentative
    case known
    case confident
    case gettingThere
    case needsHelp
    case recentlySlipped
    case focus
    case mastered
    /// Parent has explicitly told the app "this letter is known" via an
    /// override (`LetterOverride.markedKnown`). The underlying performance
    /// data is preserved unchanged; this state only changes how the letter
    /// is labeled in the dashboard and treated by `effectiveIsKnown`. We
    /// keep this distinct from `.known` so a parent can never look at the
    /// dashboard and confuse "I marked it" with "they actually proved it."
    case markedKnown
    /// Parent has flagged this letter for retraining via
    /// `LetterOverride.reset`. The data is preserved; the letter is just
    /// excluded from `effectiveIsKnown` so it re-enters the to-be-taught
    /// pool. Distinct from `.learning` because the reset is parent-driven,
    /// not a data signal.
    case parentReset

    /// Sample-size cutoff at which a `tentative` letter is upgraded to `known`.
    /// Calibration alone won't usually hit this; regular play does within a
    /// few sessions.
    static let confidentSampleThreshold: Int = 5

    var displayLabel: String {
        switch self {
        case .unseen: return "Not seen yet"
        case .exposed: return "Just glimpsed"
        case .learning: return "Still learning"
        case .tentative: return "Looks familiar"
        case .known: return "Confident"
        case .confident: return "Confident"
        case .gettingThere: return "Getting there"
        case .needsHelp: return "Needs help"
        case .recentlySlipped: return "Recently slipped"
        case .focus: return "Practicing now"
        case .mastered: return "Mastered"
        case .markedKnown: return "Marked known by parent"
        case .parentReset: return "Reset by parent"
        }
    }

    var displayColor: Color {
        switch self {
        case .unseen, .exposed:
            return Color.gray.opacity(0.7)
        case .learning, .needsHelp:
            return Color(red: 0.95, green: 0.4, blue: 0.3)
        case .tentative, .gettingThere:
            return Color(red: 0.95, green: 0.65, blue: 0.2)
        case .known, .confident:
            return Color(red: 0.2, green: 0.65, blue: 0.3)
        case .recentlySlipped:
            return Color(red: 0.75, green: 0.45, blue: 0.85)
        case .focus:
            return Color(red: 0.9, green: 0.55, blue: 0.15)
        case .mastered:
            return Color(red: 0.85, green: 0.6, blue: 0.1)
        case .markedKnown:
            // Distinct purple/indigo so it's immediately readable as
            // "parent override" rather than a data-driven state.
            return Color(red: 0.45, green: 0.4, blue: 0.85)
        case .parentReset:
            // Soft amber — caution / retraining, not a failure state.
            return Color(red: 0.85, green: 0.55, blue: 0.2)
        }
    }
}

// MARK: - Evidence strength

enum EvidenceStrength: String, Codable, CaseIterable, Comparable {
    case notEnoughData
    case emerging
    case solid
    case strong

    private var rank: Int {
        switch self {
        case .notEnoughData: return 0
        case .emerging: return 1
        case .solid: return 2
        case .strong: return 3
        }
    }

    static func < (lhs: EvidenceStrength, rhs: EvidenceStrength) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayLabel: String {
        switch self {
        case .notEnoughData: return "Not enough data"
        case .emerging: return "Emerging"
        case .solid: return "Solid"
        case .strong: return "Strong"
        }
    }
}

// MARK: - Parent override

/// A parent-issued manual override on a single letter's knowledge state.
/// Designed so the override is a *separate, durable signal* rather than a
/// fake set of attempts injected into `LetterStat.recentResults`. This
/// preserves the integrity of the performance data — the dashboard can
/// always show what the child actually did — while still letting the
/// parent express "I know my kid; just trust me on this one."
///
/// `effectiveIsKnown` is the single read-side entry point that combines an
/// override (if any) with the data-driven `isKnown`. Game logic (warm-up
/// pool, distractor selection, focus picking, scaffolding) consumes that;
/// it never inspects the override directly.
enum LetterOverride: Codable, Equatable {
    /// Parent declares the letter known regardless of attempt history. The
    /// associated `date` is just for parent-dashboard provenance ("marked
    /// known on Apr 26") and never feeds into any algorithmic decision.
    case markedKnown(date: Date)
    /// Parent flags the letter for retraining: data stays, but the letter
    /// is treated as not-known until the override is cleared. Useful when
    /// a previously-mastered letter has stopped being recognized in real
    /// life (e.g., regression after a long break) and the parent wants to
    /// see it cycle back through the focus rotation.
    case reset(date: Date)

    /// Convenience accessor for the timestamp inside either case.
    var date: Date {
        switch self {
        case .markedKnown(let d), .reset(let d): return d
        }
    }
}

// MARK: - LetterStat

struct LetterStat: Codable, Equatable {
    /// Ring buffer of the last 8 *target* attempt outcomes (oldest first).
    /// 8 covers both the looser "isKnown" rule (last 5) and the stricter
    /// focus-graduation rule (last 8). Distractor exposures never enter here.
    var recentResults: [Bool]

    /// Number of times the child was tested on this letter (i.e. it was the
    /// target of a round). Mastery is judged on this counter, never on
    /// distractor exposures.
    var targetAttempts: Int

    /// Number of those target attempts the child got correct.
    var targetCorrect: Int

    /// Number of times the letter appeared on screen as a distractor (wrong-
    /// answer option). Tracked separately so the parent dashboard can show a
    /// "seen 12 / tested 6" split, and so distractor presence never falsifies
    /// mastery numbers.
    var distractorExposures: Int

    /// First time the child saw this letter in any way (target or distractor).
    /// Useful for the parent dashboard's "first encountered on …" copy.
    var firstSeenAt: Date?

    /// Last time the letter appeared on screen in any way. Refreshed on every
    /// target attempt *and* every distractor exposure. Used for soft staleness
    /// biasing in warm-up.
    var lastSeenAt: Date?

    /// Last time the child was actually tested on this letter (target only).
    /// Drives the recency dot on the parent dashboard and any future
    /// review-bias logic that wants to distinguish "they saw it recently" from
    /// "they were quizzed on it recently."
    var lastTestedAt: Date?

    /// Optional parent-issued override on this letter's knowledge state.
    /// `nil` means "use the data" (the default). When set, `effectiveIsKnown`
    /// short-circuits; the underlying performance fields (`recentResults`,
    /// `targetAttempts`, `targetCorrect`, `distractorExposures`, timestamps)
    /// are NEVER touched by an override — those numbers always reflect what
    /// the child actually did.
    var parentOverride: LetterOverride?

    // MARK: - Phase 1a additions
    //
    // Phase 1a (#3, #6, #7, #16, R1, R7 fixes). All new fields default to
    // empty / zero / false / nil so the tolerant `init(from:)` migration
    // can promote any older payload without synthesizing fake data.

    /// "When this letter was the target and the child tapped a different
    /// one, which letter did they tap?" — keyed by `LetterSymbol.storageKey`,
    /// value is lifetime count.
    ///
    /// Phase 1c (R7 fix): only *genuine confusions* (mistakes whose
    /// `MistakeType` is `.confusion` — i.e., the child waited long enough
    /// to be reading the prompt) are recorded here. Impulse-classified
    /// taps are routed to `impulsiveSelections` instead so this map stays
    /// a clean signal for the contrast-pair scanner (Phase 3a).
    var confusedWith: [String: Int]

    /// Same shape as `confusedWith`, but for *impulsive* taps: sub-threshold
    /// taps after the grid appeared (Phase 1b classifier). Tracked
    /// separately so impulse-prone profiles are observable without
    /// polluting the confusion signal that drives contrast rounds and
    /// dashboard "commonly confused with" badges.
    var impulsiveSelections: [String: Int]

    /// Lifetime count of times the child re-tapped the speaker / replay
    /// button while this letter was the target. Phase 4b surfaces this
    /// as a "needed to listen X times" hint; high values for a
    /// supposedly-known letter suggest auditory recognition is the
    /// weakness, not visual recognition.
    var promptReplayCount: Int

    /// Rolling window of the last 10 target-attempt response times (in
    /// seconds, from grid appearance to tap). Capped at 10 inside
    /// `recordTargetAttempt(correct:responseTime:)` (Phase 1c will start
    /// passing the time through). Used to compute `medianResponseTime`
    /// and `responseTimeBucket` without retaining a full history.
    var recentResponseTimes: [TimeInterval]

    /// `true` once this letter has *ever* been data-driven `isKnown` and
    /// then dropped back to not-known. Phase 1c sets this on the
    /// transition; cleared only by an explicit `resetLetterStats(letter:)`
    /// (which also wipes `demotedAt`). Drives the "recently slipped"
    /// chevron in Phase 4b.
    var wasKnownBefore: Bool

    /// Wall-clock moment of the most recent known→not-known demotion,
    /// or `nil` if the letter has never slipped. Co-managed with
    /// `wasKnownBefore`.
    var demotedAt: Date?

    /// Parent-written note about this letter. This is displayed in the
    /// dashboard only and never feeds the adaptive model.
    var parentNote: String?

    init(
        recentResults: [Bool] = [],
        targetAttempts: Int = 0,
        targetCorrect: Int = 0,
        distractorExposures: Int = 0,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        lastTestedAt: Date? = nil,
        parentOverride: LetterOverride? = nil,
        confusedWith: [String: Int] = [:],
        impulsiveSelections: [String: Int] = [:],
        promptReplayCount: Int = 0,
        recentResponseTimes: [TimeInterval] = [],
        wasKnownBefore: Bool = false,
        demotedAt: Date? = nil,
        parentNote: String? = nil
    ) {
        self.recentResults = recentResults
        self.targetAttempts = targetAttempts
        self.targetCorrect = targetCorrect
        self.distractorExposures = distractorExposures
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.lastTestedAt = lastTestedAt
        self.parentOverride = parentOverride
        self.confusedWith = confusedWith
        self.impulsiveSelections = impulsiveSelections
        self.promptReplayCount = promptReplayCount
        self.recentResponseTimes = recentResponseTimes
        self.wasKnownBefore = wasKnownBefore
        self.demotedAt = demotedAt
        self.parentNote = parentNote
    }

    /// Decoder tolerant of older payloads — both newer fields and renamed-from
    /// fields are accepted, so a saved profile from an earlier dev build won't
    /// fail to load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recentResults = try c.decodeIfPresent([Bool].self, forKey: .recentResults) ?? []

        // Canonical keys.
        let canonicalAttempts = try c.decodeIfPresent(Int.self, forKey: .targetAttempts)
        let canonicalCorrect = try c.decodeIfPresent(Int.self, forKey: .targetCorrect)
        let canonicalExposures = try c.decodeIfPresent(Int.self, forKey: .distractorExposures)

        // Legacy keys (pre-rename). Either source is fine; canonical wins.
        let legacyAttempts = try c.decodeIfPresent(Int.self, forKey: .lifetimeAttempts)
        let legacyCorrect = try c.decodeIfPresent(Int.self, forKey: .lifetimeCorrect)
        let legacyExposures = try c.decodeIfPresent(Int.self, forKey: .exposureCount)
        // `targetAttemptCount` was a redundant synonym for `lifetimeAttempts`
        // post-`asTarget` gating; only honor it if the canonical and legacy
        // attempts fields are both missing.
        let legacyTargetCount = try c.decodeIfPresent(Int.self, forKey: .targetAttemptCount)

        targetAttempts = canonicalAttempts ?? legacyAttempts ?? legacyTargetCount ?? 0
        targetCorrect = canonicalCorrect ?? legacyCorrect ?? 0
        distractorExposures = canonicalExposures ?? legacyExposures ?? 0

        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
            ?? c.decodeIfPresent(Date.self, forKey: .lastPracticedAt) // legacy name
        lastTestedAt = try c.decodeIfPresent(Date.self, forKey: .lastTestedAt)
        parentOverride = try c.decodeIfPresent(LetterOverride.self, forKey: .parentOverride)

        // Phase 1a additions — every one is optional so any pre-Phase-1
        // payload decodes cleanly into the canonical empty/zero/false/nil
        // defaults. From the next save onward all fields encode and the
        // schema converges.
        confusedWith = try c.decodeIfPresent([String: Int].self, forKey: .confusedWith) ?? [:]
        impulsiveSelections = try c.decodeIfPresent([String: Int].self, forKey: .impulsiveSelections) ?? [:]
        promptReplayCount = try c.decodeIfPresent(Int.self, forKey: .promptReplayCount) ?? 0
        recentResponseTimes = try c.decodeIfPresent([TimeInterval].self, forKey: .recentResponseTimes) ?? []
        wasKnownBefore = try c.decodeIfPresent(Bool.self, forKey: .wasKnownBefore) ?? false
        demotedAt = try c.decodeIfPresent(Date.self, forKey: .demotedAt)
        parentNote = try c.decodeIfPresent(String.self, forKey: .parentNote)
    }

    /// Custom encoder that writes only the canonical fields. Legacy keys
    /// (`lifetimeAttempts`, `lifetimeCorrect`, `exposureCount`,
    /// `targetAttemptCount`, `lastPracticedAt`) exist in `CodingKeys` for the
    /// read-side migration path; we never write them back.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recentResults, forKey: .recentResults)
        try c.encode(targetAttempts, forKey: .targetAttempts)
        try c.encode(targetCorrect, forKey: .targetCorrect)
        try c.encode(distractorExposures, forKey: .distractorExposures)
        try c.encodeIfPresent(firstSeenAt, forKey: .firstSeenAt)
        try c.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try c.encodeIfPresent(lastTestedAt, forKey: .lastTestedAt)
        try c.encodeIfPresent(parentOverride, forKey: .parentOverride)
        // Phase 1a additions — always written so the on-disk schema is
        // self-describing on first save after migration. Empty maps and
        // arrays encode as `{}` / `[]`, which is fine.
        try c.encode(confusedWith, forKey: .confusedWith)
        try c.encode(impulsiveSelections, forKey: .impulsiveSelections)
        try c.encode(promptReplayCount, forKey: .promptReplayCount)
        try c.encode(recentResponseTimes, forKey: .recentResponseTimes)
        try c.encode(wasKnownBefore, forKey: .wasKnownBefore)
        try c.encodeIfPresent(demotedAt, forKey: .demotedAt)
        try c.encodeIfPresent(parentNote, forKey: .parentNote)
    }

    private enum CodingKeys: String, CodingKey {
        case recentResults
        case targetAttempts, targetCorrect, distractorExposures
        case firstSeenAt, lastSeenAt, lastTestedAt
        case parentOverride
        // Phase 1a additions.
        case confusedWith, impulsiveSelections
        case promptReplayCount, recentResponseTimes
        case wasKnownBefore, demotedAt, parentNote
        // Legacy keys — decoded only so older payloads that wrote
        // `exposureCount` as a stored field (Phase 1a and earlier) can still
        // be read; we never write them back.
        case lifetimeAttempts, lifetimeCorrect, exposureCount, targetAttemptCount, lastPracticedAt
    }

    // MARK: - Recording

    /// Record a target attempt: the child was asked to identify this letter
    /// and either tapped it (correct) or tapped some other letter (incorrect).
    /// Only target attempts move `recentResults`, `targetAttempts`,
    /// `targetCorrect`, and `lastTestedAt`.
    ///
    /// `responseTime` (Phase 1a) is the seconds-elapsed from grid appearance
    /// to tap. When provided, it's appended to the rolling
    /// `recentResponseTimes` window (capped at 10). Older call sites that
    /// don't measure response time can keep using the no-arg form unchanged.
    mutating func recordTargetAttempt(
        correct: Bool,
        responseTime: TimeInterval? = nil,
        at date: Date = Date()
    ) {
        if firstSeenAt == nil { firstSeenAt = date }
        lastSeenAt = date
        lastTestedAt = date

        recentResults.append(correct)
        if recentResults.count > 8 {
            recentResults.removeFirst(recentResults.count - 8)
        }
        targetAttempts += 1
        if correct { targetCorrect += 1 }

        // Rolling 10-sample response-time window. Two cleanup rules:
        //
        //   * Sub-zero values are clamped to 0 (defensive against clock
        //     skew between grid-appearance and tap timestamps).
        //   * Values at or above `distractionResponseCutoff` are dropped
        //     entirely. They are almost certainly distraction events
        //     ("the child looked away for 8s then tapped"), not
        //     recognition latency, and keeping them would silently demote
        //     a perfectly-known letter out of the `fast` bucket and out
        //     of `isFluentKnown`. The accuracy signal is still recorded
        //     above — the answer they eventually gave still counts toward
        //     `recentResults` — but the time itself is treated as noise.
        if let rt = responseTime {
            let cleanedRT = max(0, rt)
            if cleanedRT < LetterStat.distractionResponseCutoff {
                recentResponseTimes.append(cleanedRT)
                if recentResponseTimes.count > LetterStat.responseTimeWindow {
                    recentResponseTimes.removeFirst(recentResponseTimes.count - LetterStat.responseTimeWindow)
                }
            }
        }
    }

    /// Bump the count of times the child re-tapped the speaker / replay
    /// button while this letter was the target. Phase 1c will call this
    /// once per replay tap; Phase 4b reads `promptReplayCount` for the
    /// "needed to listen X times" hint.
    mutating func recordPromptReplay() {
        promptReplayCount += 1
    }

    /// Record a confusion: this letter was the target, the child tapped a
    /// different one, and the wrong tap was *not* impulse-classified
    /// (R7 fix — impulse taps go through `recordImpulsiveSelection`
    /// instead).
    mutating func recordConfusion(with selectedKey: String) {
        confusedWith[selectedKey, default: 0] += 1
    }

    /// Record an impulsive wrong tap (sub-impulse-threshold response).
    /// Tracked separately from `confusedWith` so the contrast scanner
    /// (Phase 3a) doesn't pair letters based on impulse evidence — that
    /// would teach against a problem the child doesn't actually have.
    mutating func recordImpulsiveSelection(of selectedKey: String) {
        impulsiveSelections[selectedKey, default: 0] += 1
    }

    /// Record a distractor exposure: the letter appeared on screen as a wrong-
    /// answer option but the child was *not* asked to identify it. This bumps
    /// `distractorExposures` and refreshes `lastSeenAt` only — it never moves
    /// the recent-results window or counts as a target attempt.
    mutating func recordDistractorExposure(at date: Date = Date()) {
        if firstSeenAt == nil { firstSeenAt = date }
        lastSeenAt = date
        distractorExposures += 1
    }

    /// Backwards-compatible recorder. Existing call sites can keep using this
    /// shape; new code should prefer the explicit `recordTargetAttempt` /
    /// `recordDistractorExposure` methods.
    mutating func record(correct: Bool, asTarget: Bool, at date: Date = Date()) {
        if asTarget {
            recordTargetAttempt(correct: correct, at: date)
        } else {
            recordDistractorExposure(at: date)
        }
    }

    // MARK: - Phase 1a tunables
    //
    // Constants surfaced on the type so call sites and tests reference one
    // canonical value. Tunable in the plan's pedagogical-defaults table.

    /// Maximum number of response-time samples retained. Older samples
    /// are dropped FIFO when this is exceeded.
    static let responseTimeWindow: Int = 10

    /// Sub-1.5s median = "fast" bucket — used as a positive bonus tier in
    /// `isFluentKnown` (eligibility for the hardest distractor roles).
    static let fastResponseCutoff: TimeInterval = 1.5

    /// 1.5s ≤ median ≤ 4s = "normal" bucket; over 4s = "slow". Surfaced
    /// purely as a parent-dashboard pip (`responseTimeBucket`); never
    /// penalizes mastery or certainty.
    static let slowResponseCutoff: TimeInterval = 4.0

    /// Hard cap on how slow a recorded response can be before we treat it
    /// as a *distraction* event rather than recognition latency. A
    /// 3-year-old can take 8–20 s to tap a letter they know perfectly well
    /// (looked away, parent talking, dropped the phone). Any sample at or
    /// above this cutoff is dropped from the response-time window entirely
    /// so it cannot pollute `medianResponseTime`, `responseTimeBucket`, or
    /// any downstream fluency check.
    ///
    /// This implements the asymmetric speed rule: **fast is positive
    /// evidence; slow is no evidence**. Fast correct taps reliably mean
    /// recognition. Slow correct taps could be either real recognition or
    /// an interrupted tap, so we refuse to draw any conclusion from them.
    static let distractionResponseCutoff: TimeInterval = 5.0

    /// Saturation cap for `staleness` — letters not tested for at least
    /// this many days give the maximum staleness contribution.
    static let stalenessSaturationDays: Double = 14.0

    // MARK: - Derived metrics

    /// Lifetime accuracy ratio over *target* attempts only, in `[0, 1]`.
    /// The visible "%" on the parent dashboard.
    var accuracy: Double {
        guard targetAttempts > 0 else { return 0 }
        return Double(targetCorrect) / Double(targetAttempts)
    }

    /// Recent accuracy over the last `window` target attempts. Defaults to 5 to
    /// match the standard `isKnown` rule.
    func recentAccuracy(window: Int = 5) -> Double {
        let slice = recentResults.suffix(window)
        guard !slice.isEmpty else { return 0 }
        let correct = slice.filter { $0 }.count
        return Double(correct) / Double(slice.count)
    }

    /// Game-side ranking key used for strength ordering. Pure accuracy:
    /// recent (last 5) blended with lifetime. Response speed used to be
    /// folded in as a penalty, but that double-counted distraction noise
    /// for toddlers — a slow correct answer is still a correct answer.
    /// Speed now only ever earns a *bonus* tier via `isFluentKnown`; it
    /// never demotes a letter here or in `certaintyScore`.
    var confidenceScore: Double {
        guard targetAttempts > 0 else { return 0 }
        let recent = recentAccuracy(window: 5)
        return 0.6 * recent + 0.4 * accuracy
    }

    /// Wilson score lower bound at 95% confidence over (targetCorrect, targetAttempts).
    /// More attempts shrink the uncertainty interval, so 34/36 ranks above
    /// 1/1 even though both look like 100% on a naive accuracy reading.
    var rank: Double {
        guard targetAttempts > 0 else { return 0 }
        let n = Double(targetAttempts)
        let p = Double(targetCorrect) / n
        let z = 1.96 // 95% confidence
        let denom = 1 + z * z / n
        let centre = p + z * z / (2 * n)
        let margin = z * sqrt((p * (1 - p) + z * z / (4 * n)) / n)
        return max(0, (centre - margin) / denom)
    }

    /// Parent-facing "how sure are we they really know this?" score —
    /// pure Wilson 95% lower bound, no response-speed discount.
    ///
    /// The previous implementation multiplied by a slowness penalty so a
    /// child whose median response was > 1.5s on a letter saw their
    /// certainty silently degraded. For a 3-year-old that's wrong: slow
    /// answers are often distraction (kid looked away, parent talked
    /// nearby, dropped the phone), not weak recognition. Slow correct
    /// answers are still correct answers, and the right place to reward
    /// fluency is the additive `isFluentKnown` tier, not a subtractive
    /// discount here.
    ///
    /// Symbol counterparts (`UnitProgressStat.certaintyScore`) already
    /// computed pure Wilson; this brings letters in line with them.
    var certaintyScore: Double { rank }

    /// "Confidently knows it" by the loose review criterion: ≥ 80% over the
    /// last 5 target attempts, with a minimum of 2 attempts so we don't promote
    /// on a single lucky tap.
    ///
    /// NOTE: This is the *per-letter* signal. The app-level definition of
    /// "known letters" lives in `Profile.knownLetters`, which additionally
    /// excludes the current focus letter until it satisfies the stricter
    /// `isFocusGraduated` rule, AND respects parent overrides via
    /// `effectiveIsKnown`. Use those, not this property directly, when
    /// reasoning about review pools, warm-up, or scaffolding.
    var isKnown: Bool {
        let attempts = min(5, recentResults.count)
        guard attempts >= 2 else { return false }
        let lastFive = recentResults.suffix(5)
        let correct = lastFive.filter { $0 }.count
        return Double(correct) / Double(lastFive.count) >= 0.8
    }

    /// Strong enough evidence to use this letter in harder roles such as
    /// confusable-pair distractors or the "safe" side of a new-focus drill.
    var isStrongKnown: Bool {
        targetAttempts >= 4
            && recentAccuracy(window: 5) >= 0.8
            && evidenceStrength >= .solid
    }

    /// Automatic recognition tier. Accuracy can make a letter known; fluency
    /// additionally requires enough timing samples and consistently quick
    /// recognition, so hard distractor roles do not treat slow, effortful
    /// success the same as instant recognition.
    var isFluentKnown: Bool {
        isStrongKnown
            && recentResponseTimes.count >= 4
            && (medianResponseTime ?? .infinity) <= LetterStat.fastResponseCutoff
    }

    /// "Should the game treat this letter as known?" — the override-aware
    /// answer used by `Profile.knownLetters` and (transitively) every
    /// downstream consumer (warm-up pool, distractor selection, focus
    /// picking, scaffolding).
    ///
    /// Resolution:
    ///   * `.markedKnown` override → always `true` (parent declares).
    ///   * `.reset` override       → always `false` (parent flags retraining).
    ///   * no override             → falls through to the data-driven
    ///                               `isKnown` rule.
    ///
    /// Critically, neither override path modifies `recentResults`,
    /// `targetAttempts`, `targetCorrect`, or `distractorExposures`. The raw
    /// performance data stays honest, so the parent dashboard can always
    /// surface the underlying numbers next to the override label.
    var effectiveIsKnown: Bool {
        switch parentOverride {
        case .markedKnown: return true
        case .reset: return false
        case .none: return isKnown
        }
    }

    /// Stricter bar used to graduate the focus letter into permanent mastery:
    /// ≥ 87.5% (i.e. ≥ 7 of 8) over the last 8 target attempts.
    var isFocusGraduated: Bool {
        guard recentResults.count >= 8 else { return false }
        let lastEight = recentResults.suffix(8)
        let correct = lastEight.filter { $0 }.count
        return correct >= 7
    }

    /// Parent-dashboard label that tells the parent how much they should trust
    /// the % displayed alongside.
    var confidenceLabel: String {
        if targetAttempts == 0 { return "Not enough data" }
        let r = certaintyScore
        if r >= 0.7 { return "Strong" }
        if r >= 0.45 { return "Pretty sure" }
        if targetAttempts < 3 { return "Not enough data" }
        return "Still learning"
    }

    var evidenceStrength: EvidenceStrength {
        if targetAttempts < 4 || certaintyScore < 0.4 { return .notEnoughData }
        if certaintyScore < 0.6 { return .emerging }
        if certaintyScore < 0.8 { return .solid }
        return .strong
    }

    /// Recency dot color for the dashboard. Green = recent attempts mostly
    /// correct, amber = mixed, red = mostly wrong, gray = no recent data.
    enum RecencyState { case green, amber, red, gray }
    var recencyState: RecencyState {
        let slice = recentResults.suffix(5)
        guard !slice.isEmpty else { return .gray }
        let correct = slice.filter { $0 }.count
        if correct >= 4 { return .green }
        if correct >= 2 { return .amber }
        return .red
    }

    // MARK: - Phase 1a derived signals

    /// Median of the `recentResponseTimes` window, or `nil` if no response
    /// times have been recorded yet (older payloads, or letters that have
    /// only been seen as distractors). Median is preferred over mean
    /// because toddler taps occasionally produce spurious 30s+ outliers
    /// (a phone set down on the table) that would skew a mean badly.
    var medianResponseTime: TimeInterval? {
        guard !recentResponseTimes.isEmpty else { return nil }
        let sorted = recentResponseTimes.sorted()
        let n = sorted.count
        if n % 2 == 1 {
            return sorted[n / 2]
        }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    /// Coarse "how fast does this child recognize this letter?" label,
    /// used by the parent dashboard pip. Purely informational — the bucket
    /// drives no mastery, certainty, or review-priority decisions.
    /// Distraction-grade outliers are already filtered upstream by
    /// `recordTargetAttempt`, so this median reflects genuine recognition
    /// latency.
    var responseTimeBucket: ResponseTimeBucket {
        guard let m = medianResponseTime else { return .unknown }
        if m < LetterStat.fastResponseCutoff { return .fast }
        if m <= LetterStat.slowResponseCutoff { return .normal }
        return .slow
    }

    /// Combined "how badly do we want to revisit this letter in warm-up?"
    /// score, used by the warm-up target picker.
    ///
    /// Two signals are weighted together:
    ///
    /// | Component  | Weight | Source                                                |
    /// |------------|--------|-------------------------------------------------------|
    /// | weakness   | 0.6    | `1 - recentAccuracy(window: 5)`                        |
    /// | staleness  | 0.4    | days since `lastTestedAt`, saturating at 14 days       |
    ///
    /// Slowness used to contribute a third signal (0.2 weight), but for a
    /// distractible 3-year-old "slow on this letter" is mostly distraction
    /// noise, not weakness. Drilling a known-but-slow letter at the
    /// expense of an actually-weak letter wasted practice time. The
    /// fluency upgrade lives in `isFluentKnown` instead — fast medians
    /// earn a bonus tier, but slow medians never push warm-up priority up.
    var reviewPriority: Double {
        let recentAcc = recentAccuracy(window: 5)
        let weakness: Double = recentResults.isEmpty ? 0 : (1 - recentAcc)

        let staleness: Double
        if let last = lastTestedAt {
            let days = Date().timeIntervalSince(last) / 86_400.0
            staleness = min(1.0, max(0.0, days / LetterStat.stalenessSaturationDays))
        } else {
            staleness = 0
        }

        return 0.6 * weakness + 0.4 * staleness
    }
}

// MARK: - ResponseTimeBucket

/// Coarse classification of `LetterStat.medianResponseTime`. Used purely
/// as the parent dashboard's response-time pip; never a mastery,
/// certainty, or review-priority input. See `LetterStat`'s asymmetric
/// speed rule for the rationale.
enum ResponseTimeBucket: String, Codable, Equatable, CaseIterable {
    /// Median < `LetterStat.fastResponseCutoff` (1.5s by default).
    case fast
    /// `fastResponseCutoff <=` median `<= slowResponseCutoff` (1.5–4s).
    case normal
    /// Median > `LetterStat.slowResponseCutoff` (4s by default).
    case slow
    /// No response-time samples yet — either pre-Phase-1c data or a
    /// letter that's only been seen as a distractor.
    case unknown
}
