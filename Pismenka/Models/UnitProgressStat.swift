//
//  UnitProgressStat.swift
//  Pismenka
//
//  Shared attempt/exposure aggregate for syllables and words. LetterStat stays
//  intact because letter overrides and visual-confusion rules are letter-only.
//

import Foundation

struct UnitProgressStat: Codable, Equatable {
    var recentResults: [Bool]
    var targetAttempts: Int
    var targetCorrect: Int
    var distractorExposures: Int
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var lastTestedAt: Date?
    var confusedWith: [String: Int]
    var impulsiveSelections: [String: Int]
    var promptReplayCount: Int
    var recentResponseTimes: [TimeInterval]
    var wasKnownBefore: Bool
    var demotedAt: Date?
    var parentNote: String?

    init(
        recentResults: [Bool] = [],
        targetAttempts: Int = 0,
        targetCorrect: Int = 0,
        distractorExposures: Int = 0,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        lastTestedAt: Date? = nil,
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
        self.confusedWith = confusedWith
        self.impulsiveSelections = impulsiveSelections
        self.promptReplayCount = promptReplayCount
        self.recentResponseTimes = recentResponseTimes
        self.wasKnownBefore = wasKnownBefore
        self.demotedAt = demotedAt
        self.parentNote = parentNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recentResults = try c.decodeIfPresent([Bool].self, forKey: .recentResults) ?? []
        targetAttempts = try c.decodeIfPresent(Int.self, forKey: .targetAttempts) ?? 0
        targetCorrect = try c.decodeIfPresent(Int.self, forKey: .targetCorrect) ?? 0
        distractorExposures = try c.decodeIfPresent(Int.self, forKey: .distractorExposures) ?? 0
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        lastTestedAt = try c.decodeIfPresent(Date.self, forKey: .lastTestedAt)
        confusedWith = try c.decodeIfPresent([String: Int].self, forKey: .confusedWith) ?? [:]
        impulsiveSelections = try c.decodeIfPresent([String: Int].self, forKey: .impulsiveSelections) ?? [:]
        promptReplayCount = try c.decodeIfPresent(Int.self, forKey: .promptReplayCount) ?? 0
        recentResponseTimes = try c.decodeIfPresent([TimeInterval].self, forKey: .recentResponseTimes) ?? []
        wasKnownBefore = try c.decodeIfPresent(Bool.self, forKey: .wasKnownBefore) ?? false
        demotedAt = try c.decodeIfPresent(Date.self, forKey: .demotedAt)
        parentNote = try c.decodeIfPresent(String.self, forKey: .parentNote)
    }

    mutating func recordTargetAttempt(correct: Bool, responseTime: TimeInterval? = nil, at date: Date = Date()) {
        if firstSeenAt == nil { firstSeenAt = date }
        lastSeenAt = date
        lastTestedAt = date
        recentResults.append(correct)
        if recentResults.count > 10 {
            recentResults.removeFirst(recentResults.count - 10)
        }
        targetAttempts += 1
        if correct { targetCorrect += 1 }
        if let responseTime {
            recentResponseTimes.append(max(0, responseTime))
            if recentResponseTimes.count > LetterStat.responseTimeWindow {
                recentResponseTimes.removeFirst(recentResponseTimes.count - LetterStat.responseTimeWindow)
            }
        }
    }

    mutating func recordDistractorExposure(at date: Date = Date()) {
        if firstSeenAt == nil { firstSeenAt = date }
        lastSeenAt = date
        distractorExposures += 1
    }

    mutating func recordPromptReplay() {
        promptReplayCount += 1
    }

    mutating func recordConfusion(with selectedKey: String) {
        confusedWith[selectedKey, default: 0] += 1
    }

    mutating func recordImpulsiveSelection(of selectedKey: String) {
        impulsiveSelections[selectedKey, default: 0] += 1
    }

    var accuracy: Double {
        guard targetAttempts > 0 else { return 0 }
        return Double(targetCorrect) / Double(targetAttempts)
    }

    func recentAccuracy(window: Int = 5) -> Double {
        let slice = recentResults.suffix(window)
        guard !slice.isEmpty else { return 0 }
        return Double(slice.filter { $0 }.count) / Double(slice.count)
    }

    var isKnown: Bool {
        let attempts = min(5, recentResults.count)
        guard attempts >= 3 else { return false }
        return recentAccuracy(window: 5) >= 0.8
    }

    var isStrongKnown: Bool {
        targetAttempts >= 4
            && recentAccuracy(window: 5) >= 0.8
            && evidenceStrength >= .solid
    }

    var isFluentKnown: Bool {
        isStrongKnown
            && recentResponseTimes.count >= 4
            && (medianResponseTime ?? .infinity) <= LetterStat.fastResponseCutoff
    }

    var isFocusGraduated: Bool {
        guard recentResults.count >= 8 else { return false }
        return recentResults.suffix(8).filter { $0 }.count >= 7
    }

    var isWordGraduated: Bool {
        guard recentResults.count >= 6 else { return false }
        return recentResults.suffix(6).filter { $0 }.count >= 5
    }

    var certaintyScore: Double {
        guard targetAttempts > 0 else { return 0 }
        let n = Double(targetAttempts)
        let p = Double(targetCorrect) / n
        let z = 1.96
        let denom = 1 + z * z / n
        let centre = p + z * z / (2 * n)
        let margin = z * sqrt((p * (1 - p) + z * z / (4 * n)) / n)
        return max(0, (centre - margin) / denom)
    }

    var medianResponseTime: TimeInterval? {
        guard !recentResponseTimes.isEmpty else { return nil }
        let sorted = recentResponseTimes.sorted()
        let n = sorted.count
        if n % 2 == 1 {
            return sorted[n / 2]
        }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    var evidenceStrength: EvidenceStrength {
        if targetAttempts < 4 || certaintyScore < 0.4 { return .notEnoughData }
        if certaintyScore < 0.6 { return .emerging }
        if certaintyScore < 0.8 { return .solid }
        return .strong
    }

    var reviewPriority: Double {
        let weakness = recentResults.isEmpty ? 0 : (1 - recentAccuracy(window: 5))
        let staleness: Double
        if let lastTestedAt {
            staleness = min(1.0, max(0.0, Date().timeIntervalSince(lastTestedAt) / 86_400.0 / 14.0))
        } else {
            staleness = 0
        }
        return 0.7 * weakness + 0.3 * staleness
    }
}

typealias SyllableStat = UnitProgressStat
typealias WordStat = UnitProgressStat
