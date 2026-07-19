//
//  ProfileManager.swift
//  Pismenka
//
//  Owns the on-disk store of profiles and exposes the high-level operations
//  the game/calibration views call (recordAnswer, commitSessionStartIfNeeded,
//  endSession).
//

import Foundation
import Combine

@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published private(set) var lastResetSnapshot: Profile?
    @Published private(set) var persistenceErrorMessage: String?

    /// Storage key for the v2 schema (per-letter mastery, day-streak, focus
    /// letter). The old `pismenka_profiles` key is intentionally left untouched
    /// so old payloads don't poison the new format.
    private let storageKey = "pismenka_profiles_v2"
    private let recoveryStorageKey = "pismenka_profiles_v2_recovery"
    private let lastGoodStorageKey = "pismenka_profiles_v2_last_good"
    private let maxProfiles = 4
    private let defaults: UserDefaults
    var onProfilesSaved: (([Profile]) -> Void)?
    private var isDeferringSaves = false
    private var hasDeferredSave = false

    private let introductionDailyGoal = 25
    private let reviewTestDailyGoal = 50
    private let completedLetterSessionsBeforeAssessment = 6
    private let recentWeeklyAssessmentLimit = 12

    private struct DailyPracticePlanning {
        var kind: DailyPracticeKind
        var goalTarget: Int
        var startCount: Int
        var claimedWinnerCount: Int
        var weeklyReviewLetters: [String]
        var scheduledReviewDay: LocalDay?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadProfiles()
    }

    // MARK: - Profile CRUD

    var canCreateProfile: Bool { profiles.count < maxProfiles }

    func createProfile(name: String, avatar: AvatarType, language: GameLanguage = .system) -> Profile? {
        guard canCreateProfile else { return nil }
        let profile = Profile(name: name, avatarId: avatar, language: language)
        profiles.append(profile)
        saveProfilesImmediately()
        return profile
    }

    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            var updated = profile
            updated.markModified()
            profiles[index] = updated
            saveProfilesImmediately()
        }
    }

    func deleteProfile(_ profile: Profile) {
        lastResetSnapshot = profile
        profiles.removeAll { $0.id == profile.id }
        saveProfilesImmediately()
    }

    func replaceProfiles(_ newProfiles: [Profile]) {
        profiles = Array(newProfiles.prefix(maxProfiles))
        saveProfilesImmediately()
    }

    func replaceProfilesFromCloud(_ newProfiles: [Profile]) {
        profiles = Array(newProfiles.prefix(maxProfiles))
        saveProfilesImmediately()
    }

    /// Wipes all gameplay state for a profile (recalibration on next entry)
    // MARK: - Reset operations
    //
    // Resets come in five granularities, smallest blast radius first. The
    // shape is deliberate: parents shouldn't have to nuke a child's full
    // history just to redo calibration or undo one accidental letter.
    //
    // Across all reset variants, the following items are NEVER touched
    // unless explicitly named: `bestDailyStreak`, `highestAlphabetLevelEverReached`,
    // `celebratedAlphabetLevels`. They're parent-meaningful trophies and
    // celebration receipts; a child should not re-earn a level-up
    // celebration they've already seen just because a parent reset
    // something.

    /// Re-runs the one-time calibration UX without deleting any learning
    /// history. Just flips `hasCompletedCalibration` back to `false` so the
    /// next launch routes through `CalibrationView`. Existing letter stats
    /// stay intact; new attempts during the re-run are added to them
    /// honestly (no duplicate-counting, no synthetic data).
    ///
    /// Use case: parent wants to recheck the baseline after a long break,
    /// or wants the child to enjoy the calibration "warm-up" again.
    func resetCalibrationOnly(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        lastResetSnapshot = profiles[index]
        profiles[index].hasCompletedCalibration = false
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    /// Drops the current focus letter (if any) so the next session picks a
    /// fresh one from `LetterDifficulty.introductionOrder`. Letter stats —
    /// including the previous focus letter's accumulated history — are
    /// preserved verbatim. Streaks and calibration state are untouched.
    ///
    /// Use case: parent realizes the focus letter was a poor pick (kid is
    /// genuinely struggling and getting frustrated), wants to skip to the
    /// next one without losing evidence.
    func resetCurrentFocus(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        lastResetSnapshot = profiles[index]
        profiles[index].currentFocusLetter = nil
        profiles[index].currentSyllableFocus = nil
        profiles[index].currentWordFocus = nil
        profiles[index].focusStartedDay = nil
        profiles[index].focusPracticedDays = []
        // Phase 0d: the "why this letter?" record is about *this* focus
        // letter — once the parent invalidates the focus pick it would
        // be misleading to keep the provenance around. The next session
        // will repopulate it when a new focus is introduced.
        profiles[index].lastFocusSelection = nil
        // `lastNewLetterDay` is intentionally preserved: the "one new
        // letter per calendar day" rule still applies, so dropping the
        // current focus today doesn't entitle the child to a replacement
        // until the next calendar day. That keeps the rule honest.
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    /// Wipes one letter's `LetterStat` entirely — `recentResults`,
    /// `targetAttempts`, `targetCorrect`, `distractorExposures`, all
    /// timestamps, and any `parentOverride`. Also removes the letter from
    /// `everMasteredLetters` (since the data behind that mastery is gone)
    /// and clears the focus state if this letter was the current focus.
    ///
    /// Use case: kid was distracted during a session and the data for one
    /// letter is misleading; or a parent accidentally introduced a letter
    /// and wants it back in the to-be-taught pool fresh.
    ///
    /// `alphabetLevel` may dip if a removed letter was the only thing
    /// keeping the child at their current tier; `highestAlphabetLevelEverReached`
    /// is preserved either way (monotonic trophy).
    func resetLetterStats(profileId: UUID, letter: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var profile = profiles[index]
        lastResetSnapshot = profile
        profile.letterStats.removeValue(forKey: letter)
        profile.everMasteredLetters.remove(letter)
        profile.pausedFocusLetters.remove(letter)
        profile.pausedFocusLetterDays.removeValue(forKey: letter)
        // Phase 0c: also drop the letter from the persisted "introduced" set.
        // This intentionally returns it to the pool of letters the focus
        // picker can choose, which is exactly the parent's intent here —
        // "treat this letter as fresh again."
        profile.introducedLetters.remove(letter)
        if profile.currentFocusLetter == letter {
            profile.currentFocusLetter = nil
            profile.focusStartedDay = nil
            profile.focusPracticedDays = []
        }
        // Phase 0d: if the wiped letter was the most recently picked focus,
        // its provenance record is now meaningless — clear it. Other
        // letters' wipes leave the record alone since it's still describing
        // a real (and still-active) pick.
        if profile.lastFocusSelection?.selectedKey == letter {
            profile.lastFocusSelection = nil
        }
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
    }

    /// Clears the active day streak (`dailyStreakCount` and the day-keyed
    /// session pointer) so the next session bootstraps a fresh streak from
    /// 1. `bestDailyStreak` is intentionally preserved as a lifetime
    /// trophy.
    ///
    /// Use case: family travel produced a streak that doesn't reflect
    /// engagement, or a parent simply wants a clean slate for the
    /// motivational counter without resetting any learning data.
    func resetStreak(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        lastResetSnapshot = profiles[index]
        profiles[index].dailyStreakCount = 0
        // Clearing `lastSessionDay` is what makes the next session
        // bootstrap rather than be a no-op delta=0 update. Without this,
        // zeroing `dailyStreakCount` alone would leave the streak stuck
        // at 0 forever (today == lastSessionDay, "no change" branch).
        profiles[index].lastSessionDay = nil
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    @discardableResult
    func skipActiveWeeklyAssessment(profileId: UUID, today: LocalDay = .today()) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }),
              var assessment = profiles[index].activeWeeklyAssessment,
              !assessment.isCompleted else {
            return false
        }

        assessment.enforceQuestionLimit()
        assessment.complete(on: today)
        profiles[index].activeWeeklyAssessment = nil
        if !profiles[index].recentWeeklyAssessments.contains(where: { $0.id == assessment.id }) {
            profiles[index].recentWeeklyAssessments.append(assessment)
        }
        if profiles[index].recentWeeklyAssessments.count > recentWeeklyAssessmentLimit {
            profiles[index].recentWeeklyAssessments.removeFirst(
                profiles[index].recentWeeklyAssessments.count - recentWeeklyAssessmentLimit
            )
        }
        profiles[index].weeklyIntroducedLetters = []
        profiles[index].completedLetterSessionsInCycle = 0
        profiles[index].learningCycleStartDay = today
        profiles[index].dailyPracticeDay = today
        profiles[index].dailyPracticeAttempts = 0
        profiles[index].dailyPracticeWinnerClaimedDay = today
        profiles[index].dailyPracticeWinnerClaimedMilestone = 0
        profiles[index].markModified()
        saveProfilesImmediately()
        return true
    }

    /// The full reset: clears all learning history, calibration state, all
    /// focus state, all letter stats, the active streak, and the in-game
    /// best-streak counter. Preserves avatar, name, language, and the
    /// trophy fields (`bestDailyStreak`, `highestAlphabetLevelEverReached`,
    /// `celebratedAlphabetLevels`) so an erstwhile expert doesn't get re-shown
    /// every level-up animation as they re-grind back up.
    ///
    /// This is the equivalent of "re-introduce my child to the app from
    /// scratch, but don't pretend they never used it before."
    func resetAllProgress(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        lastResetSnapshot = profiles[index]
        profiles[index].letterStats = [:]
        profiles[index].syllableStats = [:]
        profiles[index].wordStats = [:]
        profiles[index].hasCompletedCalibration = false
        profiles[index].currentFocusLetter = nil
        profiles[index].currentSyllableFocus = nil
        profiles[index].currentWordFocus = nil
        profiles[index].focusStartedDay = nil
        profiles[index].focusPracticedDays = []
        profiles[index].syllablesUnlockedAt = nil
        profiles[index].wordsUnlockedAt = nil
        profiles[index].hasCompletedSyllableOnboarding = false
        profiles[index].hasCompletedSyllableCalibration = false
        profiles[index].hasCompletedWordOnboarding = false
        profiles[index].hasCompletedWordCalibration = false
        profiles[index].readingPracticePaused = false
        profiles[index].lastNewLetterDay = nil
        profiles[index].dailyPracticeDay = nil
        profiles[index].dailyPracticeAttempts = 0
        profiles[index].dailyPracticeWinnerClaimedDay = nil
        profiles[index].dailyPracticeWinnerClaimedMilestone = 0
        profiles[index].dailyTargetAskDay = nil
        profiles[index].dailyTargetAskCounts = [:]
        profiles[index].learningCycleStartDay = nil
        profiles[index].weeklyIntroducedLetters = []
        profiles[index].completedLetterSessionsInCycle = 0
        profiles[index].activeWeeklyAssessment = nil
        profiles[index].recentWeeklyAssessments = []
        profiles[index].lastSessionDay = nil
        profiles[index].dailyStreakCount = 0
        profiles[index].everMasteredLetters = []
        profiles[index].everMasteredSyllables = []
        profiles[index].everMasteredWords = []
        profiles[index].bestSessionStreak = 0
        // Phase 0c: reset the persisted introduced set too. After
        // resetAllProgress the child is genuinely "starting over" from
        // the teaching system's perspective; nothing has been formally
        // introduced yet, and the next session will pick a fresh focus
        // from the top of the introduction order.
        profiles[index].introducedLetters = []
        profiles[index].introducedSyllables = []
        profiles[index].introducedWords = []
        profiles[index].pausedFocusLetters = []
        profiles[index].pausedFocusLetterDays = [:]
        // Phase 0d: a full reset wipes "why was the focus letter X?" too —
        // there is no current focus letter, so there's nothing to provenance.
        profiles[index].lastFocusSelection = nil
        // Phase 0e: drop the round-event log. The narrative history was
        // about a child whose progress is now zeroed out; preserving it
        // would let the dashboard show "they got Č right yesterday"
        // alongside an empty stats table, which is just confusing.
        profiles[index].recentRoundEvents = []
        // bestDailyStreak, highestAlphabetLevelEverReached, and celebratedAlphabetLevels are
        // intentionally preserved — see top-of-section comment.
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    func undoLastReset() {
        guard let snapshot = lastResetSnapshot else { return }
        if let index = profiles.firstIndex(where: { $0.id == snapshot.id }) {
            var restored = snapshot
            restored.markModified()
            profiles[index] = restored
        } else if profiles.count < maxProfiles {
            var restored = snapshot
            restored.markModified()
            profiles.append(restored)
        }
        lastResetSnapshot = nil
        saveProfilesImmediately()
    }

    func markCalibrationComplete(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].hasCompletedCalibration = true
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    // MARK: - Session lifecycle

    /// Builds the daily session shape. `previewSessionPlan` computes the same
    /// shape without touching profile history; `commitSessionStartIfNeeded` commits
    /// day-streak and focus-day state once the child answers at least one round.
    ///
    /// ### Multi-session same-day contract
    ///
    /// Toddlers tap "Play again" all day. The system guarantees:
    ///
    /// | Concern              | Behavior across same-day sessions     | Enforced by                                                     |
    /// |----------------------|---------------------------------------|-----------------------------------------------------------------|
    /// | Target attempts      | **Count, every session**              | `recordAnswer` is session-agnostic; bumps `targetAttempts` per round. |
    /// | Distractor exposures | **Count, every session**              | Same — `recordExposure` / `recordAnswer(asTarget: false)`.       |
    /// | Focus graduation     | **Can happen, any session**           | Graduation check in `recordAnswer` fires whenever the threshold flips, regardless of which session is active. |
    /// | Reading unlock       | **Can be recorded mid-session; onboarding/calibration waits until a later eligible day** | `syllablesUnlockedAt` is day-stamped, and `isSyllableLayerEligible` requires `today > syllablesUnlockedAt`. |
    /// | New focus unit       | **At most once per calendar day**     | `alreadyIntroducedToday = (lastNewLetterDay == today)` gate below; **also** consumed by graduation (see `recordAnswer`) so a mid-session graduation can't unlock a same-day replacement. |
    /// | Day streak           | **Unchanged on a same-day re-entry**  | `delta == 0` branch is a no-op for `dailyStreakCount`.           |
    /// | `focusActiveDays`    | **Unchanged on a same-day re-entry**  | `focusPracticedDays.insert(today)` — `Set` semantics make it idempotent. |
    /// | Stamps               | **Session-local** (fresh card)        | `AdaptiveGameState` is a fresh `@StateObject` per `GameView` lifetime; all stamp/heart/round counters init to zero. |
    /// | Parent dashboard     | **Updates live** as rounds happen     | `recordAnswer` writes through `@Published profiles` and `ParentDashboardView.live` re-derives on each render. |
    ///
    /// Net effect: a child can play 1 / 3 / 10 sessions on day N — they'll
    /// keep accruing attempts, may graduate the active focus, but won't
    /// inflate the day streak, won't earn extra "active days" on the focus
    /// scaffolding ladder, and won't be served a fresh new focus beyond
    /// the day's quota.
    func previewSessionPlan(profileId: UUID, lowercaseMode: LowercaseMode = .uppercaseOnly) -> SessionPlan {
        buildSessionPlan(profileId: profileId, lowercaseMode: lowercaseMode, commit: false)
    }

    func commitSessionStartIfNeeded(profileId: UUID, lowercaseMode: LowercaseMode = .uppercaseOnly) -> SessionPlan {
        buildSessionPlan(profileId: profileId, lowercaseMode: lowercaseMode, commit: true)
    }

    private func buildSessionPlan(
        profileId: UUID,
        lowercaseMode: LowercaseMode = .uppercaseOnly,
        commit: Bool
    ) -> SessionPlan {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return SessionPlan(
                warmupLength: 0,
                introducedNewFocusLetter: false,
                dayStreakCount: 0,
                dayStreakIncreased: false,
                focusLetter: nil,
                focusScaffoldingLevel: 0
            )
        }

        var profile = profiles[index]
        let today = LocalDay.today()

        // 1. Day-streak update. We branch on the signed day delta between
        // today and the last recorded play day:
        //   * delta == 0  → already played today, no change.
        //   * delta == 1  → played yesterday, +1 to the streak.
        //   * delta >= 2  → genuine gap, reset the streak to 1.
        //   * delta <  0  → device clock appears to have moved backward
        //     (time-zone travel, restored backup, manual clock change).
        //     We deliberately *preserve* the streak here — a child should
        //     not lose their day streak because a parent flew across a
        //     date line, and a backward clock can't be allowed to be a
        //     loophole that resets the streak the way a forward gap does.
        //     We also skip every other day-keyed mutation below so a
        //     rolled-back clock can't be used to inject extra "one new
        //     letter per day" introductions or pollute focusPracticedDays.
        var streakIncreased = false
        var clockMovedBackward = false
        if let last = profile.lastSessionDay {
            let delta = today.daysSince(last)
            if delta < 0 {
                clockMovedBackward = true
                #if DEBUG
                print("⚠️ ProfileManager: clock moved backward " +
                      "(today=\(today.iso8601), last=\(last.iso8601), delta=\(delta)): " +
                      "preserving streak=\(profile.dailyStreakCount)")
                #endif
            } else if delta == 0 {
                // Same calendar day — multi-session-same-day contract:
                // streak does NOT advance on a "Play again" tap. The
                // child already got credit for showing up today; the
                // motivation here is round-level, not return-to-app-level.
            } else if delta == 1 {
                profile.dailyStreakCount += 1
                streakIncreased = true
            } else {  // delta >= 2
                profile.dailyStreakCount = 1
                streakIncreased = true
            }
        } else {
            profile.dailyStreakCount = 1
            streakIncreased = true
        }
        if profile.dailyStreakCount > profile.bestDailyStreak {
            profile.bestDailyStreak = profile.dailyStreakCount
        }

        var dailyPractice = resolveDailyPractice(
            profile: &profile,
            today: today,
            commit: commit,
            clockMovedBackward: clockMovedBackward
        )

        // 2. Focus letter logic. Only runs on forward-time days. On a
        // clock-moved-backward day we deliberately mutate nothing
        // calendar-tied — no new focus introduction, no
        // focusPracticedDays write, no lastSessionDay update — so the
        // next genuine forward-time session picks things up cleanly
        // against the original `lastSessionDay`.
        let alreadyIntroducedToday = profile.lastNewLetterDay == today
        var introducedNewFocus = false
        var introducedFocusTarget: FocusTarget?
        var dailySpotlightLetter: String?
        var pausedStuckFocusToday = false
        let primaryLayer: LearningLayer = .letters
        let activityKind: LearningActivityKind = .letterRecognition

        if !clockMovedBackward {
            profile.clearExpiredPausedFocusLetters(on: today)
            if shouldPauseStuckLetterFocus(profile: profile) {
                if let focus = profile.currentFocusLetter {
                    profile.pausedFocusLetters.insert(focus)
                    profile.pausedFocusLetterDays[focus] = today
                }
                profile.currentFocusLetter = nil
                profile.focusStartedDay = nil
                profile.focusPracticedDays = []
                profile.lastFocusSelection = nil
                profile.lastNewLetterDay = today
                pausedStuckFocusToday = true
            }

            // Reading layers are intentionally dormant in the current release.
            // Keep the persisted fields/model types for future versions, but
            // do not unlock or schedule syllable/word sessions.
            profile.syllablesUnlockedAt = nil
            profile.wordsUnlockedAt = nil
            profile.currentSyllableFocus = nil
            profile.currentWordFocus = nil

            if dailyPractice.kind == .introduction,
               !alreadyIntroducedToday,
               !pausedStuckFocusToday,
               let selection = pickNextDailyIntroductionLetter(profile: profile, lowercaseMode: lowercaseMode) {
                let next = selection.key
                dailySpotlightLetter = next
                profile.lastNewLetterDay = today
                profile.introducedLetters.insert(next)
                introducedNewFocus = true
                introducedFocusTarget = .letter(next)
                profile.weeklyIntroducedLetters.insert(next)
                if profile.currentFocusLetter == nil {
                    profile.currentFocusLetter = next
                    profile.focusStartedDay = today
                    profile.focusPracticedDays = [today]
                    profile.lastFocusSelection = FocusSelectionReason(
                        selectedKey: next,
                        date: Date(),
                        reason: selection.reason
                    )
                } else {
                    profile.focusPracticedDays.insert(today)
                }
            } else if profile.currentFocusLetter != nil {
                profile.focusPracticedDays.insert(today)
            } else {
                profile.focusStartedDay = nil
                profile.focusPracticedDays = []
            }

            profile.lastSessionDay = today
        }

        // Expert maintenance should match the amount of due work instead of
        // forcing a 25-answer round-robin through already-stable letters.
        if primaryLayer == .letters,
           dailyPractice.kind == .introduction,
           profile.currentFocusLetter == nil,
           dailySpotlightLetter == nil,
           profile.alphabetLevel == .expert {
            let dueCount = profile.snapshot.dueReviewLetters.count
            let auditCount = min(2, profile.snapshot.auditReviewLetters.count)
            dailyPractice.goalTarget = min(15, max(5, dueCount * 2 + auditCount))
        }

        if primaryLayer != .letters {
            dailyPractice = DailyPracticePlanning(
                kind: .introduction,
                goalTarget: introductionDailyGoal,
                startCount: dailyPractice.startCount,
                claimedWinnerCount: dailyPractice.claimedWinnerCount,
                weeklyReviewLetters: [],
                scheduledReviewDay: nil
            )
        }

        if commit, primaryLayer == .letters, dailyPractice.kind == .reviewTest {
            startWeeklyAssessmentIfNeeded(
                profile: &profile,
                scheduledFor: dailyPractice.scheduledReviewDay,
                cohortLetters: dailyPractice.weeklyReviewLetters,
                today: today
            )
        }

        if commit {
            profile.markModified()
            profiles[index] = profile
            saveProfilesImmediately()
        }

        let knownCount = profile.knownLetters.count
        let baseWarmup: Int
        if knownCount >= 6 { baseWarmup = 5 }
        else if knownCount >= 4 { baseWarmup = 3 }
        else if knownCount >= 3 { baseWarmup = 2 }
        else { baseWarmup = 0 }
        let dueWarmupCount = profile.snapshot.dueReviewLetters
            .filter { profile.knownLetters.contains($0) }
            .count
        let warmup = baseWarmup == 0 ? 0 : min(baseWarmup, max(1, dueWarmupCount))

        let sessionFocusLetter = dailyPractice.kind == .reviewTest ? nil : profile.currentFocusLetter
        let focusTarget = dailyPractice.kind == .reviewTest ? nil : profile.currentFocusTarget

        return SessionPlan(
            warmupLength: warmup,
            introducedNewFocusLetter: introducedNewFocus,
            introducedFocusTarget: introducedFocusTarget,
            dayStreakCount: profile.dailyStreakCount,
            dayStreakIncreased: streakIncreased,
            focusLetter: sessionFocusLetter,
            focusTarget: focusTarget,
            primaryLayer: primaryLayer,
            activityKind: activityKind,
            focusScaffoldingLevel: profile.focusScaffoldingLevel,
            dailyGoalTarget: dailyPractice.goalTarget,
            dailyGoalStartCount: dailyPractice.startCount,
            dailyGoalClaimedCount: dailyPractice.claimedWinnerCount,
            dailyPracticeKind: dailyPractice.kind,
            weeklyReviewLetters: dailyPractice.weeklyReviewLetters,
            dailySpotlightLetter: dailySpotlightLetter
        )
    }

    private func resolveDailyPractice(
        profile: inout Profile,
        today: LocalDay,
        commit: Bool,
        clockMovedBackward: Bool
    ) -> DailyPracticePlanning {
        var startCount = profile.dailyPracticeCount(on: today)

        if !clockMovedBackward {
            if profile.dailyPracticeDay != today {
                startCount = 0
                if commit {
                    profile.dailyPracticeDay = today
                    profile.dailyPracticeAttempts = 0
                    profile.dailyPracticeWinnerClaimedDay = today
                    profile.dailyPracticeWinnerClaimedMilestone = 0
                }
            }
            let claimedWinnerCount = profile.dailyPracticeWinnerClaimedCount(on: today)

            if let assessment = profile.activeWeeklyAssessment,
               assessment.isCompleted,
               assessment.completedOn != today {
                profile.activeWeeklyAssessment = nil
                profile.weeklyIntroducedLetters = []
                profile.completedLetterSessionsInCycle = 0
                profile.learningCycleStartDay = today
            }

            normalizeActiveWeeklyAssessment(profile: &profile, today: today)

            if let assessment = profile.activeWeeklyAssessment {
                return DailyPracticePlanning(
                    kind: .reviewTest,
                    goalTarget: assessment.dailyGoalTarget,
                    startCount: weeklyAssessmentStartCount(for: assessment, dailyPracticeStartCount: startCount),
                    claimedWinnerCount: claimedWinnerCount,
                    weeklyReviewLetters: assessment.cohortLetters,
                    scheduledReviewDay: assessment.scheduledFor
                )
            }

            normalizeWeeklyCycleIfNeeded(profile: &profile, today: today)

            let reviewDue = profile.completedLetterSessionsInCycle
                >= completedLetterSessionsBeforeAssessment
            let assessmentPreview = reviewDue
                ? profile.buildAdaptiveWeeklyAssessment(scheduledFor: today, startedOn: today, legacyDailyGoal: reviewTestDailyGoal)
                : nil
            let reviewLetters = assessmentPreview?.cohortLetters ?? []
            let kind: DailyPracticeKind = reviewDue && !reviewLetters.isEmpty ? .reviewTest : .introduction

            return DailyPracticePlanning(
                kind: kind,
                goalTarget: kind == .reviewTest ? (assessmentPreview?.dailyGoalTarget ?? reviewTestDailyGoal) : introductionDailyGoal,
                startCount: startCount,
                claimedWinnerCount: claimedWinnerCount,
                weeklyReviewLetters: kind == .reviewTest ? reviewLetters : [],
                scheduledReviewDay: kind == .reviewTest ? today : nil
            )
        }

        let claimedWinnerCount = profile.dailyPracticeWinnerClaimedCount(on: today)

        normalizeActiveWeeklyAssessment(profile: &profile, today: today)

        if let assessment = profile.activeWeeklyAssessment {
            return DailyPracticePlanning(
                kind: .reviewTest,
                goalTarget: assessment.dailyGoalTarget,
                startCount: weeklyAssessmentStartCount(for: assessment, dailyPracticeStartCount: startCount),
                claimedWinnerCount: claimedWinnerCount,
                weeklyReviewLetters: assessment.cohortLetters,
                scheduledReviewDay: assessment.scheduledFor
            )
        }

        let reviewDue = profile.completedLetterSessionsInCycle
            >= completedLetterSessionsBeforeAssessment
        let assessmentPreview = reviewDue
            ? profile.buildAdaptiveWeeklyAssessment(scheduledFor: today, startedOn: today, legacyDailyGoal: reviewTestDailyGoal)
            : nil
        let reviewLetters = assessmentPreview?.cohortLetters ?? []
        let kind: DailyPracticeKind = reviewDue && !reviewLetters.isEmpty ? .reviewTest : .introduction
        return DailyPracticePlanning(
            kind: kind,
            goalTarget: kind == .reviewTest ? (assessmentPreview?.dailyGoalTarget ?? reviewTestDailyGoal) : introductionDailyGoal,
            startCount: startCount,
            claimedWinnerCount: claimedWinnerCount,
            weeklyReviewLetters: kind == .reviewTest ? reviewLetters : [],
            scheduledReviewDay: kind == .reviewTest ? today : nil
        )
    }

    private func normalizeActiveWeeklyAssessment(profile: inout Profile, today: LocalDay) {
        guard var assessment = profile.activeWeeklyAssessment else { return }
        assessment.enforceQuestionLimit()
        profile.activeWeeklyAssessment = assessment
        completeWeeklyAssessmentIfNeeded(profile: &profile, today: today)
    }

    private func weeklyAssessmentStartCount(
        for assessment: WeeklyLetterAssessment,
        dailyPracticeStartCount: Int
    ) -> Int {
        max(
            dailyPracticeStartCount,
            min(assessment.dailyGoalTarget, assessment.independentAssessmentAttempts)
        )
    }

    private func normalizeWeeklyCycleIfNeeded(profile: inout Profile, today: LocalDay) {
        guard let cycleStart = profile.learningCycleStartDay else {
            profile.learningCycleStartDay = today
            return
        }
        if today.daysSince(cycleStart) < 0 {
            // The trigger is session-count based, so a clock correction only
            // repairs the informational start date; earned sessions/cohort
            // remain intact.
            profile.learningCycleStartDay = today
        }
    }

    private func startWeeklyAssessmentIfNeeded(
        profile: inout Profile,
        scheduledFor: LocalDay?,
        cohortLetters: [String],
        today: LocalDay
    ) {
        guard profile.activeWeeklyAssessment == nil,
              let scheduledFor,
              !cohortLetters.isEmpty else {
            return
        }
        let assessment = profile.buildAdaptiveWeeklyAssessment(
            scheduledFor: scheduledFor,
            startedOn: today,
            legacyDailyGoal: reviewTestDailyGoal
        )
        guard !assessment.cohortLetters.isEmpty else { return }
        profile.activeWeeklyAssessment = assessment
    }

    private func isSyllableLayerEligible(
        profile: Profile,
        today: LocalDay,
        audioService: AudioService
    ) -> Bool {
        guard profile.language.resolvedLanguage == .czech,
              !profile.readingPracticePaused,
              profile.hasCompletedAlphabetForReading,
              let unlockedAt = profile.syllablesUnlockedAt,
              today.daysSince(unlockedAt) > 0 else {
            return false
        }
        return hasAnyPlayableSyllable(profile: profile, audioService: audioService)
    }

    private func hasAnyPlayableSyllable(profile: Profile, audioService: AudioService) -> Bool {
        guard profile.hasCompletedAlphabetForReading else { return false }
        return SyllableCurriculum.allKeys(for: profile.language).contains { key in
            SyllableCurriculum.prerequisitesMet(for: key, profile: profile)
                && audioService.hasSyllableAssets(key, language: profile.language)
        }
    }

    private func shouldPauseStuckLetterFocus(profile: Profile) -> Bool {
        guard let focus = profile.currentFocusLetter,
              let stat = profile.letterStats[focus],
              profile.focusActiveDays >= 8 else {
            return false
        }
        return stat.recentAccuracy(window: 5) < 0.5
    }

    func completeSyllableCalibration(profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].hasCompletedSyllableOnboarding = true
        profiles[index].hasCompletedSyllableCalibration = true
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    func startPracticeSession(profileId: UUID, letter: String) -> SessionPlan {
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            return SessionPlan(
                warmupLength: 0,
                introducedNewFocusLetter: false,
                dayStreakCount: 0,
                dayStreakIncreased: false,
                focusLetter: nil,
                focusScaffoldingLevel: 0,
                mode: .extraPractice(letter: letter)
            )
        }
        return SessionPlan(
            warmupLength: 0,
            introducedNewFocusLetter: false,
            dayStreakCount: profile.dailyStreakCount,
            dayStreakIncreased: false,
            focusLetter: nil,
            focusScaffoldingLevel: 0,
            mode: .extraPractice(letter: letter)
        )
    }

    /// Called when the player exits the game (any reason). Persists the best
    /// session streak and forces an immediate save — session-end is an
    /// important moment to checkpoint.
    func endSession(profileId: UUID, summary: SessionSummary) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        if summary.bestSessionStreak > profiles[index].bestSessionStreak {
            profiles[index].bestSessionStreak = summary.bestSessionStreak
            profiles[index].markModified()
        }
        saveProfilesImmediately()
    }

    func claimDailyPracticeWinner(profileId: UUID, milestone: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var profile = profiles[index]
        let previousClaimedMilestone = profile.dailyPracticeWinnerClaimedCount()
        let wasAssessmentActive = profile.activeWeeklyAssessment != nil
        profile.claimDailyPracticeWinner(milestone: milestone)
        if !wasAssessmentActive {
            let previouslyCompleted = previousClaimedMilestone / introductionDailyGoal
            let nowCompleted = milestone / introductionDailyGoal
            let newlyCompleted = max(0, nowCompleted - previouslyCompleted)
            if newlyCompleted > 0 {
                if profile.learningCycleStartDay == nil {
                    profile.learningCycleStartDay = LocalDay.today()
                }
                profile.completedLetterSessionsInCycle = min(
                    completedLetterSessionsBeforeAssessment,
                    profile.completedLetterSessionsInCycle + newlyCompleted
                )
            }
        }
        // Reaching the visible daily goal on a weekly-test day finalizes the
        // test. The progress bar counts every round (warmup, rescue, filler
        // review), so a child can reach the goal (e.g. 40/40) without the
        // audit's independent-evidence quota being met. Without finalizing
        // here, the test stayed "active" and reopened the next day seeded from
        // the lower independent-attempt count (e.g. 35/40), forcing a manual
        // end. A claimable milestone is always a full multiple of the goal, so
        // milestone >= dailyGoalTarget means the bar genuinely hit the goal.
        if let assessment = profile.activeWeeklyAssessment,
           !assessment.isCompleted,
           milestone >= assessment.dailyGoalTarget {
            finalizeActiveWeeklyAssessment(profile: &profile, today: LocalDay.today())
        }
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
    }

    // MARK: - Answer recording

    /// Records a single round outcome for the given letter and reports back
    /// any side-effects the view needs to celebrate.
    ///
    /// `asTarget == true` means the child was *asked* to identify this letter
    /// (it was the target of the round) and either tapped it (`wasCorrect`
    /// true) or tapped some other letter (`wasCorrect` false). Only target
    /// attempts move `recentResults`, `targetAttempts`, and `targetCorrect`,
    /// and only target attempts can graduate the focus letter.
    ///
    /// `asTarget == false` is treated as a distractor exposure: the letter
    /// was on screen but wasn't the target. It bumps `distractorExposures`
    /// and refreshes `lastSeenAt` only — never affecting accuracy or mastery.
    ///
    /// ### Phase 1c (R6, R7, #16 fixes)
    ///
    /// The signature gained a stack of optional round-context parameters
    /// that older call sites can ignore — defaults preserve the previous
    /// 4-arg behavior verbatim. New call sites pass them so the
    /// persistence layer can:
    ///
    /// * Apply the impulse-tap **learning discount** (R6). When
    ///   `mistakeType == .impulsiveTap`, the wrong tap is excluded from
    ///   `recentResults`/`targetAttempts`/`targetCorrect`. The round is
    ///   still recorded as an exposure (so `lastSeenAt` updates and the
    ///   on-screen time isn't lost), and the response time still feeds
    ///   `recentResponseTimes` (the speed signal is real even when the
    ///   accuracy signal is bogus).
    /// * Route confusion vs. impulse evidence **separately** (R7).
    ///   Genuine confusions bump `confusedWith` (which Phase 3a's
    ///   contrast-pair scanner reads); impulse taps bump
    ///   `impulsiveSelections` instead, keeping the confusion signal
    ///   clean.
    /// * Detect **slips** (#16). When the call flips a letter's
    ///   data-driven `isKnown` from `true` to `false`, the stat's
    ///   `wasKnownBefore` and `demotedAt` are set so Phase 4b's
    ///   recently-slipped chevron has its evidence.
    /// * Append a **`RoundEvent`** to the profile's rolling log
    ///   (Phase 0e shape, FIFO-capped at `RoundEvent.maxRetained`),
    ///   carrying the full per-round narrative for the parent
    ///   dashboard.
    @discardableResult
    func recordAnswer(
        profileId: UUID,
        letter: String,
        wasCorrect: Bool,
        asTarget: Bool,
        responseTime: TimeInterval? = nil,
        didReplayPrompt: Bool = false,
        replayCount: Int = 0,
        mistakeType: MistakeType = .unknown,
        selectedWrongLetter: String? = nil,
        optionsShown: [String] = [],
        intent: RoundIntent = .warmupConfidence,
        phaseAtAnswer: RoundPhase = .drill,
        heartsAfter: Int? = nil,
        liveDifficulty: LiveDifficulty? = nil,
        isRescue: Bool = false,
        rescueDifficulty: RescueDifficulty? = nil,
        attemptContext: AttemptContext? = nil,
        cameoLetter: String? = nil,
        includedFocusAsDistractor: Bool = false,
        planReason: RoundPlanReason? = nil,
        countsTowardDailyPractice: Bool = false
    ) -> RecordedAnswer {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return RecordedAnswer()
        }
        var profile = profiles[index]
        if asTarget && !LetterDifficulty.isEligibleTarget(letter, language: profile.language) {
            return RecordedAnswer()
        }

        var stat = profile.letterStats[letter] ?? LetterStat()
        // Snapshot the data-driven `isKnown` before we mutate. Slip
        // detection (#16) compares this to the post-mutation value — a
        // true→false flip is what marks the letter as "recently slipped"
        // for the parent dashboard.
        let oldIsKnown = stat.isKnown

        // R6 fix: a sub-impulse-threshold wrong tap is treated as
        // "didn't actually try" and excluded from learning signals.
        // Correct answers and non-impulse mistakes (confusion / timeout
        // / unknown) all count normally. The session-mechanics layer
        // (Phase 1d's heart accounting) makes the parallel decision
        // independently from the same `mistakeType`.
        let context = attemptContext ?? .independent
        let discountedForImpulse = mistakeType == .impulsiveTap
        let shouldCountForLearning = !discountedForImpulse && !context.isAssistedForMastery

        if asTarget {
            if shouldCountForLearning {
                stat.recordTargetAttempt(correct: wasCorrect, responseTime: responseTime)
            } else {
                // Discounted impulse tap: the letter was on screen, the
                // round happened, but the accuracy signal would be
                // misleading. Treat it as exposure so `lastSeenAt`,
                // `firstSeenAt`, and `distractorExposures` still
                // update — the child *did* see the letter — and
                // append the response time independently below so the
                // speed signal isn't lost either.
                stat.recordDistractorExposure()
                if let rt = responseTime {
                    let cleaned = max(0, rt)
                    // Same distraction-outlier rule as `recordTargetAttempt`:
                    // anything at or above the cutoff is almost certainly
                    // a "kid looked away" event, not recognition latency,
                    // and shouldn't pollute the fluency median.
                    if cleaned < LetterStat.distractionResponseCutoff {
                        stat.recentResponseTimes.append(cleaned)
                        if stat.recentResponseTimes.count > LetterStat.responseTimeWindow {
                            let drop = stat.recentResponseTimes.count - LetterStat.responseTimeWindow
                            stat.recentResponseTimes.removeFirst(drop)
                        }
                    }
                }
            }
            // Replay tracking is independent of the discount: a child
            // who tapped the speaker before tapping a wrong letter
            // still asked to hear the prompt, regardless of whether
            // the wrong tap counts toward learning.
            if didReplayPrompt {
                stat.recordPromptReplay()
            }
            // Wrong-tap routing (R7 fix). Confusion evidence drives
            // contrast rounds (Phase 3a); impulse evidence drives the
            // dashboard impulse-prone hint but stays out of the
            // contrast scanner.
            if !wasCorrect, let wrongKey = selectedWrongLetter {
                if shouldCountForLearning {
                    stat.recordConfusion(with: wrongKey)
                } else if discountedForImpulse {
                    stat.recordImpulsiveSelection(of: wrongKey)
                } else {
                    stat.recordConfusion(with: wrongKey)
                }
            }
            if !context.isAssistedForMastery, shouldCountForLearning {
                for option in Set(optionsShown) where option != letter {
                    guard LetterDifficulty.isEligibleTarget(option, language: profile.language) else {
                        continue
                    }
                    let wasPairMistake = !wasCorrect
                        && mistakeType == .confusion
                        && selectedWrongLetter == option
                    stat.recordConfusionOpportunity(with: option, wasMistake: wasPairMistake)
                }
            }
            // Phase 0c (#8 fix): a target round is, by definition, the
            // app intentionally teaching this letter. Mark it
            // introduced. This is the second of the two writers (the
            // first is the focus-assignment path in
            // `commitSessionStartIfNeeded`); fallback distractor exposures
            // deliberately do NOT take this branch and so cannot
            // inflate the persisted set.
            profile.introducedLetters.insert(letter)
            // Every target ask counts toward the per-day exposure cap,
            // impulse-discounted or not — the child saw the round either
            // way. New sittings seed the engine's session counts from
            // this map so the "max 10 asks of one letter" rule holds per
            // calendar day, not just per app sitting.
            profile.recordDailyTargetAsk(letter: letter)
        } else {
            stat.recordDistractorExposure()
        }

        // Slip detection (#16). Only meaningful on target attempts —
        // distractor exposures don't move the recent-results window so
        // the `isKnown` value is unchanged anyway. Still, gating on
        // `asTarget` keeps the intent obvious.
        if asTarget && oldIsKnown && !stat.isKnown {
            stat.wasKnownBefore = true
            stat.demotedAt = Date()
        }
        profile.letterStats[letter] = stat
        if asTarget,
           !context.isAssistedForMastery,
           shouldCountForLearning,
           [4, 6, 8].contains(optionsShown.count) {
            var gridStat = profile.gridPerformanceStats[optionsShown.count] ?? GridPerformanceStat()
            gridStat.record(correct: wasCorrect)
            profile.gridPerformanceStats[optionsShown.count] = gridStat
        }
        if asTarget && countsTowardDailyPractice {
            // Only correct answers advance the ordinary daily goal, so a wrong
            // tap (including a deliberate one) earns no credit toward the Winner
            // button. The weekly review/test is the exception: it is a
            // fixed-length audit, so every answered round counts toward it. An
            // active weekly assessment is present exactly on review/test days
            // (it is committed before the first answer), which is the signal we
            // use to relax the correct-answer requirement here.
            //
            // Assessment evidence below is still recorded for both correct and
            // incorrect answers regardless — the audit needs to see misses.
            let isWeeklyReviewTest = profile.activeWeeklyAssessment != nil
            if wasCorrect || isWeeklyReviewTest {
                profile.recordDailyPracticeAttempt()
            }
            if context == .independent,
               shouldCountForLearning,
               intent == .weeklyAssessment {
                profile.activeWeeklyAssessment?.recordIndependentAttempt(
                    letter: letter,
                    wasCorrect: wasCorrect,
                    responseTime: responseTime
                )
            }
            completeWeeklyAssessmentIfNeeded(profile: &profile, today: LocalDay.today())
        }

        var graduatedThisCall: String?
        var leveledUpTo: AlphabetLevel?

        // Formal mastery belongs to the introduced letter, not to the
        // current-focus pointer. Daily spotlight letters are legitimate
        // teaching targets and may reach 7/8 while an older focus remains.
        // Any introduced letter that proves the strict criterion therefore
        // enters lifetime mastery; only the matching current focus is cleared.
        if asTarget,
           shouldCountForLearning,
           profile.introducedLetters.contains(letter),
           !profile.everMasteredLetters.contains(letter),
           stat.isFocusGraduated {
            graduatedThisCall = letter
            profile.everMasteredLetters.insert(letter)
            if profile.currentFocusLetter == letter {
                profile.currentFocusLetter = nil
                profile.focusStartedDay = nil
                profile.focusPracticedDays = []
                // A focus graduation consumes today's introduction quota so a
                // same-day replay cannot immediately assign another focus.
                profile.lastNewLetterDay = LocalDay.today()
            }

            // Level-up detection: a celebration fires for a given `AlphabetLevel`
            // at most once per profile, ever. The receipt is the
            // `celebratedAlphabetLevels` set — durable across sessions, preserved
            // through `resetProgress`, and indifferent to any future demotion
            // / recovery path. We deliberately do NOT compare before vs.
            // after counts or levels: that arithmetic is easy to falsify with
            // explicit resets, data restore, demotion mechanics, or transient
            // bugs.
            let afterLevel = AlphabetLevel.from(
                letterMasteredCount: profile.everMasteredLetters.count,
                language: profile.language
            )
            if profile.language.resolvedLanguage == .czech,
               profile.hasCompletedAlphabetForReading,
               profile.syllablesUnlockedAt == nil {
                profile.syllablesUnlockedAt = LocalDay.today()
            }
            if afterLevel > profile.highestAlphabetLevelEverReached {
                profile.highestAlphabetLevelEverReached = afterLevel
            }
            if !profile.celebratedAlphabetLevels.contains(afterLevel) {
                profile.celebratedAlphabetLevels.insert(afterLevel)
                leveledUpTo = afterLevel
            }
        }

        // Phase 0e/1c: append the RoundEvent. We keep this inside the
        // `recordAnswer` call so "one round = one event"; pure
        // distractor `recordExposure` calls intentionally don't append
        // their own events because they're sub-events of whichever
        // round just produced the target call.
        //
        // For a wrong target with no `selectedWrongLetter` provided
        // (legacy callers that haven't migrated to passing the wrong
        // tap), we leave `selected = ""` — better an obviously-empty
        // log entry than a synthesized one that pretends to know what
        // the child tapped.
        let selectedKey: String
        if wasCorrect {
            selectedKey = letter
        } else {
            selectedKey = selectedWrongLetter ?? ""
        }
        let wasDiscounted = asTarget && !shouldCountForLearning
        let event = RoundEvent(
            date: Date(),
            target: letter,
            options: optionsShown,
            selected: selectedKey,
            wasCorrect: wasCorrect,
            responseTime: responseTime,
            phase: phaseAtAnswer,
            intent: intent,
            mistakeType: wasCorrect ? nil : mistakeType,
            didReplayPrompt: didReplayPrompt,
            replayCount: replayCount,
            wasDiscounted: wasDiscounted,
            heartsAfter: heartsAfter,
            liveDifficulty: liveDifficulty,
            isRescue: isRescue,
            rescueDifficulty: rescueDifficulty,
            attemptContext: context,
            cameoLetter: cameoLetter,
            includedFocusAsDistractor: includedFocusAsDistractor,
            planReason: planReason
        )
        profile.appendRoundEvent(event)

        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()

        return RecordedAnswer(focusGraduated: graduatedThisCall, leveledUp: leveledUpTo)
    }

    private func completeWeeklyAssessmentIfNeeded(profile: inout Profile, today: LocalDay) {
        guard let assessment = profile.activeWeeklyAssessment,
              !assessment.isCompleted else {
            return
        }
        let attemptsToday = profile.dailyPracticeCount(on: today)
        let shouldComplete: Bool
        switch assessment.strategy {
        case .legacyCohort:
            shouldComplete = attemptsToday >= assessment.dailyGoalTarget
        case .adaptiveAudit:
            shouldComplete = assessment.isAssessmentResolved
                || (assessment.hasCoveredEveryLetter && assessment.independentAssessmentAttempts >= assessment.hardRoundCap)
        }
        guard shouldComplete else { return }
        finalizeActiveWeeklyAssessment(profile: &profile, today: today)
    }

    /// Stamps the active weekly assessment as completed, archives a copy into
    /// history, and resets the learning cycle so the next local day starts a
    /// fresh introduction cycle. The active assessment is intentionally left in
    /// place (not cleared) so a same-day "play again" still works as filler
    /// review; the next-day rollover in `resolveDailyPractice` clears it.
    private func finalizeActiveWeeklyAssessment(profile: inout Profile, today: LocalDay) {
        guard var assessment = profile.activeWeeklyAssessment,
              !assessment.isCompleted else {
            return
        }
        assessment.complete(on: today)
        let now = Date()
        for letter in assessment.needsReviewLetters {
            guard var stat = profile.letterStats[letter] else { continue }
            stat.scheduleFollowUp(afterDays: 1, from: now)
            profile.letterStats[letter] = stat
        }
        for letter in assessment.watchLetters {
            guard var stat = profile.letterStats[letter] else { continue }
            stat.scheduleFollowUp(afterDays: 3, from: now)
            profile.letterStats[letter] = stat
        }
        profile.activeWeeklyAssessment = assessment
        profile.recentWeeklyAssessments.append(assessment)
        if profile.recentWeeklyAssessments.count > recentWeeklyAssessmentLimit {
            profile.recentWeeklyAssessments.removeFirst(profile.recentWeeklyAssessments.count - recentWeeklyAssessmentLimit)
        }
        profile.weeklyIntroducedLetters = []
        profile.completedLetterSessionsInCycle = 0
        profile.learningCycleStartDay = today
    }

    @discardableResult
    func recordAnswer(
        profileId: UUID,
        target: FocusTarget,
        wasCorrect: Bool,
        asTarget: Bool,
        responseTime: TimeInterval? = nil,
        didReplayPrompt: Bool = false,
        replayCount: Int = 0,
        mistakeType: MistakeType = .unknown,
        selectedWrongTarget: FocusTarget? = nil,
        optionsShown: [FocusTarget] = [],
        intent: RoundIntent = .warmupConfidence,
        phaseAtAnswer: RoundPhase = .drill,
        activityKind: LearningActivityKind? = nil,
        heartsAfter: Int? = nil,
        liveDifficulty: LiveDifficulty? = nil,
        isRescue: Bool = false,
        rescueDifficulty: RescueDifficulty? = nil,
        attemptContext: AttemptContext? = nil,
        cameoLetter: String? = nil,
        includedFocusAsDistractor: Bool = false,
        planReason: RoundPlanReason? = nil,
        countsTowardDailyPractice: Bool = false
    ) -> RecordedAnswer {
        switch target {
        case .letter(let letter):
            return recordAnswer(
                profileId: profileId,
                letter: letter,
                wasCorrect: wasCorrect,
                asTarget: asTarget,
                responseTime: responseTime,
                didReplayPrompt: didReplayPrompt,
                replayCount: replayCount,
                mistakeType: mistakeType,
                selectedWrongLetter: selectedWrongTarget?.rawKey,
                optionsShown: optionsShown.map(\.rawKey),
                intent: intent,
                phaseAtAnswer: phaseAtAnswer,
                heartsAfter: heartsAfter,
                liveDifficulty: liveDifficulty,
                isRescue: isRescue,
                rescueDifficulty: rescueDifficulty,
                attemptContext: attemptContext,
                cameoLetter: cameoLetter,
                includedFocusAsDistractor: includedFocusAsDistractor,
                planReason: planReason,
                countsTowardDailyPractice: countsTowardDailyPractice
            )
        case .syllable, .word:
            break
        }

        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return RecordedAnswer()
        }
        var profile = profiles[index]
        let context = attemptContext ?? .independent
        let discountedForImpulse = mistakeType == .impulsiveTap
        let shouldCountForLearning = !discountedForImpulse && !context.isAssistedForMastery
        var graduatedThisCall: String?
        var leveledUpTo: AlphabetLevel?
        let selectedKey = wasCorrect ? target.storageKey : (selectedWrongTarget?.storageKey ?? "")

        func updateLevelReceipts(on profile: inout Profile) {
            let afterLevel = AlphabetLevel.from(
                letterMasteredCount: profile.everMasteredLetters.count,
                language: profile.language
            )
            if afterLevel > profile.highestAlphabetLevelEverReached {
                profile.highestAlphabetLevelEverReached = afterLevel
            }
            if !profile.celebratedAlphabetLevels.contains(afterLevel) {
                profile.celebratedAlphabetLevels.insert(afterLevel)
                leveledUpTo = afterLevel
            }
        }

        switch target {
        case .letter:
            break
        case .syllable(let syllable):
            guard SyllableCurriculum.isCurriculumSyllable(syllable, language: profile.language) else {
                return RecordedAnswer()
            }
            var stat = profile.syllableStats[syllable] ?? SyllableStat()
            let wasGraduated = stat.isFocusGraduated
            let oldKnown = stat.isKnown
            if asTarget {
                if shouldCountForLearning {
                    stat.recordTargetAttempt(correct: wasCorrect, responseTime: responseTime)
                } else {
                    stat.recordDistractorExposure()
                }
                if didReplayPrompt { stat.recordPromptReplay() }
                if !wasCorrect, let wrong = selectedWrongTarget {
                    if shouldCountForLearning {
                        stat.recordConfusion(with: wrong.storageKey)
                    } else if discountedForImpulse {
                        stat.recordImpulsiveSelection(of: wrong.storageKey)
                    } else {
                        stat.recordConfusion(with: wrong.storageKey)
                    }
                }
                profile.introducedSyllables.insert(syllable)
                if countsTowardDailyPractice && wasCorrect {
                    profile.recordDailyPracticeAttempt()
                }
            } else {
                stat.recordDistractorExposure()
            }
            if asTarget && oldKnown && !stat.isKnown {
                stat.wasKnownBefore = true
                stat.demotedAt = Date()
            }
            profile.syllableStats[syllable] = stat

            if asTarget,
               profile.currentSyllableFocus == syllable,
               !wasGraduated,
               stat.isFocusGraduated {
                graduatedThisCall = syllable
                profile.everMasteredSyllables.insert(syllable)
                profile.currentSyllableFocus = nil
                profile.focusStartedDay = nil
                profile.focusPracticedDays = []
                profile.lastNewLetterDay = LocalDay.today()
                updateLevelReceipts(on: &profile)
            }
        case .word(let word):
            guard WordCurriculum.unit(word, language: profile.language) != nil else {
                return RecordedAnswer()
            }
            var stat = profile.wordStats[word] ?? WordStat()
            let wasGraduated = stat.isWordGraduated
            let oldKnown = stat.isKnown
            if asTarget {
                if shouldCountForLearning {
                    stat.recordTargetAttempt(correct: wasCorrect, responseTime: responseTime)
                } else {
                    stat.recordDistractorExposure()
                }
                if didReplayPrompt { stat.recordPromptReplay() }
                if !wasCorrect, let wrong = selectedWrongTarget {
                    if shouldCountForLearning {
                        stat.recordConfusion(with: wrong.storageKey)
                    } else if discountedForImpulse {
                        stat.recordImpulsiveSelection(of: wrong.storageKey)
                    } else {
                        stat.recordConfusion(with: wrong.storageKey)
                    }
                }
                profile.introducedWords.insert(word)
                if countsTowardDailyPractice && wasCorrect {
                    profile.recordDailyPracticeAttempt()
                }
            } else {
                stat.recordDistractorExposure()
            }
            if asTarget && oldKnown && !stat.isKnown {
                stat.wasKnownBefore = true
                stat.demotedAt = Date()
            }
            profile.wordStats[word] = stat

            if asTarget,
               profile.currentWordFocus == word,
               !wasGraduated,
               stat.isWordGraduated {
                graduatedThisCall = word
                profile.everMasteredWords.insert(word)
                profile.currentWordFocus = nil
                profile.focusStartedDay = nil
                profile.focusPracticedDays = []
                profile.lastNewLetterDay = LocalDay.today()
                updateLevelReceipts(on: &profile)
            }
        }

        let event = RoundEvent(
            date: Date(),
            target: target.storageKey,
            unitKind: target.kind,
            activityKind: activityKind ?? LearningActivityKind(rawValue: phaseAtAnswer.rawValue),
            options: optionsShown.map(\.storageKey),
            selected: selectedKey,
            wasCorrect: wasCorrect,
            responseTime: responseTime,
            phase: phaseAtAnswer,
            intent: intent,
            mistakeType: wasCorrect ? nil : mistakeType,
            didReplayPrompt: didReplayPrompt,
            replayCount: replayCount,
            wasDiscounted: asTarget && !shouldCountForLearning,
            heartsAfter: heartsAfter,
            liveDifficulty: liveDifficulty,
            isRescue: isRescue,
            rescueDifficulty: rescueDifficulty,
            attemptContext: context,
            cameoLetter: cameoLetter,
            includedFocusAsDistractor: includedFocusAsDistractor,
            planReason: planReason
        )
        profile.appendRoundEvent(event)
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
        return RecordedAnswer(focusGraduated: graduatedThisCall, leveledUp: leveledUpTo)
    }

    /// Records a *distractor* exposure (the letter appeared on screen but
    /// wasn't the target). Doesn't move the recent-results window — it just
    /// bumps `distractorExposures` and refreshes `firstSeenAt` / `lastSeenAt`.
    /// Never affects accuracy or mastery: when the child correctly taps A
    /// while O was on screen as a distractor, that round is *not* a wrong
    /// answer for O.
    func recordExposure(profileId: UUID, letter: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var profile = profiles[index]
        guard !LetterDifficulty.isVisualOnlyDistractor(letter) else { return }
        var stat = profile.letterStats[letter] ?? LetterStat()
        stat.recordDistractorExposure()
        profile.letterStats[letter] = stat
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
    }

    /// Records an intentional cameo exposure: a future letter shown as a
    /// distractor, without treating it as a formal introduction. The daily
    /// budget is spent here, at the same point the exposure itself is recorded,
    /// so exiting before answering does not consume a cameo.
    @discardableResult
    func recordCameoExposure(profileId: UUID, letter: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return false }
        var profile = profiles[index]
        guard !LetterDifficulty.isVisualOnlyDistractor(letter) else { return false }

        let today = LocalDay.today()
        let usedToday = profile.cameoExposures(on: today)
        guard usedToday < Profile.dailyCameoExposureLimit else { return false }

        var stat = profile.letterStats[letter] ?? LetterStat()
        stat.recordDistractorExposure()
        profile.letterStats[letter] = stat
        profile.cameoExposureDay = today
        profile.cameoExposuresToday = usedToday + 1
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
        return true
    }

    func recordExposure(profileId: UUID, target: FocusTarget) {
        switch target {
        case .letter(let letter):
            recordExposure(profileId: profileId, letter: letter)
        case .syllable(let syllable):
            guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
            var profile = profiles[index]
            guard SyllableCurriculum.isCurriculumSyllable(syllable, language: profile.language) else { return }
            var stat = profile.syllableStats[syllable] ?? SyllableStat()
            stat.recordDistractorExposure()
            profile.syllableStats[syllable] = stat
            profile.markModified()
            profiles[index] = profile
            saveProfilesImmediately()
        case .word(let word):
            guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
            var profile = profiles[index]
            guard WordCurriculum.unit(word, language: profile.language) != nil else { return }
            var stat = profile.wordStats[word] ?? WordStat()
            stat.recordDistractorExposure()
            profile.wordStats[word] = stat
            profile.markModified()
            profiles[index] = profile
            saveProfilesImmediately()
        }
    }

    // MARK: - Parent overrides

    /// Sets (or clears, when `override` is `nil`) a parent-issued manual
    /// override on a single letter for a given profile. The override is the
    /// honest way to express "I know my kid; treat this letter as known
    /// (or as fresh) regardless of what the attempt history says."
    ///
    /// Critically, this does NOT touch `recentResults`, `targetAttempts`,
    /// `targetCorrect`, `distractorExposures`, or any timestamp. The
    /// performance data stays intact and the parent dashboard can show
    /// both the override label AND the underlying numbers, so a conflict
    /// between the two is visible (and the parent can clear the override).
    ///
    /// Side effects:
    ///   * If the letter has no `LetterStat` yet (e.g., parent marks an
    ///     entirely unseen letter as known), a fresh empty stat is created
    ///     with the override attached. The empty counters truthfully say
    ///     "we have no data" — they're just a vehicle for the override.
    ///   * If the letter is currently the focus and the parent issues
    ///     `.markedKnown`, the focus is cleared so the next session picks a
    ///     new focus. (Symmetric to natural focus graduation.)
    ///
    /// Levels and `everMasteredLetters` are intentionally NOT updated by
    /// overrides — those represent real lifetime achievements. A parent
    /// can't level up their child by ticking 26 boxes.
    func setLetterOverride(profileId: UUID, letter: String, override: LetterOverride?) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var profile = profiles[index]
        var stat = profile.letterStats[letter] ?? LetterStat()
        stat.parentOverride = override
        profile.letterStats[letter] = stat
        if override != nil {
            profile.pausedFocusLetters.remove(letter)
            profile.pausedFocusLetterDays.removeValue(forKey: letter)
        }
        // If the parent declared the current focus letter known, clear the
        // focus so the next session picks a fresh one. We don't auto-clear
        // on `.reset` because the parent might be flagging a non-focus
        // letter for retraining and we shouldn't disturb the active drill.
        if case .markedKnown = override, profile.currentFocusLetter == letter {
            profile.currentFocusLetter = nil
            profile.focusStartedDay = nil
            profile.focusPracticedDays = []
            // Phase 0d: parent override that clears the focus also makes the
            // matching provenance stale — the picked letter is no longer the
            // focus we're explaining. Preserve provenance only when the
            // override targeted a non-focus letter.
            if profile.lastFocusSelection?.selectedKey == letter {
                profile.lastFocusSelection = nil
            }
        }
        profile.markModified()
        profiles[index] = profile
        saveProfilesImmediately()
    }

    /// Persists the letter-grid size frozen at the start of the current
    /// session so the *next* session's `AlphabetLevel.letterOptionsPerRound`
    /// has a `previousValue` for hysteresis. Idempotent; only writes when the
    /// value actually changes to avoid pointless `modifiedAt` churn.
    func recordSessionFrozenGrid(profileId: UUID, value: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        guard profiles[index].lastFrozenLetterOptionsPerRound != value else { return }
        profiles[index].lastFrozenLetterOptionsPerRound = value
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    func updateProfileNote(profileId: UUID, note: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].parentNote = normalizedNote(note)
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    func updateLetterNote(profileId: UUID, letter: String, note: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var stat = profiles[index].letterStats[letter] ?? LetterStat()
        stat.parentNote = normalizedNote(note)
        profiles[index].letterStats[letter] = stat
        profiles[index].markModified()
        saveProfilesImmediately()
    }

    private func normalizedNote(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(500))
    }

    // MARK: - Focus letter selection

    /// Picks the next focus letter for a profile that doesn't currently have
    /// one. Delegates to the shared prerequisite-aware helper so runtime focus
    /// assignment and `ProfileLearningSnapshot.nextFocusCandidate` agree.
    private func pickNextDailyIntroductionLetter(
        profile: Profile,
        lowercaseMode: LowercaseMode = .uppercaseOnly
    ) -> (key: String, reason: FocusSelectionReason.Reason)? {
        let effectiveLowercaseMode: LowercaseMode = profile.snapshot.instructionalBand.allowsAutomaticLowercaseTargets
            ? .afterUppercaseMastery
            : lowercaseMode
        let weeklyConfusables = Set(profile.language.letters.filter { candidate in
            profile.weeklyIntroducedLetters.contains { weekly in
                LetterDifficulty.areVisuallyConfusing(candidate, weekly)
                    && profile.letterStats[weekly]?.isStrongKnown != true
            }
        })
        // Introduced letters must remain eligible for remediation. Blocking
        // them made `nextFocusWithReason`'s stale-weakness branch unreachable
        // and could strand a failed spotlight forever.
        let blocked = profile.activePausedFocusLetters()
            .union(weeklyConfusables)
        return LetterDifficulty.nextFocusWithReason(
            language: profile.language,
            known: profile.knownLetters,
            learning: profile.learningLetters,
            mastered: profile.everMasteredLetters,
            introduced: profile.introducedLetters,
            letterStats: profile.letterStats,
            lowercaseMode: effectiveLowercaseMode,
            blocked: blocked
        )
    }

    // MARK: - Persistence

    private func saveProfilesImmediately() {
        if isDeferringSaves {
            hasDeferredSave = true
            return
        }
        performSave()
    }

    func flushPendingSave() {
        if isDeferringSaves {
            hasDeferredSave = true
            return
        }
        performSave()
    }

    func withDeferredSaves<T>(_ operation: () -> T) -> T {
        let wasDeferring = isDeferringSaves
        isDeferringSaves = true
        let result = operation()
        isDeferringSaves = wasDeferring
        if !wasDeferring, hasDeferredSave {
            hasDeferredSave = false
            performSave()
        }
        return result
    }

    private func performSave() {
        do {
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: storageKey)
            defaults.set(data, forKey: lastGoodStorageKey)
            persistenceErrorMessage = nil
            #if DEBUG_PERSISTENCE_LOGS
            print("💾 Profiles saved (v2)")
            #endif
            onProfilesSaved?(profiles)
        } catch {
            persistenceErrorMessage = "Písmenka couldn't save the latest profile changes. Please export a backup before closing the app."
            print("Failed to save profiles: \(error)")
        }
    }

    private func loadProfiles() {
        guard let data = defaults.data(forKey: storageKey) else {
            profiles = []
            return
        }
        do {
            profiles = try JSONDecoder().decode([Profile].self, from: data)
            defaults.set(data, forKey: lastGoodStorageKey)
            persistenceErrorMessage = nil
        } catch {
            defaults.set(data, forKey: recoveryStorageKey)
            if let backupData = defaults.data(forKey: lastGoodStorageKey),
               let recoveredProfiles = try? JSONDecoder().decode([Profile].self, from: backupData) {
                profiles = recoveredProfiles
                defaults.set(backupData, forKey: storageKey)
                persistenceErrorMessage = "Písmenka restored profiles from the last readable backup. The unreadable data was preserved for recovery."
                print("Restored profiles from last known-good backup after load failure: \(error)")
                return
            }
            persistenceErrorMessage = "Písmenka couldn't read saved profiles. The unreadable data was preserved for recovery."
            print("Failed to load profiles: \(error)")
            profiles = []
        }
    }

    // MARK: - Avatar Availability

    func availableAvatars() -> [AvatarType] {
        let usedAvatars = Set(profiles.map { $0.avatarId })
        return AvatarType.allCases.filter { !usedAvatars.contains($0) }
    }
}

// MARK: - RecordedAnswer

/// Side-effects of `recordAnswer` that the caller might need to celebrate.
struct RecordedAnswer: Equatable {
    var focusGraduated: String? = nil
    var leveledUp: AlphabetLevel? = nil
}
