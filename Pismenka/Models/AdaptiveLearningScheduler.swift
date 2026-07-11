//
//  AdaptiveLearningScheduler.swift
//  Pismenka
//
//  A compact FSRS-inspired scheduler tailored to binary letter-recognition
//  answers. It deliberately uses population priors until enough independent
//  evidence exists; rescue, reveal, and impulse rounds never reach this model.
//

import Foundation

struct LetterMemoryState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var difficulty: Double
    var stabilityDays: Double
    var lapseCount: Int
    var independentReviews: Int
    var lastIndependentReviewAt: Date?
    var nextReviewAt: Date?
    var followUpAt: Date?

    init(
        version: Int = currentVersion,
        difficulty: Double = 5,
        stabilityDays: Double = 0.5,
        lapseCount: Int = 0,
        independentReviews: Int = 0,
        lastIndependentReviewAt: Date? = nil,
        nextReviewAt: Date? = nil,
        followUpAt: Date? = nil
    ) {
        self.version = version
        self.difficulty = min(10, max(1, difficulty))
        self.stabilityDays = min(365, max(0.25, stabilityDays))
        self.lapseCount = max(0, lapseCount)
        self.independentReviews = max(0, independentReviews)
        self.lastIndependentReviewAt = lastIndependentReviewAt
        self.nextReviewAt = nextReviewAt
        self.followUpAt = followUpAt
    }

    var effectiveDueAt: Date? {
        switch (nextReviewAt, followUpAt) {
        case let (review?, followUp?): return min(review, followUp)
        case let (review?, nil): return review
        case let (nil, followUp?): return followUp
        case (nil, nil): return nil
        }
    }

    func retrievability(at date: Date) -> Double {
        guard let lastIndependentReviewAt else { return 0 }
        let elapsedDays = max(0, date.timeIntervalSince(lastIndependentReviewAt) / 86_400)
        guard elapsedDays > 0 else { return 1 }
        return min(1, max(0, pow(0.9, elapsedDays / max(0.25, stabilityDays))))
    }

    func isDue(at date: Date) -> Bool {
        guard let effectiveDueAt else { return independentReviews == 0 }
        return effectiveDueAt <= date
    }

    var uncertainty: Double {
        1 / sqrt(Double(max(1, independentReviews)))
    }
}

enum AdaptiveLearningScheduler {
    static let desiredRetention = 0.90
    static let day: TimeInterval = 86_400

    static func migratedState(
        targetAttempts: Int,
        targetCorrect: Int,
        recentResults: [Bool],
        lastTestedAt: Date?
    ) -> LetterMemoryState {
        guard targetAttempts > 0 else { return LetterMemoryState() }
        let accuracy = Double(targetCorrect) / Double(max(1, targetAttempts))
        let recentAccuracy = recentResults.isEmpty
            ? accuracy
            : Double(recentResults.filter { $0 }.count) / Double(recentResults.count)
        let blended = 0.55 * recentAccuracy + 0.45 * accuracy
        let successes = max(0, targetCorrect)
        let lapses = max(0, targetAttempts - targetCorrect)
        let evidenceScale = min(1, log2(Double(successes + 1)) / 4)
        let stability = max(0.25, (0.5 + 10 * evidenceScale) * max(0.2, blended))
        let difficulty = min(10, max(1, 7.5 - 4 * blended + min(2, Double(lapses) * 0.15)))
        let due = lastTestedAt?.addingTimeInterval(stability * day)
        return LetterMemoryState(
            difficulty: difficulty,
            stabilityDays: stability,
            lapseCount: lapses,
            independentReviews: targetAttempts,
            lastIndependentReviewAt: lastTestedAt,
            nextReviewAt: due
        )
    }

    static func recording(
        _ oldState: LetterMemoryState,
        correct: Bool,
        at date: Date
    ) -> LetterMemoryState {
        var state = oldState
        let previousReviews = state.independentReviews
        let elapsedDays = state.lastIndependentReviewAt.map {
            max(0, date.timeIntervalSince($0) / day)
        } ?? .infinity
        let retrievability = state.retrievability(at: date)

        state.independentReviews += 1
        state.lastIndependentReviewAt = date

        if correct {
            state.difficulty = max(1, state.difficulty - (previousReviews < 3 ? 0.35 : 0.12))
            if previousReviews == 0 {
                state.stabilityDays = 1
            } else if elapsedDays < 0.04 {
                // Repetitions within roughly one hour are learning steps, not
                // proof that the memory survived another day.
                state.stabilityDays = min(365, max(0.5, state.stabilityDays * 1.05))
            } else {
                let difficultyFactor = max(0.25, (11 - state.difficulty) / 6)
                let spacingGain = 0.35 + 1.8 * max(0, 1 - retrievability)
                let growth = 1 + difficultyFactor * spacingGain
                state.stabilityDays = min(365, max(0.5, state.stabilityDays * growth))
            }
            state.followUpAt = nil
            state.nextReviewAt = date.addingTimeInterval(state.stabilityDays * day)
        } else {
            state.lapseCount += 1
            state.difficulty = min(10, state.difficulty + 0.8)
            state.stabilityDays = max(0.25, min(2, state.stabilityDays * 0.30))
            let tomorrow = date.addingTimeInterval(day)
            state.followUpAt = tomorrow
            state.nextReviewAt = tomorrow
        }

        return state
    }

    static func priority(
        state: LetterMemoryState,
        recentAccuracy: Double,
        at date: Date
    ) -> Double {
        let recallRisk = max(0, desiredRetention - state.retrievability(at: date)) * 5
        let weakness = max(0, 0.8 - recentAccuracy) * 2
        let lapsePressure = min(1, Double(state.lapseCount) * 0.08)
        let uncertainty = state.uncertainty * 0.35
        let overdue: Double
        if let due = state.effectiveDueAt, due <= date {
            overdue = min(3, date.timeIntervalSince(due) / day / max(0.5, state.stabilityDays))
        } else {
            overdue = 0
        }
        let explicitFollowUp = state.followUpAt.map { $0 <= date ? 2.5 : 0 } ?? 0
        return recallRisk + weakness + lapsePressure + uncertainty + overdue + explicitFollowUp
    }
}

struct LetterConfusionEvidence: Codable, Equatable {
    static let recentWindow = 12

    var opportunities: Int = 0
    var mistakes: Int = 0
    /// `true` means the child selected this distractor.
    var recentOutcomes: [Bool] = []
    var lastOpportunityAt: Date?
    var lastMistakeAt: Date?

    mutating func record(wasMistake: Bool, at date: Date = Date()) {
        opportunities += 1
        if wasMistake {
            mistakes += 1
            lastMistakeAt = date
        }
        lastOpportunityAt = date
        recentOutcomes.append(wasMistake)
        if recentOutcomes.count > Self.recentWindow {
            recentOutcomes.removeFirst(recentOutcomes.count - Self.recentWindow)
        }
    }

    var consecutiveClean: Int {
        recentOutcomes.reversed().prefix { !$0 }.count
    }

    func priority(at date: Date = Date()) -> Double {
        guard opportunities > 0 else { return 0 }
        let recentMistakes = recentOutcomes.filter { $0 }.count
        let smoothedRate = Double(recentMistakes + 1) / Double(recentOutcomes.count + 4)
        let ageDays = lastMistakeAt.map { max(0, date.timeIntervalSince($0) / 86_400) } ?? 90
        return smoothedRate * exp(-ageDays / 21)
    }

    func isActive(at date: Date = Date()) -> Bool {
        opportunities >= 3
            && mistakes >= 2
            && consecutiveClean < 5
            && priority(at: date) >= 0.10
    }
}

struct GridPerformanceStat: Codable, Equatable {
    static let recentWindow = 20

    var independentAttempts: Int = 0
    var independentCorrect: Int = 0
    var recentResults: [Bool] = []
    var lastAttemptAt: Date?

    mutating func record(correct: Bool, at date: Date = Date()) {
        independentAttempts += 1
        if correct { independentCorrect += 1 }
        recentResults.append(correct)
        if recentResults.count > Self.recentWindow {
            recentResults.removeFirst(recentResults.count - Self.recentWindow)
        }
        lastAttemptAt = date
    }

    var recentAccuracy: Double {
        guard !recentResults.isEmpty else { return 0 }
        return Double(recentResults.filter { $0 }.count) / Double(recentResults.count)
    }

    var wilsonLowerBound: Double {
        guard independentAttempts > 0 else { return 0 }
        let n = Double(independentAttempts)
        let p = Double(independentCorrect) / n
        let z = 1.282 // one-sided 80% bound: conservative without months of trials
        let denominator = 1 + z * z / n
        let center = p + z * z / (2 * n)
        let margin = z * sqrt((p * (1 - p) + z * z / (4 * n)) / n)
        return max(0, (center - margin) / denominator)
    }

    func supportsPromotion(minimumTrials: Int) -> Bool {
        independentAttempts >= minimumTrials
            && recentResults.count >= minimumTrials
            && recentAccuracy >= 0.85
            && wilsonLowerBound >= 0.70
    }

    var supportsMaintenance: Bool {
        let recent = recentResults.suffix(8)
        guard recent.count >= 6 else { return true }
        return Double(recent.filter { $0 }.count) / Double(recent.count) >= 0.75
    }
}
