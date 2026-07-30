//
//  NumberInstructionalBand.swift
//  Pismenka
//
//  Numbers-layer instructional band. Drives confusion-policy stage and grid
//  freeze/clamp for number sessions — never derived from AlphabetLevel.
//

import Foundation

enum NumberInstructionalBand: String, Codable, CaseIterable, Comparable {
    case beginner
    case developing
    case strong
    case fluent

    enum ConfusionStage: Equatable {
        case gentle
        case sameOnes
        case sameTens
        case contrast
    }

    var sortOrder: Int {
        switch self {
        case .beginner: return 0
        case .developing: return 1
        case .strong: return 2
        case .fluent: return 3
        }
    }

    static func < (lhs: NumberInstructionalBand, rhs: NumberInstructionalBand) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var confusionStage: ConfusionStage {
        switch self {
        case .beginner: return .gentle
        case .developing: return .sameOnes
        case .strong: return .sameTens
        case .fluent: return .contrast
        }
    }

    var confusionPolicy: NumberDifficulty.ConfusionPolicy {
        switch confusionStage {
        case .gentle: return .avoid
        case .sameOnes: return .allowSameOnes
        case .sameTens: return .allowSameTens
        case .contrast: return .intentionallyPractice
        }
    }

    /// Derive band from introduced/known counts in the numbers curriculum.
    static func from(introducedCount: Int, knownCount: Int, strongKnownCount: Int) -> NumberInstructionalBand {
        if strongKnownCount >= 40 || knownCount >= 60 {
            return .fluent
        }
        if knownCount >= 20 || strongKnownCount >= 12 {
            return .strong
        }
        if knownCount >= 8 || introducedCount >= 22 {
            return .developing
        }
        return .beginner
    }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .developing: return "Developing"
        case .strong: return "Strong"
        case .fluent: return "Fluent"
        }
    }

    /// Number-grid size for the next session. Parallel of
    /// `AlphabetLevel.letterOptionsPerRound`: promotion is earned by grid
    /// performance at the current tier; known counts are a pool-safety check.
    static func numberOptionsPerRound(
        knownCount: Int,
        strongKnownCount: Int,
        previousValue: Int? = nil,
        gridPerformance: [Int: GridPerformanceStat] = [:]
    ) -> Int {
        let sixOptionThreshold = 12
        let sixStrongRequirement = 8
        let eightOptionThreshold = 25
        let eightStrongRequirement = 18
        let hasSixSafety = knownCount >= sixOptionThreshold
            && strongKnownCount >= sixStrongRequirement
        let hasEightSafety = knownCount >= eightOptionThreshold
            && strongKnownCount >= eightStrongRequirement

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

        guard let previous = previousValue, raw < previous else { return raw }
        if previous == 8 {
            let safetyHeld = knownCount >= eightOptionThreshold - 2
                && strongKnownCount >= eightStrongRequirement - 2
            let performanceHeld = gridPerformance[8]?.supportsMaintenance ?? true
            if safetyHeld && performanceHeld { return 8 }
        }
        if previous >= 6 {
            let safetyHeld = knownCount >= sixOptionThreshold - 2
                && strongKnownCount >= sixStrongRequirement - 2
            let performanceHeld = gridPerformance[6]?.supportsMaintenance ?? true
            if safetyHeld && performanceHeld { return max(raw, 6) }
        }
        return raw
    }
}

/// Typealias: numbers use the full LetterStat shape (FSRS, overrides, confusion).
typealias NumberStat = LetterStat

/// Weekly number assessment — same shape as letters, keyed by number strings.
typealias WeeklyNumberAssessment = WeeklyLetterAssessment
