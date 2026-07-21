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
    /// Which learning layer this checkpoint belongs to. Checkpoints written
    /// before per-layer slots existed decode as `.letters`.
    var learningLayer: LearningLayer = .letters
    var savedAt: Date
    var sessionPlan: SessionPlan?
    var calibration: CalibrationSnapshot?
    var game: GameEngineSnapshot?

    init(
        schemaVersion: Int = SessionCheckpointEnvelope.currentSchemaVersion,
        profileId: UUID,
        kind: SessionCheckpointKind,
        learningLayer: LearningLayer = .letters,
        savedAt: Date,
        sessionPlan: SessionPlan? = nil,
        calibration: CalibrationSnapshot? = nil,
        game: GameEngineSnapshot? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profileId = profileId
        self.kind = kind
        self.learningLayer = learningLayer
        self.savedAt = savedAt
        self.sessionPlan = sessionPlan
        self.calibration = calibration
        self.game = game
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        kind = try c.decode(SessionCheckpointKind.self, forKey: .kind)
        learningLayer = try c.decodeIfPresent(LearningLayer.self, forKey: .learningLayer) ?? .letters
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        sessionPlan = try c.decodeIfPresent(SessionPlan.self, forKey: .sessionPlan)
        calibration = try c.decodeIfPresent(CalibrationSnapshot.self, forKey: .calibration)
        game = try c.decodeIfPresent(GameEngineSnapshot.self, forKey: .game)
    }
}

struct CalibrationSnapshot: Codable, Equatable {
    var schedule: [String]
    var currentIndex: Int
    var displayedLetters: [String]
    var roundsAnswered: Int
    var showIntro: Bool
    var showFinale: Bool
    var advanceToNextRoundOnRestore: Bool
    /// Layer the calibration ran for. Pre-layer snapshots decode as `.letters`.
    var learningLayer: LearningLayer = .letters

    private enum CodingKeys: String, CodingKey {
        case schedule, currentIndex, displayedLetters, roundsAnswered
        case showIntro, showFinale, advanceToNextRoundOnRestore, learningLayer
    }

    init(
        schedule: [String],
        currentIndex: Int,
        displayedLetters: [String],
        roundsAnswered: Int,
        showIntro: Bool,
        showFinale: Bool,
        advanceToNextRoundOnRestore: Bool,
        learningLayer: LearningLayer = .letters
    ) {
        self.schedule = schedule
        self.currentIndex = currentIndex
        self.displayedLetters = displayedLetters
        self.roundsAnswered = roundsAnswered
        self.showIntro = showIntro
        self.showFinale = showFinale
        self.advanceToNextRoundOnRestore = advanceToNextRoundOnRestore
        self.learningLayer = learningLayer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try c.decode([String].self, forKey: .schedule)
        currentIndex = try c.decode(Int.self, forKey: .currentIndex)
        displayedLetters = try c.decode([String].self, forKey: .displayedLetters)
        roundsAnswered = try c.decode(Int.self, forKey: .roundsAnswered)
        showIntro = try c.decode(Bool.self, forKey: .showIntro)
        showFinale = try c.decode(Bool.self, forKey: .showFinale)
        advanceToNextRoundOnRestore = try c.decode(Bool.self, forKey: .advanceToNextRoundOnRestore)
        learningLayer = try c.decodeIfPresent(LearningLayer.self, forKey: .learningLayer) ?? .letters
    }
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
    /// Numbers-layer band frozen at session start; `nil` for letter sessions
    /// and pre-numbers checkpoints.
    var numberBand: NumberInstructionalBand? = nil
    /// Numbers-layer grid size frozen at session start.
    var numberOptionsPerRound: Int? = nil
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
    /// Per-letter target ask counts for the current session. Used to enforce
    /// the hard "never more than 10 asks of one letter" rule on introduction
    /// days. Optional for back-compat with older checkpoints.
    var sessionTargetCounts: [String: Int]? = nil
    var advanceToNextRoundOnRestore: Bool
}
