//
//  SkillLevel.swift
//  Pismenka
//
//  Alphabet levels and reading stages are intentionally separate. Czech
//  reading begins only after every letter has been introduced and mastered,
//  while the alphabet trophy remains its own monotonic ladder.
//

import SwiftUI

enum AlphabetLevel: String, Codable, CaseIterable, Comparable {
    case novice
    case beginner
    case intermediate
    case advanced
    case expert

    enum ConfusionStage: Equatable {
        case gentle
        case safeKnownPairs
        case intentionalPractice
        case mixedCaseReview
    }

    /// Ordinal rank, 0 (`novice`) → 4 (`expert`). Drives `Comparable` for
    /// alphabet-only trophy comparisons.
    var rank: Int {
        switch self {
        case .novice: return 0
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        case .expert: return 4
        }
    }

    static func < (lhs: AlphabetLevel, rhs: AlphabetLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Lower-bound mastered-letter count required to be at this level.
    /// `expert` is special: it requires mastery of *all* letters in the active language.
    static func from(masteredCount: Int, language: GameLanguage) -> AlphabetLevel {
        from(letterMasteredCount: masteredCount, language: language)
    }

    static func from(
        letterMasteredCount: Int,
        language: GameLanguage
    ) -> AlphabetLevel {
        let total = language.letters.count
        if letterMasteredCount >= total { return .expert }
        if letterMasteredCount >= 20 { return .advanced }
        if letterMasteredCount >= 15 { return .intermediate }
        if letterMasteredCount >= 10 { return .beginner }
        if letterMasteredCount >= 5 { return .novice }
        return .novice
    }

    /// The minimum mastered-letter count to *cross into* this level. Used to check
    /// whether a brand-new mastery just promoted the child to a higher level.
    func threshold(language: GameLanguage) -> Int {
        switch self {
        case .novice: return 5
        case .beginner: return 10
        case .intermediate: return 15
        case .advanced: return 20
        case .expert: return language.letters.count
        }
    }

    /// Display name shown on profile cards and the level-up celebration.
    var displayName: String {
        switch self {
        case .novice: return "Novice"
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        }
    }

    /// Letter-grid size based on current known alphabet letters. This is
    /// separate from the trophy level so children who already know many
    /// letters are not held to the stricter `instructionalBand` evidence gate
    /// before seeing a wider answer grid.
    ///
    /// Three intentional gates:
    ///
    ///   1. **Fractional threshold for the 8-grid.** Languages range from 26
    ///      (English) to 41 (Czech) letters; a hard `min(30, total)` cap meant
    ///      English required full mastery to reach 8 while Czech only needed
    ///      ~73%. We instead require ~85% of the alphabet (floor 20) so the
    ///      bar scales with language size.
    ///   2. **Strong-known co-requirement.** Loose `knownLetters` includes
    ///      letters at the bare 80%/min-2-attempts bar; widening the grid asks
    ///      the round generator to fill more distractor slots from a stronger
    ///      pool. Each promotion gate also checks `strongKnownLetterCount`
    ///      against a slightly lower bar so the pool is realistic.
    ///   3. **±2 between-session hysteresis.** Once a child has earned a tier,
    ///      they keep it until the relevant count drops at least 2 below the
    ///      promotion threshold. Without this, a single letter slipping in/out
    ///      of `knownLetters` would flicker whole sessions between 4-grid and
    ///      6-grid. `previousValue` is the previous session's frozen grid
    ///      size (`Profile.lastFrozenLetterOptionsPerRound`), or `nil` on a
    ///      brand-new profile.
    static func letterOptionsPerRound(
        knownLetterCount: Int,
        strongKnownLetterCount: Int,
        previousValue: Int? = nil,
        gridPerformance: [Int: GridPerformanceStat] = [:],
        language: GameLanguage
    ) -> Int {
        let eightOptionThreshold = max(20, Int(ceil(Double(language.letters.count) * 0.85)))
        let eightStrongRequirement = max(0, eightOptionThreshold - 3)
        let sixOptionThreshold = 15
        let sixStrongRequirement = 10
        let hasSixSafety = knownLetterCount >= sixOptionThreshold
            && strongKnownLetterCount >= sixStrongRequirement
        let hasEightSafety = knownLetterCount >= eightOptionThreshold
            && strongKnownLetterCount >= eightStrongRequirement

        // Promotion is earned by performance at the current tier. Alphabet
        // counts remain a pool-safety check, not the evidence of visual-search
        // ability itself.
        let raw: Int
        if hasEightSafety,
           gridPerformance[6]?.supportsPromotion(minimumTrials: 16) == true {
            raw = 8
        } else if hasSixSafety,
                  gridPerformance[4]?.supportsPromotion(minimumTrials: 12) == true {
            raw = 6
        } else {
            raw = 4
        }

        // Existing 6/8-grid profiles keep a provisional continuity window while
        // the new model collects evidence. Once enough outcomes exist, recent
        // failure can demote. Both known and strong-known evidence participate
        // in hysteresis; the old known-only hold could retain an unsafe grid.
        guard let previous = previousValue, raw < previous else { return raw }
        if previous == 8 {
            let safetyHeld = knownLetterCount >= eightOptionThreshold - 2
                && strongKnownLetterCount >= eightStrongRequirement - 2
            let performanceHeld = gridPerformance[8]?.supportsMaintenance ?? true
            if safetyHeld && performanceHeld { return 8 }
        }
        if previous >= 6 {
            let safetyHeld = knownLetterCount >= sixOptionThreshold - 2
                && strongKnownLetterCount >= sixStrongRequirement - 2
            let performanceHeld = gridPerformance[6]?.supportsMaintenance ?? true
            if safetyHeld && performanceHeld { return max(raw, 6) }
        }
        return raw
    }

    /// How assertively the adaptive game should use similar-looking options.
    var confusionStage: ConfusionStage {
        switch self {
        case .novice:
            return .gentle
        case .beginner, .intermediate:
            return .safeKnownPairs
        case .advanced:
            return .intentionalPractice
        case .expert:
            return .mixedCaseReview
        }
    }

    /// High-level players see lowercase variants automatically; parents no
    /// longer need to enable the setting before the game can mix cases.
    var allowsAutomaticLowercaseDistractors: Bool {
        self >= .advanced
    }

    /// Lowercase can become a real focus/target only after uppercase mastery.
    var allowsAutomaticLowercaseTargets: Bool {
        self >= .expert
    }

    /// Visual-only lookalikes are deliberately late-game distractors.
    var allowsVisualOnlyDistractors: Bool {
        self >= .advanced
    }

    /// Short emoji badge for compact UI placement.
    var badgeEmoji: String {
        switch self {
        case .novice: return "🌱"
        case .beginner: return "🌟"
        case .intermediate: return "🚀"
        case .advanced: return "🏆"
        case .expert: return "👑"
        }
    }

    var badgeColor: Color {
        switch self {
        case .novice: return Color(red: 0.4, green: 0.75, blue: 0.4)
        case .beginner: return Color(red: 0.95, green: 0.75, blue: 0.2)
        case .intermediate: return Color(red: 0.3, green: 0.6, blue: 0.95)
        case .advanced: return Color(red: 0.7, green: 0.4, blue: 0.95)
        case .expert: return Color(red: 0.95, green: 0.4, blue: 0.4)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case Self.novice.rawValue: self = .novice
        case Self.beginner.rawValue: self = .beginner
        case Self.intermediate.rawValue: self = .intermediate
        case Self.advanced.rawValue: self = .advanced
        case Self.expert.rawValue, "reader", "wordBuilder", "storyteller":
            self = .expert
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown alphabet level: \(raw)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ReadingStage: String, Codable, CaseIterable, Comparable {
    case none
    case cvBridge
    case syllableReader
    case wordBuilder
    case storyteller

    var rank: Int {
        switch self {
        case .none: return 0
        case .cvBridge: return 1
        case .syllableReader: return 2
        case .wordBuilder: return 3
        case .storyteller: return 4
        }
    }

    static func < (lhs: ReadingStage, rhs: ReadingStage) -> Bool {
        lhs.rank < rhs.rank
    }

    static func from(
        syllablesUnlocked: Bool,
        syllableMasteredCount: Int,
        wordMasteredCount: Int
    ) -> ReadingStage {
        if wordMasteredCount >= 20 { return .storyteller }
        if wordMasteredCount >= 5 { return .wordBuilder }
        if syllableMasteredCount >= 10 { return .syllableReader }
        if syllablesUnlocked { return .cvBridge }
        return .none
    }

    var displayName: String {
        switch self {
        case .none: return "Locked"
        case .cvBridge: return "Syllable Starter"
        case .syllableReader: return "Reader"
        case .wordBuilder: return "Word Builder"
        case .storyteller: return "Storyteller"
        }
    }

    var badgeEmoji: String {
        switch self {
        case .none: return "🔒"
        case .cvBridge: return "🔤"
        case .syllableReader: return "📖"
        case .wordBuilder: return "🧩"
        case .storyteller: return "✨"
        }
    }

    var badgeColor: Color {
        switch self {
        case .none: return .secondary
        case .cvBridge: return Color(red: 0.25, green: 0.65, blue: 0.75)
        case .syllableReader: return Color(red: 0.25, green: 0.55, blue: 0.85)
        case .wordBuilder: return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .storyteller: return Color(red: 0.95, green: 0.55, blue: 0.2)
        }
    }
}
