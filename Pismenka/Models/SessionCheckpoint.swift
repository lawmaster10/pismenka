//
//  SessionCheckpoint.swift
//  Pismenka
//
//  Versioned, local-only resume checkpoints. These live outside the profile
//  payload so learning-data migrations stay independent from transient UI state.
//

import Foundation

enum SessionCheckpointKind: String, Codable {
    case calibration
    case game
}

struct SessionCheckpointEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = SessionCheckpointEnvelope.currentSchemaVersion
    var profileId: UUID
    var kind: SessionCheckpointKind
    var savedAt: Date
    var sessionPlan: SessionPlan?
    var calibration: CalibrationSnapshot?
    var game: GameEngineSnapshot?
}

struct CalibrationSnapshot: Codable, Equatable {
    var schedule: [String]
    var currentIndex: Int
    var displayedLetters: [String]
    var roundsAnswered: Int
    var showIntro: Bool
    var showFinale: Bool
    var advanceToNextRoundOnRestore: Bool
}

struct RescueItemSnapshot: Codable, Equatable {
    var letterKey: String
    var dueAfterRounds: Int
    var difficulty: RescueDifficulty
}

struct GameEngineSnapshot: Codable, Equatable {
    var profileId: UUID
    var plan: SessionPlan
    var savedAt: Date

    var targetLetter: String
    var displayedLetters: [String]
    var currentActivityKind: LearningActivityKind? = nil
    var currentRound: LearningRound? = nil
    var currentStreak: Int
    var sessionBestStreak: Int
    var heartsRemaining: Int
    var stampsEarned: Set<DailyStamp>
    var phase: RoundPhase
    var roundsThisSession: Int
    var roundsCorrect: Int
    var focusGraduatedThisSession: String?
    var sessionEnded: SessionEndReason?
    var didLevelUpThisSession: Bool

    var previousTarget: String?
    var practiceProgress: Double
    var totalCorrectThisSession: Int
    var warmupCorrectCount: Int
    var warmupAttemptCount: Int
    var consecutiveWarmupMisses: Int
    var helloFocusAwarded: Bool
    var seenWarmupLetters: Set<String>

    var rescueQueue: [RescueItemSnapshot]
    var currentRoundIsRescue: Bool
    var currentRescueDifficulty: RescueDifficulty?
    var currentRoundPhaseOverride: RoundPhase?
    var instructionalBand: AlphabetLevel? = nil
    var letterOptionsPerRound: Int? = nil
    var sessionPlayableWords: [WordUnit]? = nil

    var liveDifficulty: LiveDifficulty
    var recentRoundCorrectness: [Bool]
    var governorCorrectStreak: Int
    /// Number of governor downshifts currently applied (0, 1, or 2). Optional
    /// for back-compat with checkpoints written before the cascade landed —
    /// those restore as 0 (no relief) when `liveDifficulty` is `.normal`, or
    /// as 1 when the saved difficulty was eased, matching pre-cascade
    /// semantics.
    var governorEaseSteps: Int? = nil
    var governorCooldownIndependentRounds: Int? = nil
    var focusTargetAttemptsThisSession: Int
    var focusTargetCorrectThisSession: Int

    var teachingMode: FocusTeachingMode
    var effectiveScaffoldingLevel: Int
    var remediationFocusLetter: String?
    var preseededRemediationFocusLetter: String?
    var unintroducedExposuresThisSession: Int
    var cameoExposuresThisSession: Int? = nil
    var currentRoundCameoLetter: String? = nil

    var roundStartedAt: Date?
    var roundReplayCount: Int
    var currentRoundIntent: RoundIntent
    var currentRoundPlanReason: RoundPlanReason? = nil
    var secondMissedLetters: Set<String>
    var firstMissedLetters: Set<String>
    var lastMistakeType: MistakeType?
    var lastResponseTime: TimeInterval?

    var recentCorrectPositions: [Int]
    var recentFocusCorrectPositions: [Int]
    var sessionCorrectPositionCounts: [Int]
    var advanceToNextRoundOnRestore: Bool
}
