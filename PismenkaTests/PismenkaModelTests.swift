import FirebaseCore
import XCTest
@testable import Pismenka

final class PismenkaModelTests: XCTestCase {
    func testGoogleServiceInfoPlistIsBundledAndMatchesApp() throws {
        let plist = try firebasePlist()
        let bundleId = try XCTUnwrap(plist["BUNDLE_ID"] as? String)
        let clientId = try XCTUnwrap(plist["CLIENT_ID"] as? String)
        let reversedClientId = try XCTUnwrap(plist["REVERSED_CLIENT_ID"] as? String)
        let projectId = try XCTUnwrap(plist["PROJECT_ID"] as? String)
        let storageBucket = try XCTUnwrap(plist["STORAGE_BUCKET"] as? String)

        XCTAssertEqual(bundleId, Bundle.main.bundleIdentifier)
        XCTAssertTrue(clientId.hasSuffix(".apps.googleusercontent.com"))
        XCTAssertFalse(reversedClientId.isEmpty)
        XCTAssertFalse(projectId.isEmpty)
        XCTAssertFalse(storageBucket.isEmpty)
    }

    func testFirebasePlistReversedClientIdIsRegisteredAsURLScheme() throws {
        let plist = try firebasePlist()
        let reversedClientId = try XCTUnwrap(plist["REVERSED_CLIENT_ID"] as? String)
        let urlTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }

        XCTAssertTrue(schemes.contains(reversedClientId))
    }

    func testFirebaseBootstrapsFromBundledPlist() {
        XCTAssertTrue(FirebaseBootstrap.configureIfPossible())
        XCTAssertNotNil(FirebaseApp.app())
        XCTAssertEqual(FirebaseApp.app()?.options.bundleID, Bundle.main.bundleIdentifier)
    }

    func testLowercaseStorageKeyRoundTrips() throws {
        let symbol = LetterSymbol.lower("A", in: .english)
        XCTAssertEqual(symbol.storageKey, "A|lower")
        XCTAssertEqual(symbol.displayText, "a")
        XCTAssertEqual(LetterSymbol.decode(storageKey: symbol.storageKey, fallbackLanguage: .english), symbol)
    }

    func testLetterPracticeSummaryAggregatesTargetAttempts() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            letterStats: [
                "A": LetterStat(targetAttempts: 3, targetCorrect: 2, distractorExposures: 5),
                "B": LetterStat(targetAttempts: 2, targetCorrect: 1),
                "C": LetterStat(distractorExposures: 4)
            ]
        )

        let summary = profile.letterPracticeSummary

        XCTAssertEqual(summary.attemptedLetterCount, 2)
        XCTAssertEqual(summary.targetAttempts, 5)
        XCTAssertEqual(summary.targetCorrect, 3)
        XCTAssertEqual(summary.accuracy, 0.6, accuracy: 0.0001)
    }

    func testSessionCheckpointRoundTrips() throws {
        let profileId = UUID()
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            mode: .extraPractice(letter: "A")
        )
        let snapshot = GameEngineSnapshot(
            profileId: profileId,
            plan: plan,
            savedAt: Date(),
            targetLetter: "A",
            displayedLetters: ["A", "B", "C", "D"],
            currentStreak: 1,
            sessionBestStreak: 1,
            heartsRemaining: 5,
            stampsEarned: [.extraPractice],
            phase: .plainReview,
            roundsThisSession: 1,
            roundsCorrect: 1,
            focusGraduatedThisSession: nil,
            sessionEnded: nil,
            didLevelUpThisSession: false,
            previousTarget: nil,
            practiceProgress: 0,
            totalCorrectThisSession: 1,
            warmupCorrectCount: 0,
            warmupAttemptCount: 0,
            consecutiveWarmupMisses: 0,
            helloFocusAwarded: false,
            seenWarmupLetters: [],
            rescueQueue: [],
            currentRoundIsRescue: false,
            currentRescueDifficulty: nil,
            currentRoundPhaseOverride: nil,
            liveDifficulty: .normal,
            recentRoundCorrectness: [true],
            governorCorrectStreak: 0,
            focusTargetAttemptsThisSession: 0,
            focusTargetCorrectThisSession: 0,
            teachingMode: .normal,
            effectiveScaffoldingLevel: 0,
            remediationFocusLetter: nil,
            preseededRemediationFocusLetter: nil,
            unintroducedExposuresThisSession: 0,
            roundStartedAt: nil,
            roundReplayCount: 0,
            currentRoundIntent: .extraPractice,
            secondMissedLetters: [],
            firstMissedLetters: [],
            lastMistakeType: nil,
            lastResponseTime: nil,
            recentCorrectPositions: [0],
            recentFocusCorrectPositions: [],
            sessionCorrectPositionCounts: [1, 0, 0, 0],
            advanceToNextRoundOnRestore: false
        )
        let envelope = SessionCheckpointEnvelope(
            profileId: profileId,
            kind: .game,
            savedAt: Date(),
            sessionPlan: plan,
            game: snapshot
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(SessionCheckpointEnvelope.self, from: data)
        XCTAssertEqual(decoded.profileId, profileId)
        XCTAssertEqual(decoded.game?.targetLetter, "A")
        XCTAssertEqual(decoded.sessionPlan, plan)
    }

    func testGameEngineSnapshotDecodesMissingInstructionalBand() throws {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .english, hasCompletedCalibration: true)
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let snapshot = gameSnapshot(profile: profile, plan: plan)
        let data = try JSONEncoder().encode(snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "instructionalBand")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(GameEngineSnapshot.self, from: legacyData)

        XCTAssertNil(decoded.instructionalBand)
        XCTAssertEqual(decoded.targetLetter, snapshot.targetLetter)
    }

    func testSessionPlanDecodesMissingDailyGoalFields() throws {
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let data = try JSONEncoder().encode(plan)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "dailyGoalTarget")
        json.removeValue(forKey: "dailyGoalStartCount")
        json.removeValue(forKey: "dailyGoalClaimedCount")
        json.removeValue(forKey: "dailyPracticeKind")
        json.removeValue(forKey: "weeklyReviewLetters")
        json.removeValue(forKey: "dailySpotlightLetter")
        json.removeValue(forKey: "introducedFocusTarget")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(SessionPlan.self, from: legacyData)

        XCTAssertEqual(decoded.dailyGoalTarget, 25)
        XCTAssertEqual(decoded.dailyGoalStartCount, 0)
        XCTAssertEqual(decoded.dailyGoalClaimedCount, 0)
        XCTAssertEqual(decoded.dailyPracticeKind, .introduction)
        XCTAssertTrue(decoded.weeklyReviewLetters.isEmpty)
        XCTAssertNil(decoded.dailySpotlightLetter)
        XCTAssertNil(decoded.introducedFocusTarget)
    }

    @MainActor
    func testPlannerAndEngineWarmupAgreeForLetterKnownCounts() {
        let language = GameLanguage.english

        for knownCount in 0...8 {
            let known = Set(language.letters.prefix(knownCount))
            let profile = Profile(
                name: "Mila",
                avatarId: .lion,
                language: language,
                letterStats: knownStats(for: known),
                hasCompletedCalibration: true,
                introducedLetters: known
            )
            let manager = ProfileManager()
            manager.profiles = [profile]

            let plan = manager.previewSessionPlan(profileId: profile.id)
            let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

            let expectedWarmup: Int
            if knownCount >= 6 { expectedWarmup = 5 }
            else if knownCount >= 4 { expectedWarmup = 3 }
            else if knownCount >= 3 { expectedWarmup = 2 }
            else { expectedWarmup = 0 }

            XCTAssertEqual(plan.warmupLength, expectedWarmup, "knownCount=\(knownCount)")
            XCTAssertEqual(state.phase == .warmup, expectedWarmup > 0, "knownCount=\(knownCount)")
        }
    }

    @MainActor
    func testReadingLayerEngineNeverStartsInWarmup() {
        let profile = Profile(
            name: "Lena",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            syllablesUnlockedAt: LocalDay.today(),
            wordsUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let syllablePlan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .syllable("MA"),
            primaryLayer: .syllables,
            activityKind: .syllableRecognition,
            focusScaffoldingLevel: 0
        )
        let wordPlan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .word("MÁMA"),
            primaryLayer: .words,
            activityKind: .wordReading,
            focusScaffoldingLevel: 0
        )

        XCTAssertEqual(AdaptiveGameState(profile: profile, plan: syllablePlan, profileManager: manager).phase, .syllableRecognition)
        XCTAssertEqual(AdaptiveGameState(profile: profile, plan: wordPlan, profileManager: manager).phase, .wordReading)
    }

    @MainActor
    func testDailyGoalRequiresTwentyFiveDailyRounds() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "A": knownStat(),
                "B": knownStat(),
                "C": knownStat(),
                "D": knownStat(),
                "E": knownStat()
            ],
            hasCompletedCalibration: true
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        state.roundsThisSession = 24
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalCount, 24)
        XCTAssertEqual(state.dailyGoalProgress, 0.96, accuracy: 0.0001)

        state.roundsThisSession = 25
        XCTAssertTrue(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalCount, 25)
        XCTAssertEqual(state.dailyGoalDisplayText, "25 / 25")
        XCTAssertEqual(state.dailyGoalProgress, 1.0, accuracy: 0.0001)

        state.roundsThisSession = 30
        XCTAssertTrue(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalCount, 25)
        XCTAssertEqual(state.dailyGoalTotalCount, 30)
        XCTAssertEqual(state.dailyGoalExtraCount, 5)
        XCTAssertEqual(state.dailyGoalDisplayText, "+5")
        XCTAssertEqual(state.claimableDailyGoalMilestone, 25)
    }

    @MainActor
    func testDailyGoalAccumulatesAcrossSameDaySessions() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 10
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(plan.dailyGoalStartCount, 10)
        state.roundsThisSession = 14
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalCount, 24)

        state.roundsThisSession = 15
        XCTAssertTrue(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalCount, 25)
        XCTAssertEqual(state.dailyGoalDisplayText, "25 / 25")

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].dailyPracticeDay, today)
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 11)
    }

    @MainActor
    func testDailyWinnerRearmsAfterAnotherGoalChunk() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 25,
            dailyPracticeWinnerClaimedDay: today,
            dailyPracticeWinnerClaimedMilestone: 25
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(plan.dailyGoalStartCount, 25)
        XCTAssertEqual(plan.dailyGoalClaimedCount, 25)
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalDisplayText, "+0")
        XCTAssertEqual(state.dailyGoalProgress, 0.0, accuracy: 0.0001)

        state.roundsThisSession = 1
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalDisplayText, "+1")
        XCTAssertEqual(state.dailyGoalProgress, 0.04, accuracy: 0.0001)

        state.roundsThisSession = 24
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalDisplayText, "+24")

        state.roundsThisSession = 25
        XCTAssertTrue(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalDisplayText, "+25")
        XCTAssertEqual(state.claimableDailyGoalMilestone, 50)
        XCTAssertEqual(state.dailyGoalProgress, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testClaimingDailyWinnerPersistsMilestoneForToday() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 30
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.claimDailyPracticeWinner(profileId: profile.id, milestone: 25)

        XCTAssertEqual(manager.profiles[0].dailyPracticeWinnerClaimedDay, today)
        XCTAssertEqual(manager.profiles[0].dailyPracticeWinnerClaimedMilestone, 25)
        XCTAssertEqual(manager.previewSessionPlan(profileId: profile.id).dailyGoalClaimedCount, 25)
    }

    @MainActor
    func testReviewTestDayUsesAdaptiveAuditGoal() {
        let today = LocalDay.today()
        let cycleStart = cycleStartForDueWeeklyReview(on: today)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C", "D", "E"]),
            hasCompletedCalibration: true,
            learningCycleStartDay: cycleStart,
            weeklyIntroducedLetters: ["A", "B", "C"],
            introducedLetters: ["A", "B", "C", "D", "E"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(plan.dailyPracticeKind, .reviewTest)
        // 3 weekly cohort × 4 + 2 fluent × 1 = 14 audit attempts, plus a
        // tenth-of-the-budget extension buffer rounds the visible goal to
        // 15 (well under the 40-round ceiling).
        XCTAssertEqual(plan.dailyGoalTarget, 15)
        XCTAssertEqual(Set(plan.weeklyReviewLetters), Set(["A", "B", "C", "D", "E"]))
        XCTAssertEqual(plan.weeklyReviewLetters.count, 5)

        state.roundsThisSession = 14
        XCTAssertFalse(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalProgress, 14.0 / 15.0, accuracy: 0.0001)

        state.roundsThisSession = 15
        XCTAssertTrue(state.hasCompletedDailyGoal)
        XCTAssertEqual(state.dailyGoalProgress, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testWeeklyCycleSchedulesSundayOrNextPlayedReviewDay() {
        let today = LocalDay.today()
        let notDueProfile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            learningCycleStartDay: today,
            weeklyIntroducedLetters: ["A", "B"]
        )
        let notDueManager = ProfileManager()
        notDueManager.profiles = [notDueProfile]

        let notDuePlan = notDueManager.previewSessionPlan(profileId: notDueProfile.id)

        XCTAssertEqual(notDuePlan.dailyPracticeKind, .introduction)
        XCTAssertEqual(notDuePlan.dailyGoalTarget, 25)

        let dueProfile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            learningCycleStartDay: cycleStartForDueWeeklyReview(on: today),
            weeklyIntroducedLetters: ["A", "B"]
        )
        let dueManager = ProfileManager()
        dueManager.profiles = [dueProfile]

        let duePlan = dueManager.previewSessionPlan(profileId: dueProfile.id)

        XCTAssertEqual(duePlan.dailyPracticeKind, .reviewTest)
        // 2 weekly letters × 4 cohort attempts hits the 8-round
        // adaptiveSessionFloor exactly.
        XCTAssertEqual(duePlan.dailyGoalTarget, 8)

        let emptyReviewProfile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            learningCycleStartDay: cycleStartForDueWeeklyReview(on: today)
        )
        let manager = ProfileManager()
        manager.profiles = [emptyReviewProfile]

        let fallbackPlan = manager.previewSessionPlan(profileId: emptyReviewProfile.id)

        XCTAssertEqual(fallbackPlan.dailyPracticeKind, .introduction)
        XCTAssertEqual(fallbackPlan.dailyGoalTarget, 25)
    }

    @MainActor
    func testReviewTestDayDoesNotIntroduceNewLetter() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C", "D"]),
            hasCompletedCalibration: true,
            currentFocusLetter: "D",
            learningCycleStartDay: cycleStartForDueWeeklyReview(on: today),
            weeklyIntroducedLetters: ["A", "B", "C"],
            introducedLetters: ["A", "B", "C", "D"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.dailyPracticeKind, .reviewTest)
        XCTAssertFalse(plan.introducedNewFocusLetter)
        XCTAssertNil(plan.focusLetter)
        XCTAssertEqual(manager.profiles[0].currentFocusLetter, "D")
        XCTAssertEqual(manager.profiles[0].introducedLetters, ["A", "B", "C", "D"])
    }

    @MainActor
    func testReviewTestCommitFreezesWeeklyAssessmentCohort() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C", "D"]),
            hasCompletedCalibration: true,
            learningCycleStartDay: cycleStartForDueWeeklyReview(on: today),
            weeklyIntroducedLetters: ["A", "B", "C"],
            introducedLetters: ["A", "B", "C", "D"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        let assessment = manager.profiles[0].activeWeeklyAssessment
        XCTAssertEqual(plan.dailyPracticeKind, .reviewTest)
        XCTAssertEqual(assessment?.startedOn, today)
        XCTAssertEqual(assessment?.strategy, .adaptiveAudit)
        XCTAssertEqual(Set(assessment?.cohortLetters ?? []), Set(["A", "B", "C", "D"]))
        XCTAssertEqual(assessment?.cohortLetters, plan.weeklyReviewLetters)
    }

    @MainActor
    func testWeeklyAssessmentRecordsOnlyIndependentEvidenceAndFinalizesAtFifty() throws {
        let today = LocalDay.today()
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B"]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 40,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .confusion,
            intent: .weeklyAssessment,
            attemptContext: .immediateRescue,
            countsTowardDailyPractice: true
        )
        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .impulsiveTap,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )

        for wasCorrect in [true, true, true, false] {
            manager.recordAnswer(
                profileId: profile.id,
                letter: "A",
                wasCorrect: wasCorrect,
                asTarget: true,
                intent: .weeklyAssessment,
                attemptContext: .independent,
                countsTowardDailyPractice: true
            )
        }
        for wasCorrect in [true, true, false, false] {
            manager.recordAnswer(
                profileId: profile.id,
                letter: "B",
                wasCorrect: wasCorrect,
                asTarget: true,
                intent: .weeklyAssessment,
                attemptContext: .independent,
                countsTowardDailyPractice: true
            )
        }

        let completed = try XCTUnwrap(manager.profiles[0].activeWeeklyAssessment)
        XCTAssertEqual(completed.completedOn, today)
        XCTAssertEqual(completed.results["A"]?.independentAttempts, 4)
        XCTAssertEqual(completed.results["A"]?.independentCorrect, 3)
        XCTAssertEqual(completed.results["B"]?.independentAttempts, 4)
        XCTAssertEqual(completed.results["B"]?.independentCorrect, 2)
        XCTAssertEqual(completed.retainedLetters, ["A"])
        XCTAssertEqual(completed.needsReviewLetters, ["B"])
        XCTAssertEqual(manager.profiles[0].recentWeeklyAssessments.last, completed)
    }

    @MainActor
    func testReviewTestPrioritizesLettersStillNeedingAssessmentEvidence() {
        let today = LocalDay.today()
        let completedA = WeeklyAssessmentLetterResult(independentAttempts: 4, independentCorrect: 4)
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B"],
            results: ["A": completedA]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C", "D"]),
            hasCompletedCalibration: true,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B", "C", "D"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            dailyGoalTarget: 50,
            dailyPracticeKind: .reviewTest,
            weeklyReviewLetters: ["A", "B"]
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.targetLetter, "B")
        XCTAssertEqual(state.currentRoundIntent, .weeklyAssessment)
    }

    @MainActor
    func testReviewTestOpensFirstRoundWithWarmFluentLetter() {
        let today = LocalDay.today()
        // Build an audit that mixes fluent letters with a brand-new cohort
        // letter. The very first round of the day should pick a fluent
        // letter so the kid gets a confident win before the cohort grind.
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B", "Z"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 6,
            dailyGoalTarget: 8,
            hardRoundCap: 8,
            results: [
                "A": WeeklyAssessmentLetterResult(bucket: .cohort),
                "B": WeeklyAssessmentLetterResult(bucket: .fluent),
                "Z": WeeklyAssessmentLetterResult(bucket: .fluent)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "Z"]),
            hasCompletedCalibration: true,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B", "Z"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            dailyGoalTarget: 8,
            dailyPracticeKind: .reviewTest,
            weeklyReviewLetters: ["A", "B", "Z"]
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.currentRoundIntent, .weeklyAssessment)
        XCTAssertTrue(["B", "Z"].contains(state.targetLetter),
                      "First round of the test should warm-win on a fluent letter, got \(state.targetLetter)")
    }

    func testAdaptiveWeeklyAssessmentBucketDecisionTable() {
        var fluent = WeeklyAssessmentLetterResult(bucket: .fluent)
        fluent.recordIndependentAttempt(wasCorrect: false, responseTime: nil)
        XCTAssertEqual(fluent.outcome, .pending)
        fluent.recordIndependentAttempt(wasCorrect: false, responseTime: nil)
        XCTAssertEqual(fluent.outcome, .watch)

        var solid = WeeklyAssessmentLetterResult(bucket: .solid)
        solid.recordIndependentAttempt(wasCorrect: false, responseTime: nil)
        XCTAssertEqual(solid.outcome, .pending)
        solid.recordIndependentAttempt(wasCorrect: true, responseTime: nil)
        XCTAssertEqual(solid.outcome, .retained)

        var emerging = WeeklyAssessmentLetterResult(bucket: .emerging)
        emerging.recordIndependentAttempt(wasCorrect: true, responseTime: nil)
        emerging.recordIndependentAttempt(wasCorrect: false, responseTime: nil)
        XCTAssertEqual(emerging.outcome, .pending)
        emerging.recordIndependentAttempt(wasCorrect: true, responseTime: nil)
        XCTAssertEqual(emerging.outcome, .retained)

        var parentMarked = WeeklyAssessmentLetterResult(bucket: .parentMarked)
        parentMarked.recordIndependentAttempt(wasCorrect: false, responseTime: nil)
        XCTAssertEqual(parentMarked.outcome, .observed)
    }

    func testCohortBorderlineMissEarnsBonusFifthAttempt() {
        var cohort = WeeklyAssessmentLetterResult(bucket: .cohort)
        for wasCorrect in [true, true, false, false] {
            cohort.recordIndependentAttempt(wasCorrect: wasCorrect, responseTime: 1.0)
        }
        // 2/4 is borderline — outcome must hold pending until the bonus
        // fifth attempt resolves the call rather than dooming the letter
        // on a single bad tap.
        XCTAssertEqual(cohort.outcome, .pending)
        XCTAssertEqual(cohort.attemptCap, 5)

        cohort.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        XCTAssertEqual(cohort.independentAttempts, 5)
        XCTAssertEqual(cohort.independentCorrect, 3)
        XCTAssertEqual(cohort.outcome, .retained)
    }

    func testCohortDecisiveFailureSkipsExtension() {
        var cohort = WeeklyAssessmentLetterResult(bucket: .cohort)
        for _ in 0..<4 {
            cohort.recordIndependentAttempt(wasCorrect: false, responseTime: 1.0)
        }
        // 0/4 is not borderline; no bonus attempt should be granted because
        // a 5th tap can't change the call.
        XCTAssertEqual(cohort.attemptCap, 4)
        XCTAssertEqual(cohort.outcome, .needsReview)
    }

    func testSlippedBorderlineMissEarnsBonusFourthAttempt() {
        var slipped = WeeklyAssessmentLetterResult(bucket: .slipped)
        for wasCorrect in [true, false, false] {
            slipped.recordIndependentAttempt(wasCorrect: wasCorrect, responseTime: 1.0)
        }
        // 1/3 is borderline — extend; 0/3 would not, 2/3 already retains.
        XCTAssertEqual(slipped.outcome, .pending)
        XCTAssertEqual(slipped.attemptCap, 4)

        slipped.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        XCTAssertEqual(slipped.independentCorrect, 2)
        XCTAssertEqual(slipped.outcome, .retained)
    }

    func testWeeklyLettersAlwaysCohortRegardlessOfMidWeekStrength() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                // "B" looks fluent on the spotlight day (8/8 quick), but the
                // Sunday test still needs to verify across-days retention.
                "B": knownStat(),
                "Z": knownStat()
            ],
            hasCompletedCalibration: true,
            weeklyIntroducedLetters: ["B"],
            introducedLetters: ["B", "Z"]
        )

        let assessment = profile.buildAdaptiveWeeklyAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today
        )

        XCTAssertEqual(assessment.results["B"]?.bucket, .cohort)
        XCTAssertEqual(assessment.results["B"]?.plannedAttempts, 4)
        // A non-weekly fluent letter still slots into the fluent bucket.
        XCTAssertEqual(assessment.results["Z"]?.bucket, .fluent)
    }

    func testAdaptiveWeeklyAssessmentPlanIncludesConfidenceBuckets() {
        let today = LocalDay.today()
        var emerging = LetterStat()
        emerging.recordTargetAttempt(correct: true, responseTime: 1.2)
        emerging.recordTargetAttempt(correct: true, responseTime: 1.1)

        var slipped = LetterStat()
        for _ in 0..<5 {
            slipped.recordTargetAttempt(correct: false, responseTime: 1.0)
        }
        slipped.wasKnownBefore = true

        var parentMarked = LetterStat()
        parentMarked.parentOverride = .markedKnown(date: Date())

        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "F": knownStat(),
                "E": emerging,
                "S": slipped,
                "P": parentMarked
            ],
            hasCompletedCalibration: true,
            weeklyIntroducedLetters: ["C"],
            everMasteredLetters: ["S"],
            introducedLetters: ["C", "E", "F", "P", "S"]
        )

        let assessment = profile.buildAdaptiveWeeklyAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today
        )

        XCTAssertEqual(assessment.strategy, .adaptiveAudit)
        // Buckets contribute 4 + 3 + 1 + 1 + 3 = 12 audit attempts and a
        // 1-round extension buffer (≤ 12/10), so the visible goal lands at
        // 13 — comfortably below the 40-round comfort target.
        XCTAssertEqual(assessment.dailyGoalTarget, 13)
        XCTAssertEqual(assessment.results["C"]?.bucket, .cohort)
        XCTAssertEqual(assessment.results["E"]?.bucket, .emerging)
        XCTAssertEqual(assessment.results["E"]?.plannedAttempts, 3)
        XCTAssertEqual(assessment.results["F"]?.bucket, .fluent)
        XCTAssertEqual(assessment.results["P"]?.bucket, .parentMarked)
        XCTAssertEqual(assessment.results["S"]?.bucket, .slipped)
    }

    func testAdaptiveAssessmentIncludesTargetIntroducedWeakLettersButNotDistractorOnlyExposures() {
        let today = LocalDay.today()
        var weakTarget = LetterStat()
        weakTarget.recordTargetAttempt(correct: false, responseTime: 1.2)

        var distractorOnly = LetterStat()
        distractorOnly.recordDistractorExposure()

        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "E": weakTarget,
                "Z": distractorOnly
            ],
            hasCompletedCalibration: true,
            weeklyIntroducedLetters: ["A", "B"],
            introducedLetters: ["E"]
        )

        let assessment = profile.buildAdaptiveWeeklyAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today
        )

        XCTAssertEqual(assessment.results["E"]?.bucket, .emerging)
        XCTAssertEqual(assessment.results["E"]?.plannedAttempts, 3)
        XCTAssertNil(assessment.results["Z"])
        XCTAssertFalse(assessment.cohortLetters.contains("Z"))
    }

    func testAdaptiveAssessmentCapsQuestionCountAtForty() {
        let today = LocalDay.today()
        let allLetters = Set(GameLanguage.czech.letters)
        let weeklyLetters = Set(GameLanguage.czech.letters.prefix(2))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            letterStats: knownStats(for: allLetters),
            hasCompletedCalibration: true,
            weeklyIntroducedLetters: weeklyLetters,
            introducedLetters: allLetters
        )

        let assessment = profile.buildAdaptiveWeeklyAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today
        )

        XCTAssertTrue(weeklyLetters.isSubset(of: Set(assessment.cohortLetters)))
        XCTAssertLessThan(assessment.cohortLetters.count, allLetters.count)
        XCTAssertLessThanOrEqual(assessment.assessmentRoundTarget, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(assessment.dailyGoalTarget, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(assessment.hardRoundCap, WeeklyLetterAssessment.adaptiveSessionCeiling)
    }

    @MainActor
    func testUnfinishedWeeklyAssessmentContinuesProgressAcrossDays() {
        let today = LocalDay.today()
        let yesterday = today.adding(days: -1)
        var retainedA = WeeklyAssessmentLetterResult(bucket: .cohort)
        for _ in 0..<4 {
            retainedA.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        }
        var partialB = WeeklyAssessmentLetterResult(bucket: .cohort)
        for _ in 0..<2 {
            partialB.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        }
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: yesterday),
            startedOn: yesterday,
            cohortLetters: ["A", "B", "C"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 12,
            dailyGoalTarget: 13,
            hardRoundCap: 13,
            results: [
                "A": retainedA,
                "B": partialB,
                "C": WeeklyAssessmentLetterResult(bucket: .cohort)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: yesterday,
            dailyPracticeAttempts: 20,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B", "C"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.dailyPracticeKind, .reviewTest)
        XCTAssertEqual(plan.dailyGoalStartCount, 6)
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.startedOn, yesterday)
        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment?.completedOn)
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.results["B"]?.independentAttempts, 2)
    }

    @MainActor
    func testExistingOversizedWeeklyAssessmentIsCappedWithoutLosingProgress() {
        let today = LocalDay.today()
        let yesterday = today.adding(days: -1)
        let letters = Array(GameLanguage.english.letters.prefix(16))
        var attemptedA = WeeklyAssessmentLetterResult(bucket: .cohort)
        for _ in 0..<4 {
            attemptedA.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        }
        var attemptedB = WeeklyAssessmentLetterResult(bucket: .cohort)
        attemptedB.recordIndependentAttempt(wasCorrect: false, responseTime: 1.0)
        var results = Dictionary(uniqueKeysWithValues: letters.map {
            ($0, WeeklyAssessmentLetterResult(bucket: .cohort))
        })
        results["A"] = attemptedA
        results["B"] = attemptedB
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: yesterday),
            startedOn: yesterday,
            cohortLetters: letters,
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 64,
            dailyGoalTarget: 64,
            hardRoundCap: 64,
            results: results
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: Set(letters)),
            hasCompletedCalibration: true,
            dailyPracticeDay: yesterday,
            dailyPracticeAttempts: 5,
            activeWeeklyAssessment: assessment,
            introducedLetters: Set(letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)
        let capped = manager.profiles[0].activeWeeklyAssessment

        XCTAssertEqual(plan.dailyGoalTarget, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(plan.dailyGoalStartCount, 5)
        XCTAssertEqual(capped?.assessmentRoundTarget, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(capped?.dailyGoalTarget, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(capped?.hardRoundCap, WeeklyLetterAssessment.adaptiveSessionCeiling)
        XCTAssertEqual(capped?.results["A"]?.independentAttempts, 4)
        XCTAssertEqual(capped?.results["B"]?.independentAttempts, 1)
        XCTAssertLessThan(capped?.cohortLetters.count ?? letters.count, letters.count)
    }

    @MainActor
    func testSkippingWeeklyAssessmentArchivesPartialResultsAndAllowsSameDayIntroduction() {
        let today = LocalDay.today()
        let scheduled = mostRecentSunday(onOrBefore: today)
        var retainedA = WeeklyAssessmentLetterResult(bucket: .cohort)
        for _ in 0..<4 {
            retainedA.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        }
        var partialB = WeeklyAssessmentLetterResult(bucket: .cohort)
        partialB.recordIndependentAttempt(wasCorrect: false, responseTime: 1.0)
        let assessment = WeeklyLetterAssessment(
            scheduledFor: scheduled,
            startedOn: scheduled,
            cohortLetters: ["A", "B", "C"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 12,
            dailyGoalTarget: 13,
            hardRoundCap: 13,
            results: [
                "A": retainedA,
                "B": partialB,
                "C": WeeklyAssessmentLetterResult(bucket: .cohort)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 20,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B", "C"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        XCTAssertTrue(manager.skipActiveWeeklyAssessment(profileId: profile.id, today: today))

        let archived = try! XCTUnwrap(manager.profiles[0].recentWeeklyAssessments.last)
        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment)
        XCTAssertEqual(archived.id, assessment.id)
        XCTAssertEqual(archived.completedOn, today)
        XCTAssertEqual(archived.results["A"]?.independentAttempts, 4)
        XCTAssertEqual(archived.results["B"]?.independentAttempts, 1)
        XCTAssertEqual(archived.outcome(for: "A"), .retained)
        XCTAssertEqual(archived.outcome(for: "B"), .needsReview)
        XCTAssertEqual(archived.outcome(for: "C"), .needsReview)

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.dailyPracticeKind, .introduction)
        XCTAssertEqual(plan.dailyGoalStartCount, 0)
        XCTAssertTrue(plan.introducedNewFocusLetter)
        XCTAssertNotNil(plan.dailySpotlightLetter)
        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment)
        XCTAssertEqual(manager.profiles[0].learningCycleStartDay, today)
        XCTAssertEqual(manager.profiles[0].dailyPracticeDay, today)
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 0)
        XCTAssertEqual(manager.profiles[0].dailyPracticeWinnerClaimedDay, today)
        XCTAssertEqual(manager.profiles[0].dailyPracticeWinnerClaimedMilestone, 0)
        XCTAssertTrue(manager.profiles[0].weeklyIntroducedLetters.contains(plan.dailySpotlightLetter ?? ""))
    }

    @MainActor
    func testAdaptiveAssessmentRecordsOnlyWeeklyAssessmentIntent() throws {
        let today = LocalDay.today()
        let baseProfile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            weeklyIntroducedLetters: ["A", "B"],
            introducedLetters: ["A", "B"]
        )
        var profile = baseProfile
        profile.activeWeeklyAssessment = baseProfile.buildAdaptiveWeeklyAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            intent: .staleReview,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.results["A"]?.independentAttempts, 0)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.results["A"]?.independentAttempts, 1)
    }

    @MainActor
    func testAdaptiveAssessmentDoesNotCompleteAtCapUntilEveryLetterHasCoverage() {
        let today = LocalDay.today()
        var completedA = WeeklyAssessmentLetterResult(bucket: .fluent)
        completedA.recordIndependentAttempt(wasCorrect: true, responseTime: 1.0)
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 2,
            dailyGoalTarget: 2,
            hardRoundCap: 1,
            results: [
                "A": completedA,
                "B": WeeklyAssessmentLetterResult(bucket: .fluent)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 10,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )

        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment?.completedOn)
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.results["B"]?.independentAttempts, 0)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "B",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )

        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.completedOn, today)
    }

    @MainActor
    func testAdaptiveAssessmentCapCountsIndependentEvidenceNotRescueRounds() {
        let today = LocalDay.today()
        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 2,
            dailyGoalTarget: 2,
            hardRoundCap: 1,
            results: [
                "A": WeeklyAssessmentLetterResult(bucket: .fluent),
                "B": WeeklyAssessmentLetterResult(bucket: .fluent)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 10,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .immediateRescue,
            countsTowardDailyPractice: true
        )

        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment?.completedOn)
        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.results["A"]?.independentAttempts, 0)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )

        XCTAssertNil(manager.profiles[0].activeWeeklyAssessment?.completedOn)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "B",
            wasCorrect: true,
            asTarget: true,
            intent: .weeklyAssessment,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )

        XCTAssertEqual(manager.profiles[0].activeWeeklyAssessment?.completedOn, today)
    }

    @MainActor
    func testWeeklyAssessmentPickerForcesUnattemptedLettersBeforePlannedSlotsRunOut() {
        let today = LocalDay.today()
        var borderlineCohort = WeeklyAssessmentLetterResult(bucket: .cohort)
        for wasCorrect in [true, true, false, false] {
            borderlineCohort.recordIndependentAttempt(wasCorrect: wasCorrect, responseTime: 1.0)
        }
        XCTAssertEqual(borderlineCohort.outcome, .pending)

        let assessment = WeeklyLetterAssessment(
            scheduledFor: mostRecentSunday(onOrBefore: today),
            startedOn: today,
            cohortLetters: ["A", "B", "C"],
            strategy: .adaptiveAudit,
            assessmentRoundTarget: 6,
            dailyGoalTarget: 6,
            hardRoundCap: 6,
            results: [
                "A": borderlineCohort,
                "B": WeeklyAssessmentLetterResult(bucket: .fluent),
                "C": WeeklyAssessmentLetterResult(bucket: .fluent)
            ]
        )
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C"]),
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 1,
            activeWeeklyAssessment: assessment,
            introducedLetters: ["A", "B", "C"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            dailyGoalTarget: 6,
            dailyPracticeKind: .reviewTest,
            weeklyReviewLetters: ["A", "B", "C"]
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.currentRoundIntent, .weeklyAssessment)
        XCTAssertTrue(["B", "C"].contains(state.targetLetter))
    }

    @MainActor
    func testIntroductionDayRotatesToNewDailyLetter() {
        let today = LocalDay.today()
        let yesterday = today.adding(days: -1)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            currentFocusLetter: "A",
            lastNewLetterDay: yesterday,
            learningCycleStartDay: yesterday,
            weeklyIntroducedLetters: ["A"],
            introducedLetters: ["A"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.dailyPracticeKind, .introduction)
        XCTAssertTrue(plan.introducedNewFocusLetter)
        XCTAssertEqual(plan.focusLetter, "A")
        XCTAssertNotEqual(plan.dailySpotlightLetter, "A")
        XCTAssertEqual(manager.profiles[0].currentFocusLetter, "A")
        XCTAssertEqual(manager.profiles[0].lastNewLetterDay, today)
        XCTAssertTrue(manager.profiles[0].weeklyIntroducedLetters.contains(plan.dailySpotlightLetter ?? ""))
    }

    @MainActor
    func testDailySpotlightPreservesInFlightFocus() {
        let today = LocalDay.today()
        let yesterday = today.adding(days: -1)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            currentFocusLetter: "A",
            focusStartedDay: yesterday,
            focusPracticedDays: [yesterday],
            lastNewLetterDay: yesterday,
            learningCycleStartDay: yesterday,
            weeklyIntroducedLetters: ["A"],
            introducedLetters: ["A"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.focusLetter, "A")
        XCTAssertEqual(manager.profiles[0].currentFocusLetter, "A")
        XCTAssertTrue(manager.profiles[0].focusPracticedDays.contains(today))
        XCTAssertNotNil(plan.dailySpotlightLetter)
        XCTAssertNotEqual(plan.dailySpotlightLetter, "A")
        if let spotlight = plan.dailySpotlightLetter {
            XCTAssertEqual(plan.introducedFocusTarget, FocusTarget.letter(spotlight))
        }
        XCTAssertEqual(manager.profiles[0].lastNewLetterDay, today)
    }

    @MainActor
    func testIntroducedSpotlightAppearsDuringDailyLetterSession() throws {
        let today = LocalDay.today()
        let yesterday = today.adding(days: -1)
        let knownLetters: Set<String> = ["A", "B", "C", "D", "E", "F"]
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: knownLetters),
            hasCompletedCalibration: true,
            currentFocusLetter: "A",
            focusStartedDay: yesterday,
            focusPracticedDays: [yesterday],
            lastNewLetterDay: yesterday,
            learningCycleStartDay: yesterday,
            weeklyIntroducedLetters: ["A"],
            everMasteredLetters: knownLetters,
            introducedLetters: ["A"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)
        let spotlight: String = try XCTUnwrap(plan.dailySpotlightLetter)
        XCTAssertEqual(plan.focusLetter, "A")
        XCTAssertEqual(plan.introducedFocusTarget, FocusTarget.letter(spotlight))

        let state = AdaptiveGameState(profile: manager.profiles[0], plan: plan, profileManager: manager)
        var spotlightAppearances = 0
        var spotlightTargets = 0

        for _ in 0..<plan.dailyGoalTarget {
            if state.displayedLetters.contains(spotlight) {
                spotlightAppearances += 1
            }
            if state.targetLetter == spotlight {
                spotlightTargets += 1
            }

            let outcome = state.processAnswer(state.targetLetter)
            if outcome.sessionEndReason != nil { break }
            state.setupNewRound()
        }

        XCTAssertGreaterThanOrEqual(spotlightAppearances, 3)
        XCTAssertGreaterThanOrEqual(spotlightTargets, 1)
    }

    @MainActor
    func testCounterOnlyAdvancesWhenAdaptiveDailyRoundRequestsIt() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 4
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(profileId: profile.id, letter: "A", wasCorrect: true, asTarget: true)
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 4)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .impulsiveTap,
            attemptContext: .independent,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 5)

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            attemptContext: .immediateRescue,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 6)

        manager.recordExposure(profileId: profile.id, letter: "B")
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 6)
    }

    @MainActor
    func testEmptyReviewDayFallsBackToIntroductionWithoutResettingCycle() {
        let today = LocalDay.today()
        let cycleStart = cycleStartForDueWeeklyReview(on: today)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            learningCycleStartDay: cycleStart,
            weeklyIntroducedLetters: ["A"],
            introducedLetters: ["A"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.dailyPracticeKind, .introduction)
        XCTAssertEqual(plan.dailyGoalTarget, 25)
        XCTAssertEqual(manager.profiles[0].learningCycleStartDay, cycleStart)
        XCTAssertTrue(plan.weeklyReviewLetters.isEmpty)
    }

    @MainActor
    func testWeeklyIntroductionSkipsUnsafeConfusables() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["A", "B", "C", "J", "M", "O", "S", "T", "V"]),
            hasCompletedCalibration: true,
            learningCycleStartDay: LocalDay.today(),
            weeklyIntroducedLetters: ["B"],
            introducedLetters: ["B"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)
        let spotlight = try? XCTUnwrap(plan.dailySpotlightLetter)

        XCTAssertNotNil(spotlight)
        XCTAssertFalse(["D", "P", "Q"].contains(spotlight ?? ""))
    }

    @MainActor
    func testReadingLayerDailyGoalCountsTypedTargetsWithoutWeeklyReview() {
        let today = LocalDay.today()
        var profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            currentSyllableFocus: "MA",
            syllablesUnlockedAt: today,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 7,
            learningCycleStartDay: today.adding(days: -6),
            weeklyIntroducedLetters: ["A", "B", "C"],
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        profile.introducedSyllables.insert("MA")
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .syllable("MA"),
            primaryLayer: .syllables,
            activityKind: .syllableRecognition,
            focusScaffoldingLevel: 0,
            dailyGoalTarget: 25,
            dailyGoalStartCount: 7,
            dailyPracticeKind: .introduction,
            weeklyReviewLetters: []
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.dailyGoalCount, 7)
        state.roundsThisSession = 18
        XCTAssertTrue(state.hasCompletedDailyGoal)

        manager.recordAnswer(
            profileId: profile.id,
            target: .syllable("MA"),
            wasCorrect: true,
            asTarget: true,
            countsTowardDailyPractice: true
        )
        XCTAssertEqual(manager.profiles[0].dailyPracticeAttempts, 8)
    }

    @MainActor
    func testHeartsEndSittingWithoutResettingDailyProgress() {
        let today = LocalDay.today()
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            dailyPracticeDay: today,
            dailyPracticeAttempts: 10
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            dailyGoalTarget: 25,
            dailyGoalStartCount: 10
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        state.heartsRemaining = 0
        state.roundsThisSession = 3

        XCTAssertEqual(state.dailyGoalCount, 13)
        XCTAssertFalse(state.hasCompletedDailyGoal)
    }

    @MainActor
    func testExtraPracticeCompletionDoesNotUseDailyRoundMinimum() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "A": knownStat(),
                "B": knownStat(),
                "C": knownStat(),
                "D": knownStat(),
                "E": knownStat()
            ],
            hasCompletedCalibration: true
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            mode: .extraPractice(letter: "A")
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        for _ in 0..<5 {
            let outcome = state.processAnswer(state.targetLetter)
            if outcome.sessionEndReason != nil { break }
            state.setupNewRound()
        }

        XCTAssertEqual(state.roundsCorrect, 5)
        XCTAssertEqual(state.sessionEnded, .practiceComplete)
    }

    @MainActor
    func testAdaptiveGameOptionCountTracksKnownLetterThresholds() {
        // 6-grid: knownLetterCount >= 15 AND strongKnownLetterCount >= 10
        // 8-grid: knownLetterCount AND strongKnownLetterCount >= ~85% of the
        // alphabet (floored at 20). English (26 letters): 23-known threshold.
        // Czech (41 letters): 35-known threshold. The `knownStats` helper
        // produces strong-known evidence, so each `knownCount` here is also
        // its `strongKnownLetterCount`.
        let cases: [(language: GameLanguage, knownCount: Int, expectedOptions: Int)] = [
            (.english, 14, 4),
            (.english, 15, 6),
            (.english, 22, 6),
            (.english, 23, 8),
            (.czech, 34, 6),
            (.czech, 35, 8)
        ]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        for testCase in cases {
            let known = Set(testCase.language.letters.prefix(testCase.knownCount))
            let profile = Profile(
                name: "Mila",
                avatarId: .lion,
                language: testCase.language,
                letterStats: knownStats(for: known),
                hasCompletedCalibration: true,
                everMasteredLetters: known
            )
            let manager = ProfileManager()
            manager.profiles = [profile]

            let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

            XCTAssertEqual(state.displayedLetters.count, testCase.expectedOptions)
        }
    }

    @MainActor
    func testParentMarkedKnownLettersCountTowardOptionThreshold() {
        let language = GameLanguage.english
        let known = Set(language.letters.prefix(14))
        let markedKnown = language.letters[14]
        var stats = knownStats(for: known)
        var markedStat = LetterStat()
        markedStat.parentOverride = .markedKnown(date: Date())
        stats[markedKnown] = markedStat
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: language,
            letterStats: stats,
            hasCompletedCalibration: true,
            everMasteredLetters: known
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(profile.knownAlphabetLetterCount, 15)
        XCTAssertEqual(state.displayedLetters.count, 6)
    }

    @MainActor
    func testParentResetLettersDoNotCountTowardOptionThreshold() {
        let language = GameLanguage.english
        let known = Set(language.letters.prefix(15))
        var stats = knownStats(for: known)
        var resetStat = stats[language.letters[14]]!
        resetStat.parentOverride = .reset(date: Date())
        stats[language.letters[14]] = resetStat
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: language,
            letterStats: stats,
            hasCompletedCalibration: true,
            everMasteredLetters: known
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(profile.knownAlphabetLetterCount, 14)
        XCTAssertEqual(state.displayedLetters.count, 4)
    }

    @MainActor
    func testRestoredSessionKeepsFrozenLetterOptionCount() {
        let language = GameLanguage.english
        let known = Set(language.letters.prefix(15))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: language,
            letterStats: knownStats(for: known),
            hasCompletedCalibration: true,
            everMasteredLetters: known
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(
            profile: profile,
            plan: plan,
            advanceToNextRoundOnRestore: true
        )
        snapshot.letterOptionsPerRound = 4
        snapshot.sessionCorrectPositionCounts = Array(repeating: 0, count: 4)

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        XCTAssertEqual(profile.letterOptionsPerRound, 6)
        XCTAssertEqual(state.displayedLetters.count, 4)
    }

    @MainActor
    func testLiveDifficultyDownshiftsKnownLetterOptionCount() {
        let language = GameLanguage.czech
        // The 8-grid threshold scales with alphabet size now
        // (`max(20, ceil(count * 0.85))`); Czech needs 35 of 41 letters known.
        let known = Set(language.letters.prefix(35))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: language,
            letterStats: knownStats(for: known),
            hasCompletedCalibration: true,
            everMasteredLetters: known
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let snapshot = gameSnapshot(
            profile: profile,
            plan: plan,
            liveDifficulty: .easierUntilStreak,
            advanceToNextRoundOnRestore: true
        )

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        XCTAssertEqual(profile.letterOptionsPerRound, 8)
        XCTAssertEqual(state.displayedLetters.count, 6)
    }

    @MainActor
    func testReadingLayerOptionCountStaysFour() {
        let knownSyllables = Set(WordCurriculum.czechWords.flatMap(\.syllables))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            letterStats: knownStats(for: Set(GameLanguage.czech.letters)),
            syllableStats: Dictionary(uniqueKeysWithValues: knownSyllables.map { ($0, knownUnitStat()) }),
            hasCompletedCalibration: true,
            wordsUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            everMasteredSyllables: Set(SyllableCurriculum.allKeys(for: .czech).prefix(10)),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .word("MÁMA"),
            primaryLayer: .words,
            activityKind: .wordReading,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        // The underlying letter grid would be 8 for a profile this advanced;
        // assert via the actual grid-size resolver so the reading-layer
        // override (forcing 4) is the only thing that brings displayed count
        // down. (`AlphabetLevel.optionsPerRound` was removed because it was
        // dead code and disagreed with the live `letterOptionsPerRound`
        // formula — see `SkillLevel.swift`.)
        XCTAssertEqual(profile.letterOptionsPerRound, 8)
        XCTAssertEqual(state.displayedLetters.count, 4)

        let syllablePlan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .syllable("MA"),
            primaryLayer: .syllables,
            activityKind: .syllableRecognition,
            focusScaffoldingLevel: 0
        )
        let syllableState = AdaptiveGameState(profile: profile, plan: syllablePlan, profileManager: manager)
        XCTAssertEqual(syllableState.displayedLetters.count, 4)
    }

    func testAlphabetLevelControlsConfusionAndCaseProgression() {
        let table: [(level: AlphabetLevel, stage: AlphabetLevel.ConfusionStage, lowerDistractors: Bool, lowerTargets: Bool, visualOnly: Bool)] = [
            (.novice, .gentle, false, false, false),
            (.beginner, .safeKnownPairs, false, false, false),
            (.intermediate, .safeKnownPairs, false, false, false),
            (.advanced, .intentionalPractice, true, false, true),
            (.expert, .mixedCaseReview, true, true, true)
        ]

        for row in table {
            XCTAssertEqual(row.level.confusionStage, row.stage)
            XCTAssertEqual(row.level.allowsAutomaticLowercaseDistractors, row.lowerDistractors)
            XCTAssertEqual(row.level.allowsAutomaticLowercaseTargets, row.lowerTargets)
            XCTAssertEqual(row.level.allowsVisualOnlyDistractors, row.visualOnly)
        }
    }

    func testLowercaseSettingLabelsAutomaticHighLevelBehavior() {
        XCTAssertEqual(LowercaseMode.uppercaseOnly.displayName, "Automatic at high levels")
        XCTAssertTrue(LowercaseMode.uppercaseOnly.settingsSubtitle.contains("Advanced and Expert"))
    }

    func testConfusionMapSeparatesSymmetricAndDirectionalPairs() {
        XCTAssertTrue(LetterDifficulty.areVisuallyConfusing("B|lower", "D|lower"))
        XCTAssertTrue(LetterDifficulty.areVisuallyConfusing("C", "C|lower"))
        XCTAssertTrue(LetterDifficulty.areVisuallyConfusing("F|lower", "T|lower"))
        XCTAssertFalse(LetterDifficulty.areVisuallyConfusing("M|lower", "rn"))
        XCTAssertFalse(LetterDifficulty.areVisuallyConfusing("L", "1"))
        XCTAssertEqual(LetterDifficulty.visualOnlyDistractors(for: "M|lower"), ["rn"])
        XCTAssertEqual(LetterDifficulty.visualOnlyDistractors(for: "L"), ["1"])
        XCTAssertTrue(LetterDifficulty.isVisualOnlyDistractor("1"))
        XCTAssertTrue(LetterDifficulty.isVisualOnlyDistractor("rn"))
        XCTAssertFalse(LetterDifficulty.isEligibleTarget("1", language: .english))
        XCTAssertFalse(LetterDifficulty.isEligibleTarget("rn", language: .english))
        XCTAssertTrue(LetterDifficulty.isEligibleTarget("A|lower", language: .english))
    }

    @MainActor
    func testExpertAutomaticallyIntroducesLowercaseFocus() {
        let language = GameLanguage.english
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: language,
            letterStats: knownStats(for: Set(language.letters)),
            hasCompletedCalibration: true,
            everMasteredLetters: Set(language.letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let preview = manager.previewSessionPlan(profileId: profile.id, lowercaseMode: .uppercaseOnly)

        XCTAssertTrue(preview.focusLetter?.hasSuffix("|lower") == true)
        XCTAssertNil(manager.profiles[0].currentFocusLetter)
    }

    @MainActor
    func testNoviceLevelGateDominatesConfusionHistory() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "I": knownStat(confusedWith: ["L": 3]),
                "L": knownStat(),
                "A": knownStat(),
                "B": knownStat(),
                "C": knownStat()
            ],
            hasCompletedCalibration: true,
            everMasteredLetters: []
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            mode: .extraPractice(letter: "I")
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.targetLetter, "I")
        XCTAssertFalse(state.displayedLetters.contains("L"))
    }

    @MainActor
    func testFluentConfusablePolicySurvivesFallback() {
        var weakKnownD = LetterStat()
        weakKnownD.recordTargetAttempt(correct: true, responseTime: 1.0)
        weakKnownD.recordTargetAttempt(correct: true, responseTime: 1.0)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "B": knownStat(),
                "D": weakKnownD
            ],
            hasCompletedCalibration: true
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            mode: .extraPractice(letter: "B")
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan, advanceToNextRoundOnRestore: true)
        snapshot.instructionalBand = .beginner

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        XCTAssertTrue(LetterDifficulty.areVisuallyConfusing("B", "D"))
        XCTAssertTrue(profile.knownLetters.contains("D"))
        XCTAssertFalse(profile.strongKnownLetters.contains("D"))
        XCTAssertEqual(state.displayedLetters.count, profile.letterOptionsPerRound)
        XCTAssertFalse(state.displayedLetters.contains("D"))
    }

    @MainActor
    func testVisualOnlyDistractorsDoNotAffectMasteryOrLevelWhenTappedWrong() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: ["I": knownStat()],
            hasCompletedCalibration: true,
            everMasteredLetters: ["I"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)
        state.targetLetter = "I"
        state.displayedLetters = ["I", "1", "L", "A"]

        _ = state.processAnswer("1")

        XCTAssertNil(manager.profiles[0].letterStats["1"])
        XCTAssertEqual(manager.profiles[0].letterStats["I"]?.confusedWith["1"], 1)
        XCTAssertEqual(manager.profiles[0].everMasteredLetters, ["I"])
        XCTAssertEqual(manager.profiles[0].alphabetLevel, .novice)

        _ = manager.recordAnswer(profileId: profile.id, letter: "rn", wasCorrect: true, asTarget: true)
        manager.recordExposure(profileId: profile.id, letter: "rn")
        XCTAssertNil(manager.profiles[0].letterStats["rn"])
    }

    func testStrongKnownRequiresEvidenceAndHonorsOverrides() {
        var emerging = LetterStat()
        emerging.recordTargetAttempt(correct: true, responseTime: 1.0)
        emerging.recordTargetAttempt(correct: true, responseTime: 1.0)
        XCTAssertTrue(emerging.isKnown)
        XCTAssertFalse(emerging.isStrongKnown)

        var marked = LetterStat()
        marked.parentOverride = .markedKnown(date: Date())
        var reset = knownStat()
        reset.parentOverride = .reset(date: Date())
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: [
                "A": marked,
                "B": knownStat(),
                "C": reset
            ],
            hasCompletedCalibration: true
        )

        XCTAssertTrue(profile.knownLetters.contains("A"))
        XCTAssertTrue(profile.knownLetters.contains("B"))
        XCTAssertFalse(profile.knownLetters.contains("C"))
        XCTAssertFalse(profile.strongKnownLetters.contains("A"))
        XCTAssertTrue(profile.strongKnownLetters.contains("B"))
        XCTAssertFalse(profile.strongKnownLetters.contains("C"))
        XCTAssertEqual(profile.parentMarkedKnownButUnverified, ["A"])
        XCTAssertTrue(profile.fluentKnownLetters.contains("B"))
        XCTAssertFalse(profile.fluentKnownLetters.contains("A"))
    }

    func testFluentKnownRequiresFastStableResponses() {
        var fast = LetterStat()
        var slow = LetterStat()
        for _ in 0..<8 {
            fast.recordTargetAttempt(correct: true, responseTime: 1.0)
            slow.recordTargetAttempt(correct: true, responseTime: 2.0)
        }

        XCTAssertTrue(fast.isStrongKnown)
        XCTAssertTrue(fast.isFluentKnown)
        XCTAssertTrue(slow.isStrongKnown)
        XCTAssertFalse(slow.isFluentKnown)
    }

    @MainActor
    func testEasyDistractorsExhaustStrongKnownBeforeWeakKnown() {
        let strongLetters = Set(["E", "F", "G"])
        let weakLetters = Set(["H", "I", "J", "K"])
        var stats = knownStats(for: strongLetters)
        for letter in weakLetters {
            var stat = LetterStat()
            stat.recordTargetAttempt(correct: true, responseTime: 1.0)
            stat.recordTargetAttempt(correct: true, responseTime: 1.0)
            stats[letter] = stat
        }
        let profile = Profile(
            name: "Lena",
            avatarId: .lion,
            language: .english,
            letterStats: stats,
            hasCompletedCalibration: true
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan, advanceToNextRoundOnRestore: true)
        snapshot.rescueQueue = [
            RescueItemSnapshot(letterKey: "A", dueAfterRounds: 0, difficulty: .easy)
        ]

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        let distractors = Set(state.displayedLetters).subtracting(["A"])
        XCTAssertEqual(state.targetLetter, "A")
        XCTAssertEqual(distractors.count, 3)
        XCTAssertTrue(distractors.isSubset(of: strongLetters))
    }

    func testInstructionalBandCanDropBelowCurrentLevel() {
        let mastered = Set(GameLanguage.english.letters.prefix(20))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            everMasteredLetters: mastered
        )

        XCTAssertEqual(profile.alphabetLevel, .advanced)
        XCTAssertEqual(profile.snapshot.instructionalBand, .novice)
        XCTAssertLessThanOrEqual(profile.snapshot.instructionalBand.rank, profile.alphabetLevel.rank)
    }

    @MainActor
    func testInstructionalBandControlsLowercaseFocusIntroduction() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true,
            everMasteredLetters: Set(GameLanguage.english.letters),
            introducedLetters: Set(GameLanguage.english.letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)

        XCTAssertEqual(profile.alphabetLevel, .expert)
        XCTAssertEqual(manager.profiles[0].snapshot.instructionalBand, .novice)
        XCTAssertNil(plan.focusLetter)
        XCTAssertFalse(plan.introducedNewFocusLetter)
    }

    @MainActor
    func testReadingLayerPlansDoNotPromiseWarmup() {
        let yesterday = LocalDay.today().adding(days: -1)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            syllablesUnlockedAt: yesterday,
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)

        XCTAssertEqual(plan.primaryLayer, .syllables)
        XCTAssertEqual(plan.warmupLength, 0)
    }

    func testWordUnlockRequiresFourPlayableWordsFromFilteredPool() {
        let knownSyllables = Set(WordCurriculum.czechWords.flatMap(\.syllables))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            syllableStats: Dictionary(uniqueKeysWithValues: knownSyllables.map { ($0, knownUnitStat()) }),
            hasCompletedCalibration: true
        )

        XCTAssertFalse(WordCurriculum.wordsShouldUnlock(
            profile: profile,
            audio: StubAudio(playableWords: ["MÁMA", "TÁTA", "PUSA"])
        ))
        XCTAssertTrue(WordCurriculum.wordsShouldUnlock(
            profile: profile,
            audio: StubAudio(playableWords: ["MÁMA", "TÁTA", "PUSA", "MÍSA"])
        ))

        let pool = WordCurriculum.playableWords(
            for: profile,
            audio: StubAudio(playableWords: ["MÁMA", "TÁTA", "PUSA", "MÍSA"])
        )
        let distractors = WordCurriculum.distractors(
            for: "MÁMA",
            candidates: pool,
            profile: profile,
            count: 3
        )
        XCTAssertEqual(Set(distractors).isSubset(of: Set(pool.map(\.key))), true)
        XCTAssertEqual(distractors.count, 3)
    }

    func testWordNextFocusUsesAudioFilteredPool() {
        let knownSyllables = Set(WordCurriculum.czechWords.flatMap(\.syllables))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            syllableStats: Dictionary(uniqueKeysWithValues: knownSyllables.map { ($0, knownUnitStat()) }),
            hasCompletedCalibration: true,
            wordsUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )

        XCTAssertNil(profile.nextFocusTarget(letterSelection: nil))
        XCTAssertEqual(
            WordCurriculum.nextFocus(profile: profile, audio: StubAudio(playableWords: ["TÁTA"])),
            "TÁTA"
        )
        XCTAssertEqual(
            profile.nextFocusTarget(letterSelection: nil, wordAudio: StubAudio(playableWords: ["TÁTA"])),
            .word("TÁTA")
        )
    }

    @MainActor
    func testWordRoundsUseAndCheckpointSessionPlayablePool() throws {
        let knownSyllables = Set(WordCurriculum.czechWords.flatMap(\.syllables))
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            syllableStats: Dictionary(uniqueKeysWithValues: knownSyllables.map { ($0, knownUnitStat()) }),
            hasCompletedCalibration: true,
            wordsUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        let playable = WordCurriculum.playableWords(for: profile, audio: AudioService.shared)
        try XCTSkipIf(playable.count < 4, "Bundled word audio is required for this invariant.")
        let playableKeys = Set(playable.map(\.key))
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .word(playable[0].key),
            primaryLayer: .words,
            activityKind: .wordReading,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)
        let optionKeys = Set(state.currentRound?.options.map(\.rawKey) ?? [])
        var snapshot = state.captureSnapshot()

        XCTAssertEqual(state.currentRound?.target.kind, .word)
        XCTAssertTrue(optionKeys.isSubset(of: playableKeys))
        XCTAssertEqual(snapshot.sessionPlayableWords?.map(\.key), playable.map(\.key))

        snapshot.advanceToNextRoundOnRestore = true
        let restored = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )
        let restoredOptionKeys = Set(restored.currentRound?.options.map(\.rawKey) ?? [])
        XCTAssertEqual(restored.captureSnapshot().sessionPlayableWords?.map(\.key), playable.map(\.key))
        XCTAssertTrue(restoredOptionKeys.isSubset(of: playableKeys))
    }

    @MainActor
    func testAssistedAttemptDiscountsLearningButKeepsConfusionSignal() {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .english, hasCompletedCalibration: true)
        let manager = ProfileManager()
        manager.profiles = [profile]

        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .confusion,
            selectedWrongLetter: "B",
            attemptContext: .independent
        )
        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: true,
            asTarget: true,
            mistakeType: .confusion,
            attemptContext: .immediateRescue
        )
        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .confusion,
            selectedWrongLetter: "C",
            attemptContext: .immediateRescue
        )
        manager.recordAnswer(
            profileId: profile.id,
            letter: "A",
            wasCorrect: false,
            asTarget: true,
            mistakeType: .confusion,
            selectedWrongLetter: "D",
            attemptContext: .revealed
        )

        let stat = try! XCTUnwrap(manager.profiles[0].letterStats["A"])
        XCTAssertEqual(stat.targetAttempts, 1)
        XCTAssertEqual(stat.recentResults, [false])
        XCTAssertEqual(stat.confusedWith["B"], 1)
        XCTAssertEqual(stat.confusedWith["C"], 1)
        XCTAssertEqual(stat.confusedWith["D"], 1)
        XCTAssertNil(stat.impulsiveSelections["C"])
        XCTAssertNil(stat.impulsiveSelections["D"])
        XCTAssertEqual(manager.profiles[0].recentRoundEvents.last?.attemptContext, .revealed)
        XCTAssertEqual(manager.profiles[0].recentRoundEvents.last?.wasDiscounted, true)
    }

    @MainActor
    func testDelayedRescueDoesNotCreateMasteryEvidence() {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .english, hasCompletedCalibration: true)
        let manager = ProfileManager()
        manager.profiles = [profile]

        for _ in 0..<8 {
            manager.recordAnswer(
                profileId: profile.id,
                letter: "A",
                wasCorrect: true,
                asTarget: true,
                attemptContext: .delayedRescue
            )
        }

        let stat = try! XCTUnwrap(manager.profiles[0].letterStats["A"])
        XCTAssertEqual(stat.targetAttempts, 0)
        XCTAssertFalse(stat.isKnown)
        XCTAssertTrue(manager.profiles[0].recentRoundEvents.allSatisfy { $0.wasDiscounted })
    }

    @MainActor
    func testFastAssistedWrongStillCostsHeartAndRecordsConfusion() {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .english, hasCompletedCalibration: true)
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan)
        snapshot.targetLetter = "A"
        snapshot.displayedLetters = ["A", "B", "C", "D"]
        snapshot.currentRoundIsRescue = true
        snapshot.currentRescueDifficulty = .easy
        snapshot.currentRoundPhaseOverride = .rescue
        snapshot.roundStartedAt = Date()
        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        let outcome = state.processAnswer("B")

        let event = try! XCTUnwrap(manager.profiles[0].recentRoundEvents.last)
        let stat = try! XCTUnwrap(manager.profiles[0].letterStats["A"])
        XCTAssertEqual(outcome.heartsRemaining, 4)
        XCTAssertEqual(state.heartsRemaining, 4)
        XCTAssertEqual(event.attemptContext, .immediateRescue)
        XCTAssertEqual(event.mistakeType, .confusion)
        XCTAssertTrue(event.wasDiscounted)
        XCTAssertEqual(stat.targetAttempts, 0)
        XCTAssertEqual(stat.confusedWith["B"], 1)
        XCTAssertNil(stat.impulsiveSelections["B"])
    }

    @MainActor
    func testReplayedWrongTapWithFullHeartsDoesNotEndDailySession() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["P", "R", "N", "L"]),
            hasCompletedCalibration: true,
            introducedLetters: ["P", "R", "N", "L"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan)
        snapshot.roundReplayCount = 2
        snapshot.roundStartedAt = Date()
        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        let outcome = state.processAnswer("R")

        XCTAssertEqual(outcome.heartsRemaining, 5)
        XCTAssertNil(outcome.sessionEndReason)
        XCTAssertNil(state.sessionEnded)
    }

    @MainActor
    func testWarmupMissesDoNotEndDailySessionWhileHeartsRemain() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["P", "R", "N", "L"]),
            hasCompletedCalibration: true,
            introducedLetters: ["P", "R", "N", "L"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 5,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan)
        snapshot.phase = .warmup
        snapshot.consecutiveWarmupMisses = 2
        snapshot.roundStartedAt = Date().addingTimeInterval(-1)
        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        let outcome = state.processAnswer("R")

        XCTAssertEqual(outcome.heartsRemaining, 4)
        XCTAssertNil(outcome.sessionEndReason)
        XCTAssertNil(state.sessionEnded)
    }

    @MainActor
    func testLegacyTiredSignalCheckpointDoesNotEndDailySession() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["P", "R", "N", "L"]),
            hasCompletedCalibration: true,
            introducedLetters: ["P", "R", "N", "L"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan)
        snapshot.sessionEnded = .tiredSignal

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        XCTAssertNil(state.sessionEnded)
    }

    @MainActor
    func testWrongAnswerStillEndsDailySessionWhenLastHeartIsLost() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: ["P", "R", "N", "L"]),
            hasCompletedCalibration: true,
            introducedLetters: ["P", "R", "N", "L"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        var snapshot = gameSnapshot(profile: profile, plan: plan)
        snapshot.heartsRemaining = 1
        snapshot.roundStartedAt = Date().addingTimeInterval(-1)
        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        let outcome = state.processAnswer("R")

        XCTAssertEqual(outcome.heartsRemaining, 0)
        XCTAssertEqual(outcome.sessionEndReason, .outOfHearts)
        XCTAssertEqual(state.sessionEnded, .outOfHearts)
    }

    func testParentExplanationsPrioritizeDiscountBeforeCameo() {
        let event = RoundEvent(
            date: Date(),
            target: "A",
            options: ["A", "B", "M", "C"],
            selected: "B",
            wasCorrect: false,
            responseTime: 1.0,
            phase: .rescue,
            intent: .rescue,
            mistakeType: .confusion,
            didReplayPrompt: false,
            replayCount: 0,
            wasDiscounted: true,
            heartsAfter: 4,
            liveDifficulty: .normal,
            isRescue: true,
            rescueDifficulty: .easy,
            attemptContext: .immediateRescue,
            cameoLetter: "M",
            includedFocusAsDistractor: true
        )

        XCTAssertTrue(event.parentExplanations[0].contains("Helped after a miss"))
        XCTAssertTrue(event.parentExplanations.contains { $0.contains("M appeared as a preview") })
        XCTAssertTrue(event.parentExplanations.contains { $0.contains("focus") })
    }

    func testParentExplanationsPrioritizeImpulseBeforeCameo() {
        let event = RoundEvent(
            date: Date(),
            target: "A",
            options: ["A", "B", "Z", "C"],
            selected: "B",
            wasCorrect: false,
            responseTime: 0.2,
            phase: .drill,
            intent: .focusDistractorExposure,
            mistakeType: .impulsiveTap,
            didReplayPrompt: false,
            replayCount: 0,
            wasDiscounted: true,
            heartsAfter: 5,
            liveDifficulty: .normal,
            isRescue: false,
            rescueDifficulty: nil,
            cameoLetter: "Z",
            includedFocusAsDistractor: true
        )

        XCTAssertEqual(event.parentExplanations.first, "Discounted as an impulsive tap.")
        XCTAssertTrue(event.parentExplanations.contains { $0.contains("Z appeared as a preview") })
    }

    func testLegacyRoundEventDecodeDefaultsExplanations() throws {
        let event = RoundEvent(
            date: Date(),
            target: "A",
            options: ["A", "B", "C", "D"],
            selected: "A",
            wasCorrect: true,
            responseTime: 1.0,
            phase: .drill,
            intent: .focusDistractorExposure,
            mistakeType: nil,
            didReplayPrompt: false,
            replayCount: 0,
            wasDiscounted: false,
            heartsAfter: 5,
            liveDifficulty: .normal,
            isRescue: false,
            rescueDifficulty: nil,
            attemptContext: .independent,
            cameoLetter: "Z",
            includedFocusAsDistractor: true
        )
        let data = try JSONEncoder().encode(event)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "attemptContext")
        json.removeValue(forKey: "cameoLetter")
        json.removeValue(forKey: "includedFocusAsDistractor")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(RoundEvent.self, from: legacyData)

        XCTAssertNil(decoded.attemptContext)
        XCTAssertNil(decoded.cameoLetter)
        XCTAssertFalse(decoded.includedFocusAsDistractor)
        XCTAssertEqual(decoded.parentExplanations, ["Today's focus appeared as a distractor for extra exposure."])
    }

    func testLegacyFocusDistractorIntentStillExplainsExposure() {
        let event = RoundEvent(
            date: Date(),
            target: "A",
            options: ["A", "B", "C", "D"],
            selected: "A",
            wasCorrect: true,
            responseTime: 1.0,
            phase: .drill,
            intent: .focusDistractorExposure,
            mistakeType: nil,
            didReplayPrompt: false,
            replayCount: 0,
            wasDiscounted: false,
            heartsAfter: 5,
            liveDifficulty: .normal,
            isRescue: false,
            rescueDifficulty: nil
        )

        XCTAssertTrue(event.parentExplanations.contains("Today's focus appeared as a distractor for extra exposure."))
    }

    @MainActor
    func testCameoLetterRecordsOnlyDistractorExposure() {
        let today = LocalDay.today()
        let introduced = Set(["P", "R", "N", "L", "E"])
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: introduced),
            hasCompletedCalibration: true,
            lastNewLetterDay: today,
            introducedLetters: introduced
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)
        let cameo = try! XCTUnwrap(state.displayedLetters.first { !introduced.contains($0) && $0 != state.targetLetter })

        XCTAssertEqual(state.displayedLetters.count, profile.letterOptionsPerRound)
        XCTAssertEqual(manager.profiles[0].cameoExposuresToday, 0)

        _ = state.processAnswer(state.targetLetter)

        let saved = manager.profiles[0]
        XCTAssertEqual(saved.introducedLetters, introduced)
        XCTAssertEqual(saved.lastNewLetterDay, today)
        XCTAssertEqual(saved.letterStats[cameo]?.targetAttempts ?? 0, 0)
        XCTAssertEqual(saved.letterStats[cameo]?.distractorExposures, 1)
        XCTAssertEqual(saved.cameoExposureDay, today)
        XCTAssertEqual(saved.cameoExposuresToday, 1)
        XCTAssertEqual(state.cameoExposuresThisSession, 1)
        XCTAssertEqual(state.unintroducedExposuresThisSession, 0)
    }

    @MainActor
    func testSameDayReplayDoesNotResetCameoDailyBudget() {
        let introduced = Set(["P", "R", "N", "L", "E"])
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: introduced),
            hasCompletedCalibration: true,
            introducedLetters: introduced
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        for _ in 0..<(Profile.dailyCameoExposureLimit + 2) {
            let entryProfile = manager.profiles[0]
            let state = AdaptiveGameState(profile: entryProfile, plan: plan, profileManager: manager)
            _ = state.processAnswer(state.targetLetter)
        }

        let saved = manager.profiles[0]
        let cameoExposureTotal = saved.letterStats
            .filter { key, _ in !introduced.contains(key) }
            .map { _, stat in stat.distractorExposures }
            .reduce(0, +)
        XCTAssertEqual(saved.cameoExposureDay, LocalDay.today())
        XCTAssertEqual(saved.cameoExposuresToday, Profile.dailyCameoExposureLimit)
        XCTAssertEqual(cameoExposureTotal, Profile.dailyCameoExposureLimit)
    }

    @MainActor
    func testCameosStopWhileDifficultyIsEased() {
        let introduced = Set(["P", "R", "N", "L", "E"])
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: introduced),
            hasCompletedCalibration: true,
            introducedLetters: introduced
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let snapshot = gameSnapshot(
            profile: profile,
            plan: plan,
            liveDifficulty: .easierUntilStreak,
            advanceToNextRoundOnRestore: true
        )

        let state = AdaptiveGameState(
            profile: profile,
            plan: plan,
            profileManager: manager,
            restoredSnapshot: snapshot
        )

        XCTAssertFalse(state.displayedLetters.contains { !introduced.contains($0) && $0 != state.targetLetter })
        _ = state.processAnswer(state.targetLetter)
        XCTAssertEqual(manager.profiles[0].cameoExposuresToday, 0)
        XCTAssertEqual(state.cameoExposuresThisSession, 0)
    }

    @MainActor
    func testCameosRespectCzechDiacriticPrerequisites() {
        let known = Set(["P", "L", "H", "K", "G"])
        let diacritics = Set(LetterDifficulty.diacriticBase.keys)
        let introduced = Set(GameLanguage.czech.letters).subtracting(diacritics)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            letterStats: knownStats(for: known),
            hasCompletedCalibration: true,
            introducedLetters: introduced
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertFalse(state.displayedLetters.contains { diacritics.contains($0) })
        _ = state.processAnswer(state.targetLetter)
        XCTAssertEqual(manager.profiles[0].cameoExposuresToday, 0)
    }

    @MainActor
    func testCameosAvoidVisualConfusablesWithTarget() {
        let introduced = Set(["D", "A", "E", "L", "N"])
        var stats = knownStats(for: introduced)
        stats["D"] = knownStat(correctCount: 4, incorrectCount: 1)
        let profile = Profile(
            name: "Lena",
            avatarId: .lion,
            language: .english,
            letterStats: stats,
            hasCompletedCalibration: true,
            introducedLetters: introduced
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.targetLetter, "D")
        XCTAssertFalse(state.displayedLetters.contains("P"))
        XCTAssertTrue(state.displayedLetters.contains("R"))
    }

    @MainActor
    func testLowercaseAudioFallbackHasSpokenText() {
        XCTAssertEqual(AudioService.shared.spokenLetter(for: "Q|lower"), "q")
    }

    func testOldProfileJSONDecodesWithEmptyReadingFields() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Mila",
          "avatarId": "lion",
          "language": "cz",
          "modifiedAt": 0,
          "letterStats": {},
          "hasCompletedCalibration": true,
          "focusPracticedDays": [],
          "dailyStreakCount": 0,
          "bestDailyStreak": 0,
          "everMasteredLetters": [],
          "bestSessionStreak": 0,
          "introducedLetters": [],
          "recentRoundEvents": [],
          "highestLevelEverReached": "novice",
          "celebratedLevels": ["novice"]
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertTrue(profile.syllableStats.isEmpty)
        XCTAssertTrue(profile.wordStats.isEmpty)
        XCTAssertNil(profile.syllablesUnlockedAt)
        XCTAssertNil(profile.wordsUnlockedAt)
        XCTAssertNil(profile.cameoExposureDay)
        XCTAssertEqual(profile.cameoExposuresToday, 0)
        XCTAssertNil(profile.dailyPracticeDay)
        XCTAssertEqual(profile.dailyPracticeAttempts, 0)
        XCTAssertNil(profile.learningCycleStartDay)
        XCTAssertTrue(profile.weeklyIntroducedLetters.isEmpty)
    }

    @MainActor
    func testExpertCzechProfileUnlocksSyllablesForNextDay() {
        var profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            everMasteredLetters: Set(GameLanguage.czech.letters)
        )
        for letter in GameLanguage.czech.letters {
            profile.letterStats[letter] = LetterStat(recentResults: Array(repeating: true, count: 8), targetAttempts: 8, targetCorrect: 8)
            profile.introducedLetters.insert(letter)
        }
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.primaryLayer, .letters)
        XCTAssertNotNil(manager.profiles[0].syllablesUnlockedAt)
    }

    func testAlphabetLevelAndReadingStageThresholdsAreSeparate() {
        XCTAssertEqual(AlphabetLevel.from(letterMasteredCount: GameLanguage.czech.letters.count, language: .czech), .expert)
        XCTAssertEqual(ReadingStage.from(syllablesUnlocked: true, syllableMasteredCount: 0, wordMasteredCount: 0), .cvBridge)
        XCTAssertEqual(ReadingStage.from(syllablesUnlocked: true, syllableMasteredCount: 10, wordMasteredCount: 0), .syllableReader)
        XCTAssertEqual(ReadingStage.from(syllablesUnlocked: true, syllableMasteredCount: 10, wordMasteredCount: 5), .wordBuilder)
        XCTAssertEqual(ReadingStage.from(syllablesUnlocked: true, syllableMasteredCount: 10, wordMasteredCount: 20), .storyteller)
        XCTAssertTrue(ReadingStage.storyteller > .wordBuilder)
    }

    func testSyllableAndWordCurriculumPrerequisites() {
        var profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            everMasteredLetters: Set(GameLanguage.czech.letters)
        )
        XCTAssertTrue(SyllableCurriculum.prerequisitesMet(for: "MA", profile: profile))
        XCTAssertFalse(SyllableCurriculum.prerequisitesMet(for: "MÁ", profile: profile))

        profile.syllableStats["MA"] = SyllableStat(recentResults: [true, true, true], targetAttempts: 3, targetCorrect: 3)
        XCTAssertTrue(SyllableCurriculum.prerequisitesMet(for: "MÁ", profile: profile))
    }

    @MainActor
    func testCzechStarterSubsetDoesNotUnlockSyllablesBeforeFullAlphabet() {
        let starter = Set(SyllableCurriculum.starterConsonants + SyllableCurriculum.shortVowels)
        let stats = knownStats(for: starter)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            letterStats: stats,
            hasCompletedCalibration: true,
            everMasteredLetters: starter,
            introducedLetters: starter
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        XCTAssertLessThan(profile.everMasteredLetters.count, GameLanguage.czech.letters.count)
        XCTAssertFalse(profile.hasCompletedAlphabetForReading)

        let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(plan.primaryLayer, .letters)
        XCTAssertNil(manager.profiles[0].syllablesUnlockedAt)
        XCTAssertNil(plan.focusTarget.flatMap { target in
            target.kind == .letter ? nil : target
        })
    }

    @MainActor
    func testStaleSyllableUnlockDoesNotRouteBeforeFullAlphabet() {
        let yesterday = LocalDay.today().adding(days: -1)
        let starter = Set(SyllableCurriculum.starterConsonants + SyllableCurriculum.shortVowels)
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            letterStats: knownStats(for: starter),
            hasCompletedCalibration: true,
            currentSyllableFocus: "MA",
            syllablesUnlockedAt: yesterday,
            everMasteredLetters: starter,
            introducedLetters: starter
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let plan = manager.previewSessionPlan(profileId: profile.id)

        XCTAssertEqual(plan.primaryLayer, .letters)
        XCTAssertNotEqual(plan.focusTarget, .syllable("MA"))
        XCTAssertNotEqual(manager.profiles[0].snapshot.nextFocusTarget, .syllable("MA"))
        XCTAssertEqual(manager.profiles[0].readingStage, .none)
    }

    @MainActor
    func testTypedRecordAnswerUpdatesSyllableStats() {
        var profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            currentSyllableFocus: "MA",
            syllablesUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        profile.introducedSyllables.insert("MA")
        let manager = ProfileManager()
        manager.profiles = [profile]

        _ = manager.recordAnswer(
            profileId: profile.id,
            target: .syllable("MA"),
            wasCorrect: true,
            asTarget: true,
            optionsShown: [.syllable("MA"), .syllable("LA")]
        )

        XCTAssertEqual(manager.profiles[0].syllableStats["MA"]?.targetAttempts, 1)
        XCTAssertNil(manager.profiles[0].letterStats["MA"])
    }

    @MainActor
    func testSyllableRoundGenerationUsesTypedRound() {
        var profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .czech,
            hasCompletedCalibration: true,
            currentSyllableFocus: "MA",
            syllablesUnlockedAt: LocalDay.today(),
            everMasteredLetters: Set(GameLanguage.czech.letters),
            introducedLetters: Set(GameLanguage.czech.letters)
        )
        profile.introducedSyllables.insert("MA")
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusTarget: .syllable("MA"),
            primaryLayer: .syllables,
            activityKind: .syllableRecognition,
            focusScaffoldingLevel: 0
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        XCTAssertEqual(state.currentRound?.target, .syllable("MA"))
        XCTAssertTrue(state.displayedLetters.contains("MA"))
        XCTAssertEqual(state.currentRoundPlanReason?.primaryGoal, .readingBridge)
        XCTAssertEqual(state.currentRoundPlanReason?.distractorPolicy, .audioPlayableOnly)
    }

    func testWordBuildingRoundMetadataSurvivesCheckpointCoding() throws {
        let round = LearningRound(
            target: .word("MÁMA"),
            options: [.syllable("MÁ"), .syllable("MA"), .syllable("MO")],
            activityKind: .wordBuilding,
            segments: [.syllable("MÁ"), .syllable("MA")],
            expectedSequence: [.syllable("MÁ"), .syllable("MA")],
            selectedSequence: [.syllable("MÁ")]
        )
        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(LearningRound.self, from: data)
        XCTAssertEqual(decoded, round)
    }

    @MainActor
    func testAudioValidationIncludesCurriculumAssetNames() {
        let required = AudioService.shared.requiredCurriculumVoiceAssets(for: .czech)
        XCTAssertTrue(required.contains("cz_syl_ma"))
        XCTAssertTrue(required.contains("cz_word_máma"))
    }

    func testNewProfilesDefaultToSystemLanguage() {
        let profile = Profile(name: "Mila", avatarId: .lion)

        XCTAssertEqual(profile.language, .system)
        XCTAssertEqual(profile.language.resolvedLanguage, GameLanguage.system.resolvedLanguage)
    }

    func testSlowCorrectAnswersDoNotLowerCertainty() {
        // Asymmetric speed rule: slow correct answers (likely toddler
        // distraction) must never demote certainty below an identical-
        // accuracy fast answer. Speed only earns a *positive* fluency
        // tier; it never penalizes confidence.
        var fast = LetterStat()
        var slow = LetterStat()

        for _ in 0..<8 {
            fast.recordTargetAttempt(correct: true, responseTime: 1.0)
            // 3.0s ≈ distractible toddler pace, still inside the
            // distraction cutoff so the median is recorded.
            slow.recordTargetAttempt(correct: true, responseTime: 3.0)
        }

        XCTAssertTrue(slow.isKnown)
        XCTAssertTrue(slow.isFocusGraduated)
        XCTAssertEqual(slow.certaintyScore, fast.certaintyScore, accuracy: 0.0001)
        XCTAssertTrue(fast.isFluentKnown)
        XCTAssertFalse(slow.isFluentKnown)
    }

    func testDistractionGradeResponseTimesAreDroppedFromTheWindow() {
        // Anything at or above `distractionResponseCutoff` is treated as a
        // "kid looked away" event and never enters the response-time
        // window, so the median (and the `fast`/`normal`/`slow` bucket
        // and `isFluentKnown`) reflect genuine recognition latency only.
        var stat = LetterStat()
        for _ in 0..<6 {
            stat.recordTargetAttempt(correct: true, responseTime: 1.0)
        }
        let medianBefore = stat.medianResponseTime
        XCTAssertEqual(medianBefore ?? -1, 1.0, accuracy: 0.0001)

        // Two huge "distraction" outliers must not move the median.
        stat.recordTargetAttempt(correct: true, responseTime: 12.0)
        stat.recordTargetAttempt(correct: true, responseTime: 30.0)

        XCTAssertEqual(stat.medianResponseTime ?? -1, 1.0, accuracy: 0.0001)
        // Accuracy still updates — the answer they eventually gave was
        // correct and counts toward mastery, even if the time was noise.
        XCTAssertEqual(stat.targetAttempts, 8)
        XCTAssertEqual(stat.targetCorrect, 8)
    }

    func testParentLetterKnowledgeSummaryRecognizesEverMasteredAndCarvesOutSlipped() {
        // Three contrasting letters in a tiny 3-letter "alphabet":
        //   A — currently mastered (strict 7/8 bar), in everMastered
        //   B — ever-mastered but currently slipped (3/5 recent)
        //   C — introduced and learning, never mastered, currently failing
        //
        // Expected bucketing under the new rules:
        //   • A → confidently known (currently mastered AND in knownLetters)
        //   • B → likely known (lifetime trophy, carved out of needs-practice)
        //   • C → needs practice (truly weak — never cleared the bar)
        //   • recentlySlipped explicitly contains B for callers that want it
        let strictlyMastered = knownStat(correctCount: 8)

        var slipped = LetterStat()
        for _ in 0..<8 {
            slipped.recordTargetAttempt(correct: true, responseTime: 1.0)
        }
        // Three fresh misses push the loose 4/5-of-last-5 check below the
        // bar, simulating a previously-mastered letter that's wobbled in
        // the last session.
        for _ in 0..<3 {
            slipped.recordTargetAttempt(correct: false, responseTime: 1.0)
        }
        slipped.wasKnownBefore = true

        var weak = LetterStat()
        for _ in 0..<4 {
            weak.recordTargetAttempt(correct: false, responseTime: 1.0)
        }

        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: ["A": strictlyMastered, "B": slipped, "C": weak],
            hasCompletedCalibration: true,
            everMasteredLetters: ["A", "B"],
            introducedLetters: ["A", "B", "C"]
        )

        let summary = profile.snapshot.parentLetterKnowledgeSummary(
            alphabetLetters: ["A", "B", "C"]
        )

        XCTAssertEqual(summary.confidentlyKnownLetters, ["A"])
        XCTAssertEqual(summary.likelyKnownLetters, ["B"])
        XCTAssertEqual(summary.needsPracticeLetters, ["C"])
        XCTAssertEqual(summary.recentlySlippedLetters, ["B"])
        XCTAssertEqual(summary.totalLetters, 3)
    }

    func testParentLetterKnowledgeSummaryPromotesEverMasteredStillPassing() {
        // A letter that was mastered some time ago but only has a few
        // recent attempts now should be confidently known if those recent
        // attempts pass the loose 4/5 check. Without the ever-mastered
        // path this letter sat in "likely known" purely because its 8-
        // attempt window had drifted; the lifetime trophy stopped
        // translating into the headline count.
        var stillStrong = LetterStat()
        for _ in 0..<5 {
            stillStrong.recordTargetAttempt(correct: true, responseTime: 1.0)
        }

        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            letterStats: ["A": stillStrong],
            hasCompletedCalibration: true,
            everMasteredLetters: ["A"],
            introducedLetters: ["A"]
        )

        let summary = profile.snapshot.parentLetterKnowledgeSummary(
            alphabetLetters: ["A"]
        )

        XCTAssertEqual(summary.confidentlyKnownLetters, ["A"])
        XCTAssertTrue(summary.likelyKnownLetters.isEmpty)
        XCTAssertTrue(summary.needsPracticeLetters.isEmpty)
    }

    func testReviewPriorityIgnoresSlowResponsesAndUsesWeaknessAndStaleness() {
        // Two letters with identical (perfect) recent accuracy and no
        // staleness — one answered fast, one answered slow. Under the
        // old rule the slow letter floated up the warm-up queue purely
        // because of its median; under the new rule both should tie at
        // 0 priority and the slow letter doesn't crowd out actually-weak
        // letters.
        var fast = LetterStat()
        var slow = LetterStat()
        for _ in 0..<8 {
            fast.recordTargetAttempt(correct: true, responseTime: 1.0)
            slow.recordTargetAttempt(correct: true, responseTime: 3.0)
        }

        XCTAssertEqual(fast.reviewPriority, 0.0, accuracy: 0.0001)
        XCTAssertEqual(slow.reviewPriority, 0.0, accuracy: 0.0001)

        // A genuinely weak letter must still outrank both of them, even
        // when it's been answered very recently.
        var weak = LetterStat()
        for _ in 0..<5 {
            weak.recordTargetAttempt(correct: false, responseTime: 1.0)
        }
        XCTAssertGreaterThan(weak.reviewPriority, slow.reviewPriority)
        XCTAssertGreaterThan(weak.reviewPriority, fast.reviewPriority)
    }

    func testLettersByConfidenceSortsByCertaintyAndIgnoresSpeed() {
        // With the speed multiplier removed, two letters at identical
        // accuracy and attempt count tie on `certaintyScore` regardless
        // of how slow one of them is. The stable tiebreaker (storage key
        // ordering) wins, so neither A nor B leapfrogs the other on
        // speed alone.
        var slowA = LetterStat()
        var fastB = LetterStat()

        for _ in 0..<8 {
            slowA.recordTargetAttempt(correct: true, responseTime: 3.0)
            fastB.recordTargetAttempt(correct: true, responseTime: 1.0)
        }

        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            letterStats: ["A": slowA, "B": fastB],
            hasCompletedCalibration: true
        )

        XCTAssertEqual(slowA.certaintyScore, fastB.certaintyScore, accuracy: 0.0001)
        XCTAssertEqual(profile.lettersByConfidence, ["A", "B"])
    }

    @MainActor
    func testProfileManagerCreatesProfileWithSelectedLanguage() throws {
        let suiteName = "PismenkaModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ProfileManager(defaults: defaults)

        let profile = try XCTUnwrap(manager.createProfile(name: "Mila", avatar: .lion, language: .czech))

        XCTAssertEqual(profile.language, .czech)
    }

    func testProfileExportMergeReplacesMatchingProfile() throws {
        let id = UUID()
        let existing = Profile(id: id, name: "Old", avatarId: .lion)
        let imported = Profile(id: id, name: "New", avatarId: .penguin)
        let result = try ProfileExportService.merged(existing: [existing], imported: [imported], mode: .merge)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "New")
    }

    func testCloudBackupEnvelopeRoundTrips() throws {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .czech)
        let settings = AppSettingsSnapshot(
            musicEnabled: false,
            sfxEnabled: true,
            reduceMotionEnabled: false,
            confettiEnabled: true,
            parentGateMethod: .swipe,
            remindersEnabled: true,
            reminderHour: 17,
            reminderMinute: 30,
            lowercaseMode: .uppercaseOnly,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let envelope = CloudBackupEnvelope(
            savedAt: Date(timeIntervalSince1970: 200),
            profiles: [profile],
            settings: settings
        )

        let data = try FirebaseBackupService.encodePayload(envelope)
        let decoded = try FirebaseBackupService.decodePayload(data)

        XCTAssertEqual(decoded, envelope)
    }

    func testFirebaseBackupPayloadLimitHelperRejectsOversizedData() {
        let oversized = Data(repeating: 1, count: FirebaseBackupService.maxPayloadBytes + 1)

        XCTAssertFalse(FirebaseBackupService.isPayloadWithinLimit(oversized))
        XCTAssertTrue(FirebaseBackupService.isPayloadWithinLimit(Data()))
    }

    func testFirebaseBackupDocumentFieldsMatchEncodedPayload() throws {
        let profile = Profile(name: "Mila", avatarId: .lion, language: .czech)
        let settings = AppSettingsSnapshot(
            musicEnabled: false,
            sfxEnabled: true,
            reduceMotionEnabled: false,
            confettiEnabled: true,
            parentGateMethod: .swipe,
            remindersEnabled: true,
            reminderHour: 17,
            reminderMinute: 30,
            lowercaseMode: .uppercaseOnly,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let envelope = CloudBackupEnvelope(
            savedAt: Date(timeIntervalSince1970: 200),
            profiles: [profile],
            settings: settings
        )

        let fields = try FirebaseBackupService.backupDocumentFields(for: envelope)
        let payload = try XCTUnwrap(fields["payload"] as? Data)

        XCTAssertEqual(fields["schemaVersion"] as? Int, CloudBackupEnvelope.currentSchemaVersion)
        XCTAssertEqual(fields["payloadEncoding"] as? String, "lzfse-marker-v1")
        XCTAssertEqual(fields["payloadBytes"] as? Int, payload.count)
        XCTAssertTrue(FirebaseBackupService.isPayloadWithinLimit(payload))
    }

    func testOlderProfilesDecodeWithDistantPastModifiedAt() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Mila",
          "avatarId": "lion",
          "language": "en"
        }
        """

        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.id, id)
        XCTAssertEqual(profile.modifiedAt, .distantPast)
    }

    func testCloudMergeKeepsNewestMatchingProfile() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let local = Profile(id: id, name: "Old", avatarId: .lion, modifiedAt: older)
        let cloud = Profile(id: id, name: "New", avatarId: .penguin, modifiedAt: newer)

        let result = FirebaseBackupService.mergedProfiles(local: [local], cloud: [cloud])

        XCTAssertTrue(result.didChangeLocalProfiles)
        XCTAssertEqual(result.profiles.count, 1)
        XCTAssertEqual(result.profiles[0].name, "New")
    }

    @MainActor
    func testAppSettingsAppliesNewerSnapshot() throws {
        let suiteName = "PismenkaModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let snapshot = AppSettingsSnapshot(
            musicEnabled: true,
            sfxEnabled: false,
            reduceMotionEnabled: true,
            confettiEnabled: false,
            parentGateMethod: .holdButtons,
            remindersEnabled: true,
            reminderHour: 8,
            reminderMinute: 15,
            lowercaseMode: .afterUppercaseMastery,
            modifiedAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(settings.apply(snapshot: snapshot))
        XCTAssertEqual(settings.snapshot(), snapshot)
        XCTAssertFalse(settings.apply(snapshot: AppSettingsSnapshot(
            musicEnabled: false,
            sfxEnabled: true,
            reduceMotionEnabled: false,
            confettiEnabled: true,
            parentGateMethod: .swipe,
            remindersEnabled: false,
            reminderHour: 17,
            reminderMinute: 0,
            lowercaseMode: .uppercaseOnly,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )))
    }

    @MainActor
    func testSessionPreviewDoesNotMutateProfileUntilFirstAnswerCommit() {
        let profile = Profile(
            name: "Mila",
            avatarId: .lion,
            language: .english,
            hasCompletedCalibration: true
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let preview = manager.previewSessionPlan(profileId: profile.id)

        XCTAssertEqual(preview.dayStreakCount, 1)
        XCTAssertTrue(preview.dayStreakIncreased)
        XCTAssertNotNil(preview.focusLetter)
        XCTAssertEqual(manager.profiles[0].dailyStreakCount, 0)
        XCTAssertNil(manager.profiles[0].lastSessionDay)
        XCTAssertNil(manager.profiles[0].currentFocusLetter)
        XCTAssertTrue(manager.profiles[0].introducedLetters.isEmpty)

        let committed = manager.commitSessionStartIfNeeded(profileId: profile.id)

        XCTAssertEqual(committed.dayStreakCount, 1)
        XCTAssertTrue(committed.dayStreakIncreased)
        XCTAssertEqual(manager.profiles[0].dailyStreakCount, 1)
        XCTAssertEqual(manager.profiles[0].lastSessionDay, LocalDay.today())
        XCTAssertEqual(manager.profiles[0].currentFocusLetter, committed.focusLetter)
        XCTAssertEqual(manager.profiles[0].introducedLetters, Set([committed.focusLetter].compactMap { $0 }))
    }

    @MainActor
    func testProfileManagerRestoresLastGoodProfilesWhenPrimaryDecodeFails() throws {
        let suiteName = "PismenkaModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = Profile(name: "Mila", avatarId: .lion, language: .czech)
        let backupData = try JSONEncoder().encode([profile])
        defaults.set(Data("not valid json".utf8), forKey: "pismenka_profiles_v2")
        defaults.set(backupData, forKey: "pismenka_profiles_v2_last_good")

        let manager = ProfileManager(defaults: defaults)

        XCTAssertEqual(manager.profiles, [profile])
        XCTAssertNotNil(defaults.data(forKey: "pismenka_profiles_v2_recovery"))
        XCTAssertEqual(defaults.data(forKey: "pismenka_profiles_v2"), backupData)
    }

    @MainActor
    func testSessionSummaryUsesEntryProfileIfProfileDisappears() {
        let profile = Profile(
            name: "Ada",
            avatarId: .penguin,
            language: .czech,
            hasCompletedCalibration: true,
            currentFocusLetter: "A",
            introducedLetters: ["A"]
        )
        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: "A",
            focusScaffoldingLevel: 0
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)

        manager.profiles = []
        let summary = state.makeSummary(reason: .homeTapped)

        XCTAssertEqual(summary.profileId, profile.id)
        XCTAssertEqual(summary.totalLetters, profile.language.letters.count)
        XCTAssertEqual(summary.currentFocusLetter, "A")
    }

    @MainActor
    func testAdaptiveTrajectorySimulationMaintainsRoundInvariants() {
        let scenarios: [(String, Profile)] = [
            (
                "brand-new sparse profile",
                Profile(name: "Ada", avatarId: .lion, language: .english, hasCompletedCalibration: true)
            ),
            (
                "parent-marked broad known pool",
                Profile(
                    name: "Zoe",
                    avatarId: .fox,
                    language: .english,
                    letterStats: parentMarkedStats(for: ["P", "R", "N", "L", "E", "I", "D", "H"]),
                    hasCompletedCalibration: true,
                    introducedLetters: ["P", "R", "N", "L", "E", "I", "D", "H"]
                )
            ),
            (
                "Czech vowel-length learner",
                Profile(
                    name: "Mila",
                    avatarId: .penguin,
                    language: .czech,
                    letterStats: knownStats(for: ["A", "E", "I", "O", "U", "M", "L", "S", "P", "T"]),
                    hasCompletedCalibration: true,
                    everMasteredLetters: ["A", "E", "I", "O", "U", "M", "L", "S", "P", "T"],
                    introducedLetters: ["A", "E", "I", "O", "U", "M", "L", "S", "P", "T"]
                )
            )
        ]

        for (label, profile) in scenarios {
            let manager = ProfileManager()
            manager.profiles = [profile]
            let plan = manager.commitSessionStartIfNeeded(profileId: profile.id)
            let state = AdaptiveGameState(profile: manager.profiles[0], plan: plan, profileManager: manager)

            for step in 0..<24 {
                XCTAssertFalse(state.displayedLetters.isEmpty, label)
                XCTAssertTrue(state.displayedLetters.contains(state.targetLetter), label)
                XCTAssertEqual(Set(state.displayedLetters).count, state.displayedLetters.count, label)
                XCTAssertNotNil(state.currentRoundPlanReason, label)

                if let round = state.currentRound {
                    XCTAssertEqual(round.options.count, state.displayedLetters.count, label)
                    XCTAssertTrue(round.options.contains(round.target), label)
                }

                let shouldMiss = step % 7 == 3
                let wrongChoice = state.displayedLetters.first { $0 != state.targetLetter }
                let selected = shouldMiss ? (wrongChoice ?? state.targetLetter) : state.targetLetter
                let outcome = state.processAnswer(selected)

                XCTAssertLessThanOrEqual(
                    manager.profiles[0].cameoExposures(on: LocalDay.today()),
                    Profile.dailyCameoExposureLimit,
                    label
                )
                XCTAssertLessThanOrEqual(
                    manager.profiles[0].recentRoundEvents.count,
                    RoundEvent.maxRetained,
                    label
                )

                if outcome.sessionEndReason != nil { break }
                state.setupNewRound()
            }
        }
    }

    @MainActor
    func testSameDaySimulationDoesNotIntroduceSecondFocusAfterGraduation() throws {
        let known = Set(["B", "V", "T", "M", "J"])
        let profile = Profile(
            name: "Ada",
            avatarId: .lion,
            language: .english,
            letterStats: knownStats(for: known),
            hasCompletedCalibration: true,
            everMasteredLetters: known,
            introducedLetters: known
        )
        let manager = ProfileManager()
        manager.profiles = [profile]

        let firstPlan = manager.commitSessionStartIfNeeded(profileId: profile.id)
        let focus = try XCTUnwrap(firstPlan.focusLetter)
        XCTAssertTrue(firstPlan.introducedNewFocusLetter)

        for _ in 0..<8 {
            manager.recordAnswer(
                profileId: profile.id,
                letter: focus,
                wasCorrect: true,
                asTarget: true,
                responseTime: 1.0,
                intent: .focusTarget,
                phaseAtAnswer: .drill,
                attemptContext: .independent
            )
        }

        XCTAssertNil(manager.profiles[0].currentFocusLetter)
        XCTAssertEqual(manager.profiles[0].lastNewLetterDay, LocalDay.today())

        let sameDayReplayPlan = manager.commitSessionStartIfNeeded(profileId: profile.id)
        XCTAssertFalse(sameDayReplayPlan.introducedNewFocusLetter)
        XCTAssertNil(sameDayReplayPlan.focusLetter)
    }

    @MainActor
    func testNameLettersArePrioritizedForSafeCameoExposure() throws {
        let known = Set(["P", "R", "N", "L", "E", "I"])
        let profile = Profile(
            name: "Zoe",
            avatarId: .fox,
            language: .english,
            letterStats: knownStats(for: known),
            hasCompletedCalibration: true,
            everMasteredLetters: known,
            introducedLetters: known
        )
        XCTAssertEqual(profile.nameLetterKeys, ["Z", "O", "E"])

        let manager = ProfileManager()
        manager.profiles = [profile]
        let plan = SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: 1,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0
        )
        let state = AdaptiveGameState(profile: profile, plan: plan, profileManager: manager)
        _ = state.processAnswer(state.targetLetter)

        let event = try XCTUnwrap(manager.profiles[0].recentRoundEvents.last)
        XCTAssertEqual(event.cameoLetter, "Z")
    }

    private func firebasePlist() throws -> [String: Any] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"))
        let plist = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any])
        return plist
    }

    private func knownStats(for letters: Set<String>) -> [String: LetterStat] {
        Dictionary(uniqueKeysWithValues: letters.map { ($0, knownStat()) })
    }

    private func mostRecentSunday(onOrBefore day: LocalDay) -> LocalDay {
        var candidate = day
        while !candidate.isSunday() {
            candidate = candidate.adding(days: -1)
        }
        return candidate
    }

    private func cycleStartForDueWeeklyReview(on day: LocalDay) -> LocalDay {
        mostRecentSunday(onOrBefore: day).adding(days: -1)
    }

    private func parentMarkedStats(for letters: Set<String>) -> [String: LetterStat] {
        Dictionary(uniqueKeysWithValues: letters.map { letter in
            var stat = LetterStat()
            stat.parentOverride = .markedKnown(date: Date())
            return (letter, stat)
        })
    }

    private struct StubAudio: CurriculumAudioAvailability {
        let playableWords: Set<String>
        var playableSyllables: Set<String> = []

        init(playableWords: Set<String>) {
            self.playableWords = playableWords
        }

        init(playableWords: Set<String>, playableSyllables: Set<String>) {
            self.playableWords = playableWords
            self.playableSyllables = playableSyllables
        }

        func hasWordAudio(_ key: String, language: GameLanguage) -> Bool {
            playableWords.contains(key)
        }

        func hasSyllableAudio(_ key: String, language: GameLanguage) -> Bool {
            playableSyllables.contains(key)
        }
    }

    private func knownStat(
        correctCount: Int = 8,
        incorrectCount: Int = 0,
        confusedWith: [String: Int] = [:]
    ) -> LetterStat {
        var stat = LetterStat()
        for _ in 0..<correctCount {
            stat.recordTargetAttempt(correct: true, responseTime: 1.0)
        }
        for _ in 0..<incorrectCount {
            stat.recordTargetAttempt(correct: false, responseTime: 1.0)
        }
        for (key, count) in confusedWith {
            for _ in 0..<count {
                stat.recordConfusion(with: key)
            }
        }
        return stat
    }

    private func knownUnitStat() -> UnitProgressStat {
        var stat = UnitProgressStat()
        for _ in 0..<8 {
            stat.recordTargetAttempt(correct: true, responseTime: 1.0)
        }
        return stat
    }

    private func gameSnapshot(
        profile: Profile,
        plan: SessionPlan,
        liveDifficulty: LiveDifficulty = .normal,
        advanceToNextRoundOnRestore: Bool = false
    ) -> GameEngineSnapshot {
        GameEngineSnapshot(
            profileId: profile.id,
            plan: plan,
            savedAt: Date(),
            targetLetter: "P",
            displayedLetters: ["P", "R", "N", "L"],
            currentStreak: 0,
            sessionBestStreak: 0,
            heartsRemaining: 5,
            stampsEarned: [],
            phase: .plainReview,
            roundsThisSession: 0,
            roundsCorrect: 0,
            focusGraduatedThisSession: nil,
            sessionEnded: nil,
            didLevelUpThisSession: false,
            previousTarget: nil,
            practiceProgress: 0,
            totalCorrectThisSession: 0,
            warmupCorrectCount: 0,
            warmupAttemptCount: 0,
            consecutiveWarmupMisses: 0,
            helloFocusAwarded: false,
            seenWarmupLetters: [],
            rescueQueue: [],
            currentRoundIsRescue: false,
            currentRescueDifficulty: nil,
            currentRoundPhaseOverride: nil,
            instructionalBand: profile.snapshot.instructionalBand,
            letterOptionsPerRound: profile.letterOptionsPerRound,
            liveDifficulty: liveDifficulty,
            recentRoundCorrectness: [],
            governorCorrectStreak: 0,
            focusTargetAttemptsThisSession: 0,
            focusTargetCorrectThisSession: 0,
            teachingMode: .normal,
            effectiveScaffoldingLevel: 0,
            remediationFocusLetter: nil,
            preseededRemediationFocusLetter: nil,
            unintroducedExposuresThisSession: 0,
            roundStartedAt: nil,
            roundReplayCount: 0,
            currentRoundIntent: .staleReview,
            secondMissedLetters: [],
            firstMissedLetters: [],
            lastMistakeType: nil,
            lastResponseTime: nil,
            recentCorrectPositions: [],
            recentFocusCorrectPositions: [],
            sessionCorrectPositionCounts: Array(repeating: 0, count: profile.letterOptionsPerRound),
            advanceToNextRoundOnRestore: advanceToNextRoundOnRestore
        )
    }
}
