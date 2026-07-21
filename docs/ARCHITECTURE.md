# Písmenka 🔤

A profile-based **adaptive** pre-reading and early-numeracy game for toddlers (ages 3-5). The app figures out which letters — or, in Numbers mode, which numbers (0–100) — your child knows, gives them a visible practice goal, introduces a fresh spotlight unit without destroying longer-term remediation state, explicitly shows and drills that same introduced unit, and runs a retention progress check after every six completed 25-answer sessions in that layer. The Expert alphabet crown and the Fluent number band remain the long-term trophies.

iOS 17+, SwiftUI.

> **Current release scope.** The shipped app covers **letters plus the numbers peer layer**; the reading layers stay dormant. The Czech syllable (`slabiky`) and word-reading models, gates, focus state, distractor pools, calibration phases, and `ReadingStage` ladder all still live in the codebase as future-version scaffolding, but they are **silent in the current build** — never scheduled for sessions, not shown in the UI, never eligible for syllable/word rounds in the planner (`isSyllableLayerEligible` is unused), and not validated as required assets. A `syllablesUnlockedAt` timestamp may still be written on Czech alphabet completion during play, but it is cleared on the next `commitSessionStartIfNeeded` and does not enable reading sessions in this build. Session planning is layer-aware: `ProfileManager.previewSessionPlan(profileId:lowercaseMode:layer:)` / `commitSessionStartIfNeeded(...)` route through `buildSessionPlan(..., layer:, commit:)`, which forwards `layer == .numbers` to `buildNumberSessionPlan` (plans with `primaryLayer = .numbers` / `activityKind = .numberRecognition`). The **letters** branch uses a local profile copy with `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` nilled out (in memory on preview, persisted on the first-answer commit) and leaves `primaryLayer` at `.letters` — only the dormant **reading** layers are forced off; numbers are a first-class scheduled layer. The hard-required audio surface is English/Czech letter prompts, the optional personalized Czech letter pack, and game SFX (~115 files: 67 letter prompts, 41 optional Čermák Czech prompts, 7 SFX/Winner clips); the Numbers voice pack (202 files under `Sounds/Numbers/`) is bundled on the **soft** validation path with a runtime TTS fallback, bringing the bundled total to ≈ 317 audio files (see [Required assets → Audio](#audio) for the current pack state). `AudioService.requiredCurriculumVoiceAssets(for:)` returns `[]`, so syllable/blend/word clips are neither required nor bundled; `AudioService` still knows the future reading filenames/paths (`cz_syl_*`, `cz_blend_*`, `cz_word_*`, optional `Sounds/Blends/`), but those recordings are absent from the app bundle today — older copies may still exist in repo backup folders such as `audio_backups/` outside the Xcode target. Throughout this document, any subsection describing syllable/word behavior — CV bridge, `syllableCalibration` / `syllableRecognition` / `syllableBlending` / `wordReading` / `wordBuilding` phases, `WordCurriculum` audio gates, reading-stage badges, the `readingPracticePaused` toggle, and so on — describes **dormant scaffolding kept healthy for a future release**, not behavior the current build exposes. The README is the short product-scope statement; this document carries the exact repo asset inventory.
>
> **Numbers peer layer (shipped).** The **numbers** learning track (number recognition, 0–100) has landed as a peer layer of letters, ahead of the Czech reading layer being re-activated — the order stays intentional: numbers first, reading second. Numbers ship with their own `UnitKind.number` / `LearningLayer.numbers` cases, their own curriculum and confusion policies (`NumberDifficulty`), their own instructional band (`NumberInstructionalBand`, never derived from `AlphabetLevel`), their own per-unit stats (`NumberStat`, a `typealias` of `LetterStat`), their own calibration flag (`hasCompletedNumberCalibration`), their own daily/weekly twin counters on `Profile`, their own parent dashboard (`ParentNumberDashboardView`), and their own reset semantics inside `resetAllProgress` / the numbers-specific resets. The home screen switches between Letters and Numbers via the **local-only** `AppSettings.activeLearningLayer` (never synced to cloud backup). The day streak is shared across both layers; cycle/session counters are per-layer twins. Number voice clips are validated **softly** (`AudioService.missingNumberAssetNames(...)`) with a TTS spoken-word fallback, unlike the hard letter-asset gate. Re-activating the silent reading scaffolding remains a separate later step.

### Numbers peer — summary

Numbers are documented inline throughout this document as a shipped peer of letters; the load-bearing decisions in brief:

- **`SessionPlan` field reuse.** Numbers reuse `focusLetter`, `dailySpotlightLetter`, `introducedNewFocusLetter`, and `SessionMode.extraPractice(letter:)` with bare digit keys (`"26"`); disambiguation is `primaryLayer == .numbers` plus `focusTarget = .number(...)` / `activityKind = .numberRecognition`. No parallel `focusNumber` twins exist on the plan. See [Daily session](#3-daily-session).
- **`FocusTarget` bare-digit trap.** `FocusTarget(storageKey:)` treats any bare single character as a **letter** (`"5"` → `.letter("5")`); number paths must always use the `number:` prefix. See [Numbers peer layer](#numbers-peer-layer).
- **Twin state, shared streak.** Every cycle/goal/focus/assessment field has a number twin on `Profile`; only the day streak (`dailyStreakCount` / `bestDailyStreak` / `lastSessionDay`) is shared. See [Data storage](#data-storage) and [Granular resets](#granular-resets).
- **Parent surface.** Numbers mode swaps in [`ParentNumberDashboardView`](#numbers-dashboard) and the profile card's Confident n/m counts against the introduced `numberKnowledgePool`, never all 101.

---

## Table of contents

- [What the app does](#what-the-app-does)
- [User flow](#user-flow)
  - [First launch](#1-first-launch--onboarding-then-profile-creation)
  - [Calibration](#2-calibration-one-time-per-profile)
  - [Daily session](#3-daily-session)
  - [Daily goal, Winner button, and progress strip](#daily-goal-winner-button-and-progress-strip)
  - [Six-session retention progress check](#six-session-retention-progress-check)
  - [Session end & "Play again"](#4-session-end--play-again)
  - [Parent dashboard](#5-parent-dashboard)
  - [Numbers dashboard](#numbers-dashboard)
- [The adaptive learning model](#the-adaptive-learning-model)
  - [Per-letter mastery (`LetterStat`)](#per-letter-mastery-letterstat)
  - [Alphabet levels & reading stages](#alphabet-levels--reading-stages)
  - [Answer-grid sizing: 4 / 6 / 8 options](#answer-grid-sizing-4--6--8-options)
  - [Daily spotlight, durable focus & scaffolding ladder](#daily-spotlight-durable-focus--scaffolding-ladder)
  - [Numbers peer layer](#numbers-peer-layer)
  - [Czech reading progression](#czech-reading-progression)
  - [Syllable contrast policy](#syllable-contrast-policy)
  - [Distractor selection (`DistractorTier`)](#distractor-selection-distractortier)
  - [Cameo letters](#cameo-letters)
  - [Visually confusing pairs (`ConfusionPolicy`)](#visually-confusing-pairs-confusionpolicy)
  - [Round generation & answer-position fairness](#round-generation--answer-position-fairness)
  - [Hearts (5)](#hearts-5)
  - [Attempt contexts & assisted discount](#attempt-contexts--assisted-discount)
  - [Day streak (clock-tolerant)](#day-streak-clock-tolerant)
  - ["Today's sticker card" stamps](#todays-sticker-card-stamps)
  - [Multi-session same-day contract](#multi-session-same-day-contract)
  - [Adaptive struggle response](#adaptive-struggle-response)
  - [Adaptive signals & feedback loops](#adaptive-signals--feedback-loops)
- [Parent controls](#parent-controls)
  - [Case practice](#case-practice)
  - [Parent gate](#parent-gate)
  - [Personalized letters](#personalized-letters)
  - [Per-letter overrides](#per-letter-overrides)
  - [Granular resets](#granular-resets)
- [Architecture & file map](#architecture--file-map)
- [Data storage](#data-storage)
- [Required assets](#required-assets)
- [Building](#building)
  - [Development verification cadence](#development-verification-cadence)
- [Technical notes](#technical-notes)

---

## What the app does

| Trait | Detail |
|---|---|
| Audience | Pre-readers, ages 3–5 |
| First launch | Language choice (Czech default + spoken previews), then optional Apple/Google backup, then profile select |
| Profiles | Up to 4, each fully independent |
| Languages | English 🇺🇸 and Czech 🇨🇿 (per profile; app-level default from onboarding) |
| Network | Not needed for gameplay or learning; optional Apple/Google Firebase backup for parents (requires `GoogleService-Info.plist`; see Settings and first-launch onboarding) |
| Learning layers | **Letters** and **Numbers (0–100)**, switched from the home screen (`AppSettings.activeLearningLayer`, local-only); reading layers dormant |
| Core loop | Hear a letter **or** a number → pick the matching symbol from a playful options grid (slabika/word loops remain dormant scaffolding) |
| Difficulty | Self-adjusting per child and per unit, with a per-layer retention progress check after six completed 25-answer sessions in that layer |
| Session length | Variable length per sitting (no fixed timer in code), paced by 5 hearts; progress persists toward and beyond a visible goal — **25** correct-answer rounds on introduction sessions (wrong taps do not advance the bar), **8–40 adaptive** rounds on progress-check sessions (hard cap `adaptiveSessionCeiling`; may end sooner once cohort evidence resolves; every answered round counts during the check) |
| Parent surface | Hold a profile card → iOS context menu → **View results** (parent gate → dashboard) or **Edit profile** (parent gate → edit sheet) |

---

## User flow

```
App launch
   │
   ├──[first launch]──▶ FirstLaunchOnboardingView
   │                       │  (language → optional Apple/Google backup)
   │                       ▼
   │                    ProfileSelectView
   │
   └──[returning / migrated]──▶ ProfileSelectView
                                   │  (pinned Letters 🔠 / Numbers 🔢 switch →
                                   │   AppSettings.activeLearningLayer, local-only)
   ├──[gear + parent gate]──────────────────▶ SettingsView
   │
   ├──[hold profile → iOS context menu]
   │      │
   │      ├──[View results + parent gate]──▶ ParentDashboardView (letters mode)
   │      │                                  ParentNumberDashboardView (numbers mode)
   │      │                                   │
   │      │                                   └──[practice letter / number]──▶ GameView
   │      │
   │      └──[Edit profile + parent gate]──▶ EditProfileView
   │
   └──[tap profile]──▶ (layer calibration flag false) ──▶ CalibrationView
                       │   letters: hasCompletedCalibration
                       │   numbers: hasCompletedNumberCalibration
                       │                 (intro → ~10–22 rounds → finale)
                       │                      │
                       │                      ├──[home]──▶ ProfileSelectView
                       │                      └──[finale CTA]──▶ GameView
                       (calibrated)   ──▶                    GameView
                                                                │
                                                                ▼
                                                         SessionEndView
                                                          │      │
                                                  replay icon   home icon
                                                          │      │
                                                  GameView ◀┘    └──▶ ProfileSelectView
```

`ProfileSelectView` pins a two-segment Letters/Numbers switch above the `+` button. It writes straight to `AppSettings.activeLearningLayer` (persisted in `UserDefaults`, deliberately **excluded** from `AppSettingsSnapshot` so cloud backup never overwrites a device's home mode; only `.letters` / `.numbers` are accepted). Everything downstream of the profile tap is layer-aware: `ContentView` branches calibration on `hasCompletedCalibration` vs `hasCompletedNumberCalibration`, builds the session plan via `previewSessionPlan(..., layer: settings.activeLearningLayer)`, restores per-layer checkpoints, and **View results** opens `ParentDashboardView` or `ParentNumberDashboardView` depending on the active layer. The profile card's Confident n/m headline is also layer-aware (numbers mode uses `parentNumberKnowledgeSummary(pool: numberKnowledgePool)`).

The profile card uses iOS's standard `.contextMenu` so the gesture is discoverable (long-press triggers the system menu; choosing an action plays a light haptic). A small hint line — `Tap a card to play · Hold for parent options.` — appears below the profile grid once at least one profile exists, so parents can find it without a tutorial. Both context menu actions still pass through `ParentGateView` before the dashboard or edit sheet opens.

Root navigation lives in [`PismenkaApp.swift`](Pismenka/PismenkaApp.swift). Before the four-screen state machine (`profileSelect → calibration → game → sessionEnd`), `ContentView` gates on `AppSettings.hasCompletedFirstLaunchOnboarding`: when false, it shows [`FirstLaunchOnboardingView`](Pismenka/Views/Profile/CreateProfileView.swift) (defined in the same file as `CreateProfileView`). Installs that already have a profile skip the onboarding via `migrateExistingInstallationIfNeeded`, which calls `completeFirstLaunchOnboarding(language:)` with the first existing profile's language so updates keep opening on profile select.

### 1. First launch — onboarding, then profile creation

**App-level onboarding (`FirstLaunchOnboardingView`).** On a truly new install the parent sees a two-step welcome before any profile exists:

1. **Language** — Czech is selected by default; English is the other choice. Each option has a spoken letter preview ("Hear A"). Continue advances to backup.
2. **Optional backup** — Sign in with Apple or Google when Firebase is configured, or skip. Copy states that play works without an account and that progress can be lost without backup. Completing (or skipping) calls `AppSettings.completeFirstLaunchOnboarding(language:)`, which stores `defaultGameLanguage` and sets `hasCompletedFirstLaunchOnboarding = true`, then the root navigates to `ProfileSelectView`.

**Profile creation.** `ProfileSelectView` shows the existing profile cards, up to the four-profile limit, plus a bottom `+` button. When no profiles exist yet, a first-run card explains how to add a child and points parents to the gear icon for settings, backup, and recovery. Tapping `+` triggers the configured parent gate (`ParentGateView`) before `CreateProfileView` opens (seeded with `settings.defaultGameLanguage` from onboarding). The default gate is a swipe-up drag; settings can switch it to a hold-two-buttons accessibility mode.

In `CreateProfileView` the parent picks:

- **Avatar** — emoji picker drives the profile's color theme. Avatars already used by another profile are hidden (`ProfileManager.availableAvatars()`).
- **Name** — optional; empty name falls back to the avatar's display name. When set, limited to 8 characters; ASCII keyboard, autocorrect off (so "Lulu" doesn't become "Lulu's"). Create is enabled once an avatar is chosen (name not required).
- **Language** — English or Czech (pre-selected from the app-level default). Sets the alphabet and bundled audio prefix for that profile; each child can still differ from the onboarding choice.

The level **is not** chosen — the app discovers it during calibration. There's no "novice/beginner/expert" question for the parent.

Tapping **Create** saves the profile and dismisses the sheet; the child is **not** auto-launched into calibration until a parent taps that profile card on `ProfileSelectView`.

### 2. Calibration (first run per profile; parent resets can require it again)

Each layer has its own one-time calibration: letters gate on `hasCompletedCalibration`, numbers on `hasCompletedNumberCalibration`, and both run through the same [`CalibrationView`](Pismenka/Views/Game/CalibrationView.swift) with a `layer` parameter. The letters flow plays a friendly ~10-22 round calibration drawn from a generalized early-recognition pool. The base 10 letters come from `LetterDifficulty.earlyRecognitionLetters` — `A B C O X M S T D E` — which mirror published preschool letter-recognition rankings (alphabet-song head `A`-`E` plus visually distinctive `O`/`X`/`M`/`S`/`T`). The first letter of the child's typed name is added to the pool when it isn't already in the base 10 (Czech diacritics like `Š` are mapped to their base, `S`, so the diacritic-prerequisite contract isn't violated). When front-loading won't create consecutive duplicates at the start of the schedule (`draft[1]` must differ from the mapped name letter), that name letter is swapped to round 1 so calibration often opens on a personally meaningful prompt.

- Each pool letter is scheduled to appear exactly twice; with a name-letter addition the schedule grows from 20 to 22 rounds. A soft "no two consecutive same" pass varies the cadence.
- Each round records a real `targetAttempts` / `targetCorrect` event; nothing is synthetically pre-marked.
- Distractor selection during calibration avoids visually confusing pairs by filtering `LetterDifficulty.visuallyConfusingPairs` in `CalibrationView.buildOptions` (same intent as `ConfusionPolicy.avoid`, but calibration does not call the enum).
- Calibration can stop early via `CalibrationView.shouldStopCalibrationEarly`: after ≥10 rounds when accuracy is ≥0.8 or ≤0.3; after any stretch of ≥3 wrong in the last 5; or after ≥12 rounds when accuracy is ≥0.75 or ≤0.4. Mixed evidence continues to the full 20-22.
- When the child finishes the finale screen and taps through, `CalibrationView` calls `ProfileManager.markCalibrationComplete` (sets `hasCompletedCalibration = true`); `ContentView`'s completion handler then routes into `GameView`. Leaving via the home control before that does not set the flag (it clears the calibration checkpoint but keeps any `LetterStat` data already written by answered rounds).

**Calibration screens.** `CalibrationView` shows a welcome intro, then letter rounds with checkpoint persistence (including cold-launch restore via `ContentView.restoreCheckpointIfPossible`), then a short finale. Only the finale button marks calibration complete and hands off to the daily game.

A child who nails most calibration letters will exit with several `LetterStat`s at **2/2** (`targetCorrect`/`targetAttempts`) and many of those letters may already count as data-driven known via `LetterStat.isKnown` / `Profile.knownLetters`. A child who misses often exits with mostly weak stats (often **0/2** or **1/2**); the next session skips warm-up when fewer than three letters count as known (`warmupLength = 0`) and assigns longer warm-up as `knownLetters` grows (2 / 3 / 5 rounds at ≥3 / ≥4 / ≥6 known). `nextFocusWithReason` can re-teach 0/2 letters through the `staleWeakness` branch (threshold `targetAttempts >= 2` so calibration evidence counts).

**Numbers calibration twin.** The same `CalibrationView` runs the numbers layer when `AppSettings.activeLearningLayer == .numbers` and `hasCompletedNumberCalibration` is false (a `layer` parameter switches the flow; there is no separate view):

- The pool is `NumberDifficulty.calibrationPool()` — the digits **1…10** — with each number scheduled twice, the same "no two consecutive same" pass, and the same early-stop rules. There is **no name-letter seed**: the numbers flow passes `nil` where letters use the child's name initial.
- An optional age seed exists but is **unwired**: `NumberDifficulty.calibrationPool(ageNumber:)` can ensure the child's age digit (1…10) appears in the schedule, mirroring the letter name-seed, but `Profile` has no age field yet, so `CalibrationView` calls `calibrationPool()` with no age.
- Prompts play through `AudioService.playNumber(_:language:)` (bundled clip with spoken-word TTS fallback).
- Distractor selection filters hard confusables via `NumberDifficulty.isHardConfusable` (digit transposes, 6/9-style lookalikes, containment pairs, shared-tens) — the numbers analog of the letters flow filtering `visuallyConfusingPairs`.
- Answers are recorded as typed rounds (`target: .number(...)`, `activityKind: .numberRecognition`), so evidence lands in `numberStats` and round events carry `unitKind: .number`.
- The finale calls `ProfileManager.markNumberCalibrationComplete` (sets `hasCompletedNumberCalibration = true`); leaving early keeps any recorded `NumberStat` data without setting the flag, exactly like the letters contract.

### 3. Daily session

`ProfileManager.previewSessionPlan(profileId:lowercaseMode:layer:)` builds a non-mutating session preview when `GameView` opens, using the home screen's `AppSettings.activeLearningLayer`. `AdaptiveGameState.commitSessionStartIfNeeded(...)` commits that plan on the first real answer, so merely opening the game does not count as practice. `GameView` calls `commitSessionStartIfNeeded` on every tap; the engine no-ops after the first answer unless `plan.mode == .adaptiveDaily` and `roundsThisSession == 0`. Extra parent practice (`SessionMode.extraPractice`) never commits session-start profile mutations. The committed session:

1. Updates the day streak based on the signed delta between today and `lastSessionDay` (in `LocalDay`, not `Date` — see [Day streak](#day-streak-clock-tolerant)). The streak engine is **shared** across letters and numbers: both planner branches read and write the same `dailyStreakCount` / `lastSessionDay`.
2. Sets `primaryLayer` per the requested layer. A `layer: .numbers` plan routes to `buildNumberSessionPlan` and carries `primaryLayer = .numbers` / `activityKind = .numberRecognition`; the letters branch leaves `primaryLayer` at `.letters` and deliberately nils out `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` on every commit so only the dormant reading-layer scaffolding is forced off.
3. Resolves the practice contract **per layer**: ordinary introduction session (`25` correct target rounds) or, after six such completed sessions in that layer's cycle, a retention progress check with an adaptive frozen target (letters: `resolveDailyPractice` over `completedLetterSessionsInCycle` / `activeWeeklyAssessment`; numbers: `resolveNumberDailyPractice` over `completedNumberSessionsInCycle` / `activeWeeklyNumberAssessment`).
4. Decides whether to introduce a fresh **daily spotlight** unit today. The spotlight is intentionally separate from the durable remediation/focus state, so a new day does not automatically wipe an in-flight `currentFocusLetter` / `currentFocusNumber`.
5. Returns a `SessionPlan` with warm-up length, focus fields, daily-goal contract, review-cohort keys, optional `dailySpotlightLetter`, and day-streak fields (`dayStreakCount`, `dayStreakIncreased`) used for the "Day N!" banner. Numbers plans **reuse the letter-named plan fields with bare digit keys** (`focusLetter = "26"`, `dailySpotlightLetter`, `weeklyReviewLetters`, `SessionMode.extraPractice(letter:)`); `primaryLayer == .numbers` plus the typed `focusTarget = .number(...)` disambiguate — there are no parallel `focusNumber` plan fields.

**Numbers planning specifics** (`buildNumberSessionPlan` / `resolveNumberDailyPractice`): the spotlight picker is `NumberDifficulty.nextFocusCandidate(introduced:known:blocked:)`, which walks the pedagogical `introductionOrder` (1…10, then 0, then teens, then decade anchor + fill per decade, then 100), gated by `isReadyToIntroduce` readiness rules and by requiring a 4-option grid to be buildable under `.avoid`. Introduction updates the number twin fields (`introducedNumbers`, `lastNewNumberDay`, `weeklyIntroducedNumbers`, `currentFocusNumber` / `numberFocusStartedDay` / `numberFocusPracticedDays`, `lastNumberFocusSelection`). Stuck-focus pause has a numbers twin too (`shouldPauseStuckNumberFocus`, `pausedFocusNumbers` / `pausedFocusNumberDays`, 8 practiced days at &lt; 50% recent accuracy). Warm-up length uses the same known-count ladder as letters over `knownNumbers`, additionally capped by how many known numbers are actually review-due (`min(baseWarmup, max(1, dueWarmupCount))`). On review-test days the plan carries no focus number.

**Same-day re-entry.** Toddlers often tap "Play again" multiple times. `recordAnswer` keeps accruing attempts and can graduate focus mid-day, but `commitSessionStartIfNeeded` will not introduce a second daily spotlight (`lastNewLetterDay`), will not bump the day streak again (`delta == 0`), and treats `focusPracticedDays` idempotently. Hearts, stamps, and `roundsThisSession` are **session-local** — each `GameView` gets a fresh `AdaptiveGameState`. See the multi-session table in `ProfileManager.buildSessionPlan` comments.

A session is structured into phases by [`AdaptiveGameState`](Pismenka/Models/GameState.swift):

| Phase | Trigger | Round shape |
|---|---|---|
| `warmup` | Letter and number sessions, when the engine starts in warm-up | Target chosen from known units ordered by review priority; distractors are other known units. Warm-up deliberately excludes the active focus/spotlight, so a just-introduced unit is not hidden among warm-up distractors before drill begins. Warm-up uses the `avoid` confusion policy in both layers. Reading-layer routing is dormant in this release, so the dormant syllable/word branches never plan a warm-up. |
| `drill` | Letter sessions after warm-up, while either a durable focus or daily spotlight is active | The active drill focus is the priority target (by teaching-mode probability, with progressive scaffolding, never chained, capped at 10 asks per local day); remaining rounds go to the needs-work / confusion-partner / strong mix described in [Introduction-day round mix](#daily-goal-winner-button-and-progress-strip). The focus/spotlight also slips in as a "clearly wrong" distractor for extra exposure. Durable remediation focus wins when the child is stuck; otherwise the daily spotlight becomes the active drill focus without clearing `currentFocusLetter`. Product goal for a completed 25-round introduction session: the introduced spotlight appears at least three times and is asked as a target at least once (`testIntroducedSpotlightAppearsDuringDailyLetterSession`); drill forcing (`firstFocusAppearanceDeadline`, `activeDrillFocus`) is designed toward that exposure. |
| `plainReview` | Letter sessions when no drill focus is active, including no-focus review and retention progress checks | Normal review pulls from known letters, weak/stale letters, and confidence-ordered pools. Progress checks first prioritize the frozen assessment cohort until every cohort letter has enough independent evidence, then fall back to weak/stale/global review. The frozen `instructionalBand` gates similar-shape, mixed-case, and visual-only distractors while cameo eligibility follows its own conservative rules. Progress checks use safer confusable rules than later Expert maintenance and do not inject contrast rounds. |
| `maintenance` | Alphabet Expert, no current letter focus | Mixed letter review ordered by `reviewPriority`, with deliberate confusable-pair, mixed-case practice, and eligible cameo letters. Reading stage does not decide letter maintenance by itself. |
| `contrast` | ~1 in 5 eligible review/maintenance round builds (`Int.random(in: 1...5) == 1` per build, not a global quota) | Target is a letter the child often confuses, with the confused letter deliberately shown as a distractor. |
| `rescue` | After a wrong answer on a letter or number target | Two-tier queue: wrong non-rescue target → easy retry after **one** intervening round (`dueAfterRounds: 1`); failed easy rescue → mid retry in **2–3** rounds (`midRescueDelayRange`). Rescue is a round override, not a lasting `phase` value. Number rescues force a 4-option grid, `.avoid` distractors, and (easy tier) a known-numbers pool. |
| `syllableCalibration` *(dormant)* | First Czech reading session after reading unlock. In the current code, that dormant unlock path is tied to full alphabet completion, not an early CV bridge. | 12 short-CV recognition rounds with same-vowel consonant contrasts; no long-vowel pairs yet. **Not reachable in the current release** — reading unlock fields are forced to nil at session start. |
| `syllableRecognition` *(dormant)* | Czech profile while the syllable layer is active | Target is the active syllable focus when one exists, otherwise a known/playable CV slabika such as `MA`; options are structurally selected eligible slabiky. |
| `syllableBlending` / `syllableSegmenting` *(dormant)* | Scheduled reading-production activities | Blending adds `M + A -> MA` style segment metadata; segmenting uses word/syllable segment metadata when routed. |
| `wordReading` *(dormant)* | Czech word layer after enough known slabiky | Target is a seeded word such as `MÁMA`; options are eligible words with matching syllable shape where possible. |
| `wordBuilding` *(dormant)* | Scheduled word-production activity | Uses two-syllable tiles and `expectedSequence` / `selectedSequence` in `LearningRound` when invoked. |

**Numbers sessions share this engine skeleton.** When `plan.primaryLayer == .numbers`, the same `warmup` / `drill` / `plainReview` / `rescue` phases run, but rounds are built by `AdaptiveGameState.buildNumberRound(...)`: targets come from the introduced number pool (warm-up by `numbersByReviewPriority`, drill by the active spotlight/focus with the same focus-chance, hello-focus deadline, and per-day ask-cap machinery, review-test days by `chooseWeeklyNumberAssessmentTarget`), distractors come from `NumberDifficulty.pickDistractors` under the frozen `NumberInstructionalBand`'s confusion policy (relaxed tier by tier before ever shrinking the grid), and the typed round carries `target: .number(...)` / `activityKind: .numberRecognition` so `recordAnswer` writes `numberStats` and `RoundEvent.unitKind == .number`. The letter-only `maintenance` and `contrast` phases and cameo letters have no numbers equivalents today.

Letter sessions use a session-frozen 4/6/8 answer grid from `Profile.letterOptionsPerRound`, based on known/strong-known pool safety **plus** demonstrated independent performance at the current grid size (`Profile.gridPerformanceStats`), not on the alphabet-level badge. Per-round, `AdaptiveGameState.resolvedLetterOptionCount` can still cap a weak, new, slipped, or active-drill-focus target at 4 (or 6 for strong-but-not-fluent) even after a wider session grid is earned. Numbers sessions freeze their own grid from `Profile.numberOptionsPerRound` (backed by `NumberInstructionalBand.numberOptionsPerRound` with `numberGridPerformanceStats` promotion evidence and `lastFrozenNumberOptionsPerRound` hysteresis) and clamp per-round via the twin `resolvedNumberOptionCount`. See [Answer-grid sizing: 4 / 6 / 8 options](#answer-grid-sizing-4--6--8-options) for the exact contract. `instructionalBand` / `numberBand` still gate the harder distractor behavior, but they do not directly decide the answer count. `LiveDifficulty` can downshift the frozen grid during struggle in both layers. Early slabika and word sessions are designed to stay at 4 choices even when the child is already Expert in letters, but they are not reachable in the current release.

#### Daily goal, Winner button, and progress strip

The daily goal is now a first-class `SessionPlan` contract, not an accidental by-product of stamps or hearts:

| Day type | `DailyPracticeKind` | Visible target | Product meaning |
|---|---|---:|---|
| Ordinary introduction day | `.introduction` | `25` | Enough completed target rounds to count as the child's daily letter practice, with any newly introduced spotlight receiving real drill exposure during the run. |
| Retention progress check | `.reviewTest` | Adaptive, floor `8`, hard cap `40` | Runs after six completed 25-answer letter sessions, prioritized by new/weak evidence and capped so the check stays child-sized. Completion cannot leave a planned audit letter at `0/0 independent`. |

`AdaptiveGameState.dailyGoalTotalCount` is:

```
max(0, plan.dailyGoalStartCount + progress)
```

where `progress` is `roundsCorrect` when `dailyPracticeKind == .introduction`, and `roundsThisSession` when `dailyPracticeKind == .reviewTest`.

On ordinary introduction sessions, only **correct** answers advance the visible bar — a wrong tap earns no progress toward the Winner button. `roundsThisSession` still counts every answered round for warm-up length, focus-appearance deadlines, and round indexing. During a **retention progress check** (`.reviewTest`), the bar uses `roundsThisSession` instead: every answered round counts whether right or wrong, because completion is about *coverage*, not a correct-answer quota.

`dailyGoalStartCount` comes from `Profile.dailyPracticeCount(on:)` in the letters layer and `Profile.numberDailyPracticeCount(on:)` in the numbers layer, so a child can get 10 correct in the morning, run out of hearts, come back later, and see `10 / 25` already filled — per layer. Hearts end the **current sitting** only; they do not reset or fail the daily goal.

**Introduction-day round mix.** Within the 25-answer day, `chooseIntroductionDrillTarget` fills non-warm-up rounds in this priority order: (1) the spotlight/focus by teaching-mode probability, never chained back-to-back when alternatives exist; (2) an active confusion partner of the previous target (~35% when a pair like B/D has live mistake evidence), so discriminations get adjacent-round practice; (3) a **needs-work** letter — introduced letters that are weak on recent accuracy, under-practiced (< 5 target attempts), **review-due per the memory scheduler** (`LetterMemoryState`), or still short of strong evidence (never cleared `isStrongKnown` / graduation / lifetime mastery — the parent letter map's "Maybe" tiles), weighted-sampled by a blend of weakness, low attempts, and forgetting risk so the day interleaves the pool instead of drilling the top two; (4) an occasional **strong** letter (~15% base, ~22% when live session accuracy is under 70%, ~30% under 55%), ordered by scheduler `reviewPriority` so the easy win lands on the strong letter closest to slipping. Every letter is hard-capped at **10 target asks per local day** (`hardMaxTargetsPerLetterPerSession`, seeded across sittings from `Profile.dailyTargetAskCounts`), with a sparse-profile escape when nothing else is eligible.

After the first target is reached, the counter keeps going instead of stopping at `25 / 25` or the frozen review/test target. The visible count switches to extra rounds: `+1`, `+5`, `+25`, and so on. Tapping the Winner button records the highest completed milestone for that local day in `dailyPracticeWinnerClaimedMilestone` (numbers: `numberDailyPracticeWinnerClaimedMilestone`). On the next same-day session, Winner stays hidden until the child completes another full goal chunk: after claiming `25`, the next Winner appears at `+25` (`50` total); after claiming an adaptive review/test goal, the next Winner appears after one more full goal chunk.

The claim itself is layer-scoped: `GameView` calls `ProfileManager.claimDailyPracticeWinner(profileId:milestone:layer: plan.primaryLayer)`. A `.letters` claim moves only `dailyPracticeWinnerClaimed*` / `completedLetterSessionsInCycle` (and can finalize `activeWeeklyAssessment`); a `.numbers` claim moves only `numberDailyPracticeWinnerClaimed*` / `completedNumberSessionsInCycle` (and can finalize `activeWeeklyNumberAssessment`). The two cycles never cross-contaminate.

When the visible goal is reached, adaptive play swaps the progress strip for the `🏆 WINNER 🏆` bar (`Tap for your prize`) until the child claims the milestone; after a claim, the strip returns while extra-round chunks accumulate toward the next Winner. Claiming each ordinary 25-answer chunk increments the persisted six-session cycle. The Winner tap is intentionally a larger celebration than ordinary correct-answer feedback: full-screen celebration confetti (`.celebration`), a big `WOW!`, then applause via `AudioService.playWinnerCelebration` before handing off to `SessionEndView`. During a progress check, claiming Winner at the frozen goal also finalizes the assessment if needed.

The `GameView` card header and bottom progress strip show the contract visually and numerically:

- Card header eyebrow/title: `TODAY / Daily letters` on introduction sessions, `REVIEW / Progress check` during retention assessment (parent-directed practice uses `Practice / Practicing <unit>` instead). The title string is currently `Daily letters` in numbers sessions too — a known cosmetic leftover, not a routing signal.
- Progress strip count: `5 / 25`, `10 / 25`, `25 / 25`, then `+1`, `+5`, `+25`, using monospaced digits via `dailyGoalDisplayText`.
- Progress strip right label: `Winner soon` until the daily goal is reached, then `Goal reached` while extra-round chunks continue.
- Line: a linear `GradientProgressBar`; before the first Winner it fills toward the first goal, and after a Winner claim it refills toward the next full extra chunk.
- Before each claimable milestone, the progress strip is visible; when a milestone is ready, it is replaced by the Winner bar until tapped.

Only **correct** adaptive-daily **target** rounds advance `Profile.dailyPracticeAttempts` on ordinary days; number rounds advance the twin `numberDailyPracticeAttempts` under identical rules, with `activeWeeklyNumberAssessment` as the numbers review-day detector. This is explicit at the persistence boundary via `countsTowardDailyPractice` combined with the round's `wasCorrect` (and the weekly-test exception below):

- Counts: correct ordinary target rounds, correct rescue/assisted target rounds, and correct revealed target rounds, when they came from the adaptive daily game flow.
- Progress-check exception: on review/test days (detected by a present `activeWeeklyAssessment`, committed before the first answer), **every** answered target round counts — wrong answers included — because the check is a coverage audit with an adaptive 8–40 participation target (and may end early once every planned letter has a non-pending outcome), not a correct-answer quota.
- Does not count: on ordinary days, any wrong answer (including deliberate wrong taps and impulsive misses); and always: distractor exposure, cameo exposure, visual-only distractors, parent-directed extra practice, opening a preview, or any non-adaptive flow that does not pass the daily counter flag.
- Mastery remains stricter than daily participation. Assisted rounds may advance the visible daily bar while still being discounted from `recentResults` / `targetAttempts` where appropriate.

This deliberately separates three ideas that used to be too easy to conflate: **daily participation** (visible 25/adaptive bar), **session pacing** (5 hearts), and **mastery evidence** (`LetterStat` / `UnitProgressStat`).

**Ending a sitting.** Besides running out of hearts, adaptive play can end via Winner → `goalComplete`, the home control → `homeTapped`, or parent skip of an in-progress progress check → `practiceComplete`. `tiredSignal` remains legacy-only in `GameState`.

#### Six-session retention progress check

The longer retention check follows completed practice, not the calendar, and runs **independently per layer**:

```
Sessions 1–6: complete the 25-correct goal in that layer
Next session in that layer: adaptive retention progress check
After check: reset that layer's counter and begin the next six-session cycle
```

Scheduling is handled in `ProfileManager.resolveDailyPractice(...)` for letters and its twin `resolveNumberDailyPractice(...)` for numbers (same shape, backed entirely by the number twin fields — `completedNumberSessionsInCycle`, `numberLearningCycleStartDay`, `activeWeeklyNumberAssessment`, `recentWeeklyNumberAssessments`, `weeklyIntroducedNumbers`, and the `numberDailyPractice*` counters; the number cohort is built by `Profile.buildAdaptiveWeeklyNumberAssessment` and stored as `WeeklyNumberAssessment`, a `typealias` of `WeeklyLetterAssessment` keyed by number strings). For letters:

- Each claimed 25-answer Winner milestone increments `completedLetterSessionsInCycle`. Same-day replay sessions count independently when they complete the next 25-answer chunk.
- At six completed sessions, the next playable session becomes `.reviewTest`, regardless of weekday or elapsed calendar time.
- The visible `dailyGoalTarget` is frozen from the adaptive audit plan (normally 8–40). `adaptiveSessionFloor` is 8 and `adaptiveSessionCeiling` is 40: when full coverage would exceed 40, lower-priority audit entries are omitted. The check ends as soon as every planned audit letter has a non-pending outcome, or after the independent-evidence cap is reached **only once every planned letter has at least one independent attempt**.
- If no eligible audit letters exist yet, planning safely remains `.introduction` while preserving the six-session count; the next session retries assessment planning.
- The check runs in whichever layer is due: a letters check after six claimed letter sessions, a numbers check after six claimed number sessions. The dormant reading layers never schedule one.

The letters-layer state lives on `Profile` (each field has a numbers twin, listed in [Data storage](#data-storage)):

| Field | Purpose |
|---|---|
| `dailyPracticeDay`, `dailyPracticeAttempts` | Local-day counter behind the visible 25/adaptive progress bar and extra-round display. |
| `dailyPracticeWinnerClaimedDay`, `dailyPracticeWinnerClaimedMilestone` | Local-day Winner claim receipt; prevents same-day Winner from reappearing until the next full goal chunk is complete. |
| `dailyTargetAskDay`, `dailyTargetAskCounts` | Per-letter target-ask counts for the current local day; seeds each new sitting's engine counts so the 10-ask-per-letter introduction-day cap holds per calendar day. |
| `learningCycleStartDay` | Informational start date for the current practice-count cycle; it does not trigger the check. |
| `weeklyIntroducedLetters` | Letters introduced as spotlights during this six-session cycle (legacy field name retained for storage compatibility). |
| `completedLetterSessionsInCycle` | Number of claimed 25-answer letter sessions in the current cycle, capped at six. |
| `activeWeeklyAssessment` | The frozen adaptive audit and per-letter evidence for the current progress check (legacy type name retained). |
| `recentWeeklyAssessments` | Completed assessment snapshots, capped to recent history. |

The review/test is deliberately two-layered: a visible participation goal plus a stricter retained/watch/review assessment.

**1. Audit freeze.** `previewSessionPlan` can show that the next session is a progress check without mutating the profile. On the first real answer, `commitSessionStartIfNeeded` starts `activeWeeklyAssessment` if needed and freezes an adaptive audit into `cohortLetters` and `results`. The planner prioritizes eligible target-introduced letters (`introducedLetters`, plus any historical target-attempt stats), parent-marked-but-unverified letters, and **letters introduced during the current six-session cycle** — even ones that already look fluent — but it caps the frozen audit at 40 planned questions so the check stays child-sized. Distractor-only exposure stays out because the child was never asked to produce that answer. Cohort letters still earn their four-attempt retention rerun instead of being demoted to a one-tap probe. Parent `.reset` overrides still excise a letter entirely. The frozen `dailyGoalTarget` keeps the progress bar stable for resumes, and unfinished checks reuse persisted assessment evidence.

**2. Target ordering.** During `.reviewTest`, `AdaptiveGameState.buildPlainReviewRound(...)` first asks letters that still need audit evidence. The first audit target when today's `dailyPracticeAttempts` is still 0 prefers a fluent or solid cohort letter as a "warm win" before the harder grind (not necessarily the first round of a later same-day session if the bar already moved). After that, candidate scoring favors new/weak/slipped material, previous misses, remaining planned attempts, and review priority while avoiding immediate repeats. A quota-aware coverage guard takes over near the end of the planned evidence budget: if the remaining planned independent slots are no more than the number of zero-attempt audit letters, the picker forces those unattempted letters before spending another slot on repeats. After the adaptive audit is resolved, remaining daily rounds are filler review and are tagged as ordinary review, not assessment evidence:

```
profile.snapshot.lettersByReviewPriority
+ profile.lettersByConfidence
+ weeklyReviewLetters
+ profile.learningLetters
```

`uniqueEligibleTargets(...)` preserves first-seen order while deduping. `preferNotRecentlyTargeted(...)` still avoids immediate repeats when possible.

**3. Adaptive evidence.** Each audit letter has a `WeeklyAssessmentLetterResult` bucket. Every measuring bucket gets a single bonus extension on a *borderline* outcome so a 4-year-old's stray tap can never definitively doom a letter, but decisive wins and decisive failures skip the extension to keep the test honest:

- `cohort` — every letter introduced this cycle; 4 planned attempts, 3-correct retains. A 2/4 split earns a bonus 5th tap and re-judges with the same 3-correct bar; 0–1/4 stays decisive `needsReview`.
- `slipped` — previously mastered but currently demoted; 3 attempts, majority-correct retains. A 1/3 split earns a bonus 4th tap; 0/3 stays decisive.
- `emerging` — 3 planned attempts, with one corroborating extension on a 1/3 split.
- `solid` / `fluent` — 1 planned verification attempt, with one recheck after a miss. Fluent misses resolve to `Watch` before remediation so one bad tap does not erase strong history.
- `parentMarked` — 1 probe attempt that reports `Observed`; it never turns a parent override into earned system evidence and never extends.

Only independent, non-impulsive, non-assisted target attempts with `RoundIntent.weeklyAssessment` count toward this evidence. Assisted rescue rounds, delayed rescue rounds, revealed/highlighted attempts, impulsive taps, and post-audit filler review may still advance the visible daily bar, update diagnostics, and affect hearts/governor behavior, but they do **not** satisfy retained/watch/review evidence and do **not** consume the adaptive audit's independent-evidence cap.

**4. Completion, skip, and archive.** Adaptive assessments complete as soon as every audit letter has a non-pending outcome. The frozen hard cap can complete only after every planned audit letter has at least one independent attempt. Completed assessments are appended to `recentWeeklyAssessments`, capped to the latest 12, and both `weeklyIntroducedLetters` and `completedLetterSessionsInCycle` reset. The completed active assessment remains available for same-day filler review; the next local day clears it. Legacy in-flight assessments keep their old evidence rules, but their visible target is capped at 40.

Parents can also skip an unfinished progress check from the parent dashboard's ellipsis menu (`Skip current progress check`). During a check, a parent can reach the same action by long-pressing the replay button for two seconds; `GameView` opens the parent gate and archives the partial assessment through `ProfileManager.skipActiveWeeklyAssessment(...)`. Skip resets the six-session cycle and clears the active check immediately. The partial result remains visible in the dashboard's **Progress check** card and in **Diagnostics → Letter retention**.

Daily spotlight candidate selection also skips letters visually confusable with the current cycle's cohort unless the related letter is already strongly known. For example, if `B` was introduced during this cycle and still lacks strong evidence, candidates like `D`, `P`, and `Q` are skipped for the rest of the cycle. This keeps variety without stacking visually similar new symbols too early.

The six-session progress check exists per layer: letters and numbers each keep their own cycle and assessment history. When a number check finalizes, memory-scheduler follow-ups are stamped on the missed numbers (`needsReview` → next day, `watch` → 3 days) before the snapshot is archived to `recentWeeklyNumberAssessments`. There is no parent skip action for an unfinished **number** check today — `skipActiveWeeklyAssessment` operates on the letters assessment only, so the in-game long-press skip is effectively a no-op during a numbers check (it returns `false` when no letters assessment is active), and `ParentNumberDashboardView` exposes no skip action. Reading-layer sessions are dormant, so the 25-round / adaptive-check contract is the only practice contract the shipped app exposes.

#### Warm-up length adapts to sparse data

```
knownLetters.count (doc alias: warmupPoolCount) ≥ 6  →  planner returns 5-round warm-up
                                                ≥ 4  →  planner returns 3-round warm-up
                                                ≥ 3  →  planner returns 2-round warm-up
                                                < 3  →  planner returns no warm-up
```

`warmupPoolCount` is `knownLetters.count` in the letters branch. The numbers branch runs the same ladder over `knownNumbers.count`, then additionally caps the result by how many known numbers are review-due right now (`min(baseWarmup, max(1, dueWarmupCount))`), so a numbers warm-up never pads with material the scheduler considers fresh. The dormant syllable/word phases return `warmupLength = 0` in their planner branches and would start directly in `syllableRecognition`, `syllableCalibration`, or `wordReading` if they were ever reached.

A `SessionPlan` must be exactly executable by `AdaptiveGameState`: the planner does not promise a 2-round warm-up with only 2 known letters, and the dormant reading branches do not promise warm-ups the engine would skip.

`AdaptiveGameState.init` treats this as a developer contract too: debug assertions flag a letter plan that promises warm-up with fewer than 3 known letters, or any reading-layer plan that promises warm-up before a real reading warm-up phase exists.

### 4. Session end & "Play again"

[`SessionEndView`](Pismenka/Views/Summary/SummaryView.swift) (file `SummaryView.swift`, type `SessionEndView`) is shown only when the game exits through `GameView.onExit` → `ContentView.sessionEnd` — not when the child taps **Home** mid-session (that path calls `endSession` and returns straight to `ProfileSelectView`).

When shown, the screen is **always celebratory**: confetti, sticker card, day-streak / letters-mastered stats, optional focus-graduation badge, and a tomorrow preview. Headlines by `SessionEndReason`:

- Daily goal complete → "You did it!"
- Hearts depleted → "Nice try today!"
- Legacy fatigue checkpoint (`.tiredSignal` on restored summaries only) → "Great practicing!" Adaptive daily play no longer auto-ends on mistakes while hearts remain.
- Parent extra-practice session complete (`.practiceComplete` from `extraPractice` mode) → "Practice complete!"

There is no "you lost" UX. Day-streak copy stays positive ("Day N in a row", optional best chip).

Actions (left → right): **house** → `ProfileSelectView`; **arrow.counterclockwise** (Play again) → same-day re-entry via `ProfileManager.previewSessionPlan` in `startGame`. `commitSessionStartIfNeeded` still runs only after the first answer (`GameView`), keeping streak and `focusActiveDays` idempotent on replays (see [Multi-session same-day contract](#multi-session-same-day-contract)). `ProfileManager.endSession` on exit mainly persists `bestSessionStreak` from the summary; day-streak and focus-day commits already happened at first answer.

**Checkpoint resume (orthogonal to this screen).** `SessionCheckpointStore` plus `ContentView.restoreCheckpointIfPossible` / profile selection can resume mid-calibration or mid-game from a saved plan and snapshot without passing `SessionEndView`. Checkpoints are stored in **one slot per learning layer** (letters / numbers), and restore reads the slot for the current `AppSettings.activeLearningLayer` — switching the home-screen layer never discards the other layer's in-flight session, and a restored numbers checkpoint additionally re-checks `hasCompletedNumberCalibration` (letters: `hasCompletedCalibration`) before resuming. `GameView` checkpoints on appear, after answers, and on background/inactive, always into its plan's layer slot; checkpoints clear per layer on normal exit, home, session end, and many parent resets.

Note: `.homeTapped` exists on `SessionEndReason` for summaries/tests, but the in-game Home button does not navigate to this screen today.

### 5. Parent dashboard

Holding a profile card → context menu → **View results** (or **Edit profile** for the edit sheet) → parent gate → [`ParentDashboardView`](Pismenka/Views/Parent/ParentDashboardView.swift) or [`EditProfileView`](Pismenka/Views/Profile/EditProfileView.swift). When the home screen is in Numbers mode (`AppSettings.activeLearningLayer == .numbers`), **View results** opens the sibling [`ParentNumberDashboardView`](Pismenka/Views/Parent/ParentNumberDashboardView.swift) instead — see [Numbers dashboard](#numbers-dashboard) below; the rest of this section describes the letters dashboard. The dashboard re-reads `@Published` profiles on each render, so it updates live as rounds are recorded. The dashboard is deliberately built around two parent use cases — the **15-second glance** between sessions and the **5-minute audit** every week or two — and the layout is organized into three tiers so that both work without scrolling past content meant for the other:

```
Tier 1 — 15-second read       Tier 2 — 1-2 minute audit       Tier 3 — 5-minute deep dive
─────────────────────────     ─────────────────────────       ─────────────────────────
headerCard                    weeklyTestSummarySection        diagnosticsSection (collapsed)
recommendationCard            lettersSection                    ├─ letterRetentionListCard
needsAttentionSection         unitsProgressSection              ├─ weeklyAssessmentRoundsListCard
focusCard                                                       ├─ commonConfusionsListCard
progressGlanceCard                                              └─ rawRoundsListCard
letterPaletteCard
```

#### Tier 1 — the 15-second read

This is what a parent sees in the time it takes to glance during a snack: identity, what to do today, what is on fire, and the four-bucket headline.

- **Header card** — avatar, `Alphabet: <level>` with badge, inline `info.circle` button that opens the glossary alert, day-streak chip (`flame.fill` plus `N-day streak`, or `No streak yet` for empty streaks), best-streak chip when it differs from current, and a `Best level:` row when the lifetime-best alphabet level is higher than the current one. The reading-stage chip described in older specs is not rendered in the current build because the reading layer is dormant. In `DEBUG` builds, long-pressing the header reveals the `AdaptiveDebugOverlay`.
- **Try this today (`recommendationCard`)** — one short recommendation line chosen from recent impulses, confusions, slow-but-correct letters, or the child's name. (The Czech CV readiness recommendation path lives in the dormant reading layer and is not exercised in the current release.)
- **Needs attention** — at-a-glance rows for letters or patterns that need follow-up: current needs-practice letters, recently slipped letters, progress-check watch/review outcomes, and common confusions. Drawn from the same snapshot, weekly-assessment, and round-event fields the dashboard already uses everywhere else.
- **Today's focus card** — the current focus letter, the day count of practice, and a one-sentence explanation of why the engine picked it. (The card is typed to render slabiky/words as well; only letters surface today.)
- **Progress at a glance (`progressGlanceCard`)** — the four-bucket headline used by both the profile cards and the dashboard, in a single rich card:
  - Headline `<confidentlyKnown> / <totalLetters> confidently known` with a green linear progress bar.
  - 3-up stat tiles for **Likely known**, **Needs practice**, **Not introduced** (recently-slipped letters fold into Likely known, matching `parentLetterKnowledgeSummary`).
  - Below the divider, a `Total attempts` / `Overall accuracy` pair derived from `Profile.letterPracticeSummary` (target attempts only).
  - A single aggregate line under the attempts/accuracy row (`letterPracticeSummaryText`): total correct vs target attempts across letters practiced — not the per-row `Seen X · Tested Y` split (that appears only on each `LetterStatRow` in Tier 2).
- **Letter map (`letterPaletteCard`)** — a traffic-light grid of the **entire** alphabet (`Profile.language.letters` in canonical teaching order, so even untaught letters appear) that answers "what's still missing?" in a single glance, before the parent reads any numbers or scrolls to the Tier 2 list. Each tile is colored from the same `parentLetterKnowledgeSummary` buckets the headline uses, collapsed into three states via `paletteCategory(for:summary:)`:
  - **Green** — `confidentlyKnownLetters` ("knows it").
  - **Yellow** — `likelyKnownLetters` ("maybe knows it"; recently-slipped letters fold in here, matching the headline).
  - **Red** — `needsPracticeLetters` ("doesn't know it yet"), plus a **faded/outlined red** variant for `notIntroducedLetters` so a parent can still tell "struggling with it" from "we haven't taught it yet." A note explaining the faded tiles renders only when at least one untaught letter exists.
  - A `<known> / <total>` count sits in the header and a legend below the grid shows live `Knows / Maybe / Not yet` counts. Tiles are display-only (no tap-to-practice) and carry VoiceOver labels like `Á: maybe knows it`. The palette is derived state only — it adds no new model and stays in lockstep with `progressGlanceCard` and the Tier 2 Letters list.

#### Tier 2 — the 1-2 minute audit

The mid-density slice. A parent who is *checking in* — not debugging — gets the latest progress-check result, an actionable per-letter list, and reading progress when relevant.

- **Progress check (`weeklyTestSummarySection`)** — latest retention-assessment summary. Title plus date, optional `Adaptive audit · N assessment rounds` line, outcome badge, cohort confidence tiles, and retained/review/watch/pending metrics. Partial results from a parent-skipped check also appear here.
- **Letters (`lettersSection`)** — every letter the child has interacted with, with header controls:
  - A `Menu` on the right of the section title cycles `LettersSortMode`: **Needs help first** (default), **Strongest first**, **A → Z**. Default puts problem letters at the top so a five-minute audit reaches them without scrolling past mastered ones.
  - For Czech profiles, a row of capsule filter chips selects `LettersCharsetFilter`: **All** (default), **Base** (drop diacritic letters), **Diacritic** (only diacritic letters). The filter is hidden for English profiles.
  - Letters are bucketed into knowledge groups in priority order: `Needs help` (includes `learning` and `exposed` states), `Getting there`, `Recently slipped`, `Practicing now` (the active focus), `Confident`, `Mastered`, `Marked known by parent`, `Reset by parent`, `Not yet seen`. The `strongestFirst` sort reverses that group order; `alphabetical` keeps the order but sorts letters within each group.
  - Each row is the same `LetterStatRow` as before:
    - The letter itself, color-coded by knowledge state.
    - Accuracy percentage, certainty percentage, and `EvidenceStrength` label (`Strong`, `Solid`, `Emerging`, `Not enough data`).
    - `Seen X · Tested Y` — distractor exposures vs target attempts, kept separate.
    - `mixes with …` badge when a confusion pair has ≥3 mix-ups; response-time pip; `replay often` when `promptReplayCount > max(1, targetAttempts / 2)`; recently-slipped marker.
    - Optional "Marked known by parent" / "Reset by parent" badge for overridden letters.
    - **Per-letter actions** — `ellipsis.circle` opens a confirmation dialog in order: **Clear parent override** (if set), **Mark as known**, **Reset (re-teach)**, **Extra practice for {letter}**, **Add note** / **Edit note**, **Wipe stats for {letter}** (if data exists), Cancel.
- **Reading progress (`unitsProgressSection`)** — dormant in the current release (`EmptyView()` today). Designed to surface mastered slabiky/words plus recent syllable and word stats once the reading layer reactivates.

#### Tier 3 — the 5-minute deep dive

Everything raw is collapsed into a single expander so it never crowds the top of the screen. The expander only renders when there is something to show.

- **Diagnostics (`diagnosticsSection`)** — a single button card with title `Diagnostics` and subtitle `Retention, test rounds, confusions, raw history`. Tapping it unfolds:
  - **Letter retention** (`letterRetentionListCard`) — per-letter retention rolled across every *completed* weekly assessment in `recentWeeklyAssessments` (FIFO-capped at the latest **12** completed snapshots), with an `Across N tests` count. Drawn from independent-evidence buckets only, so parent overrides don't leak in as "passed."
  - **Recent test rounds** (`weeklyAssessmentRoundsListCard`) — the last 50 `RoundEvent`s with `intent == .weeklyAssessment`, newest first. Each row shows `target → selected`, timestamp, response time, and stacked `parentExplanations` (no separate intent chip).
  - **Common confusions** (`commonConfusionsListCard`) — up to the top three pairs at ≥3 mix-ups (`confusedWith`; impulsive taps stay in `impulsiveSelections`, not here).
  - **Raw round history** (`rawRoundsListCard`) — the most recent `RoundEvent`s with a `Show 30` / `Show all` toggle, capped to `RoundEvent.maxRetained`. Includes intent, response time, the `discounted` flag, and the full `parentExplanations` list per round.

#### Overflow menu, glossary, and notes

The toolbar's `ellipsis.circle` button opens a confirmation dialog with profile-level actions, in this order: **Edit profile** (dismisses the dashboard sheet, then opens edit), **Sound settings**, **Add parent note** or **Edit parent note**, **What do labels mean?**, **Undo last reset** (when available), **Skip current progress check** (only for an unfinished `activeWeeklyAssessment`), **Re-run calibration**, **Pick a new focus letter** (when active), **Reset day streak** (only when `dailyStreakCount > 0` or `lastSessionDay` is set), then **Cancel**. The confirm alert title matches that label; its primary button still says **Skip test**. The same skip is available in-game during `.reviewTest`: long-press the replay button → parent gate → `skipActiveWeeklyAssessment` → `practiceComplete` summary → `startGame` again (no `SessionEndView`). Granular resets also appear on per-letter action dialogs (see [Granular resets](#granular-resets)).

The glossary is the single source of truth for parent-facing taxonomy and is reused everywhere a label appears. It documents both the four headline buckets (`Confidently known`, `Likely known`, `Needs practice`, `Not introduced`) and the per-letter knowledge states (`Needs help`, `Getting there`, `Recently slipped`, `Practicing now`, `Confident`, `Mastered`, plus the two override states). The header's inline `info.circle` and the ellipsis menu's `What do labels mean?` both open the same alert text, so a parent never has to guess how the summary tiles relate to the per-letter rows.

#### Numbers dashboard

[`ParentNumberDashboardView`](Pismenka/Views/Parent/ParentNumberDashboardView.swift) is a deliberately focused sibling of the letters dashboard, opened by **View results** while the home screen is in Numbers mode. Its sections, top to bottom:

- **Header card** — avatar, a `NUMBERS` eyebrow, headline `<confident> of <total> confident`, a chip with the current `NumberInstructionalBand.displayName` (Beginner / Developing / Strong / Fluent), and a `Focus <n>` chip when `currentFocusNumber` is set.
- **Number knowledge (`bucketsCard`)** — Confident / Likely / Practice / Not-yet tiles from `parentNumberKnowledgeSummary(pool:)`. The pool is `ProfileLearningSnapshot.numberKnowledgePool` — the **introduced/practiced** numbers plus anything with learning evidence, deliberately **not** all 101 numbers of the 0–100 curriculum — and a caption says so explicitly. The same summary over the same pool drives the profile card's Confident n/m headline in Numbers mode.
- **Number map (`numberMapCard`)** — a traffic-light grid over the pool in pedagogical introduction order; tapping a tile opens per-number actions (**Extra practice for {n}** → `startPracticeSession(profileId:number:)`, **Reset {n} (re-teach)** → `resetNumberStats`).
- **Recent number rounds** — the last 30 `RoundEvent`s **filtered by `unitKind == .number`**, so letter rounds never leak into the numbers history. (The letters dashboard's **Raw round history** is not kind-filtered today, so on a mixed-play profile it can include number rounds; its weekly-assessment list filters by intent.)
- **Common confusions** — top pairs from `numberStats[*].confusedWith` at ≥ 2 mix-ups.

The toolbar ellipsis exposes **Undo last reset** (shared `lastResetSnapshot`), **Re-run numbers calibration** (`resetNumberCalibrationOnly`), and **Pick a new focus number** (`resetCurrentNumberFocus`, shown while a focus number is active). Every reset confirmation also clears the numbers-layer session checkpoint. There is no numbers equivalent of the letters dashboard's diagnostics tier, per-number overrides/notes, or progress-check skip today.

---

## The adaptive learning model

### Per-letter mastery (`LetterStat`)

[`LetterStat`](Pismenka/Models/LetterStat.swift) is the per-letter record. The fields it tracks:

| Field | Meaning |
|---|---|
| `recentResults: [Bool]` | Last 8 target attempts. The last 5 drive the "known" rule; the full 8 drive focus graduation. |
| `targetAttempts` / `targetCorrect` | Lifetime totals when the letter **was** the asked-for target. |
| `distractorExposures` | Lifetime count of times the letter appeared on screen but **wasn't** the target, including intentional cameo letters. Never affects accuracy. |
| `firstSeenAt` / `lastSeenAt` | First/most-recent on-screen appearance (target or distractor). |
| `lastTestedAt` | Most-recent target attempt only — used for staleness biasing. |
| `parentOverride: LetterOverride?` | `.markedKnown(date:)` or `.reset(date:)`, see [overrides](#per-letter-overrides). |
| `recentResponseTimes` | Rolling target-attempt timings (cap 10); ≥4 samples required for `isFluentKnown`. |
| `wasKnownBefore` / `demotedAt` | Set on known→not-known demotion; feed `recentlySlipped` and parent summary. |
| `confusedWith` / `impulsiveSelections` | Mistake maps (confusion vs impulse); dashboard / contrast policy. |
| `memoryState: LetterMemoryState` | FSRS-inspired per-letter memory model (difficulty, stability, lapses, predicted retrievability, next due review). Drives `reviewPriority` / `isReviewDue`, which feed warm-up ordering, the introduction-day needs-work pool, and maintenance review. Migrated automatically from legacy attempt counts on first decode. |
| `confusionEvidence: [String: LetterConfusionEvidence]` | Pair-level confusion tracking keyed by displayed distractor — opportunities, mistakes, and recent clean discriminations, so old mix-ups can retire. Its `isActive` gate drives contrast rounds and the introduction-day confusion-partner interleave. |
| `promptReplayCount` | Speaker replays while letter was target (dashboard hint). |
| `parentNote` | Parent-only note; not used by adaptive engine. |

Four named evidence tiers:

- **`isKnown`** — ≥ 80% of the last 5 target attempts (minimum 2 attempts for letters). Drives `Profile.knownLetters`, warm-up, and ordinary review/distractor pools.
- **`isStrongKnown`** — at least 4 target attempts, ≥ 80% recent accuracy, and `EvidenceStrength >= .solid` (Wilson 95% lower bound ≥ 0.6, no longer multiplied by response speed). Drives strong accuracy evidence and backs ordinary easy slots.
- **`isFluentKnown`** — strong-known plus at least 4 timing samples with a fast median response. The single place response time matters: it earns a *positive* upgrade for the hardest roles (confusable-pair proof, mixed-case/visual-only traps, safest easy distractors). Slow medians never demote a letter out of `isStrongKnown` — they just fail to promote it to `isFluentKnown`. See [Asymmetric speed rule](#asymmetric-speed-rule).
- **`isFocusGraduated`** — ≥ 7/8 of the last 8 target attempts (minimum 8). Stricter; only the current focus needs to clear this bar to graduate and add itself to `everMasteredLetters`.

`UnitProgressStat` uses the same 80% of last-5 shape with a 3-attempt minimum for syllables and words. Numbers do not use `UnitProgressStat` at all: `NumberStat` is a `typealias` of `LetterStat`, so every field and evidence tier in this section applies verbatim to `Profile.numberStats` (keyed by `"0"`…`"100"`), including the memory scheduler and confusion evidence.

The tiers intentionally don't overlap awkwardly: a focus letter that crosses `isKnown` (≥ 4/5) but not yet `isFocusGraduated` is **excluded** from `Profile.knownLetters` until graduation, so level math stays clean. A 2/2 calibration letter is emerging-known enough for warm-up and gentle distractors, but it is not fluent-known enough for B/D-style confusable pairs, mixed-case traps, or visual-only distractors.

`EvidenceStrength` is parent-facing (`notEnoughData`, `emerging`, `solid`, `strong`) and exists on both `LetterStat` and `UnitProgressStat`, so syllables and words share the same emerging/strong/mastered vocabulary even though only letters have parent overrides and glyph-confusion policy.

`ProfileLearningSnapshot.parentLetterKnowledgeSummary(...)` is the parent-facing rollup used by both the profile cards and the dashboard:

- **Confidently known** — `(strongKnownLetters ∪ currentlyMasteredLetters ∪ everMasteredLetters)`, intersected with the active alphabet and current `knownLetters` pool. Three accepting paths: cleared the Wilson 95% bar, currently passing the strict 7/8-of-last-8 bar, **or** ever cleared that strict bar and still passing the loose 4/5-of-last-5 check right now. The ever-mastered path keeps the lifetime trophy translating into the headline count even when focus has rotated away from the older letters and they no longer have a fresh 8-attempt window — without it the count silently shrank as the child's repertoire grew.
- **Likely known** — letters in `knownLetters` that lack strong/current-mastery evidence, **plus** `recentlySlipped` (ever-mastered letters that aren't currently passing the loose check). Recently-slipped letters belong with "we believe they know it, it's wobbly right now," not with truly weak letters.
- **Needs practice** — introduced active-alphabet letters that are neither confident, likely known, nor not-introduced. The set is strictly "letters that have never reliably cleared the bar"; previously-mastered letters wobbling in the recent window are explicitly carved out into the likely-known / recently-slipped path so a single bad session can't dump them here.
- **Not introduced** — active-alphabet letters still in `unseenLetters`.
- **Recently slipped** — separately exposed (`recentlySlippedLetters` / `recentlySlippedCount`) for callers that want to label these distinctly. The dashboard's **Needs attention** card already surfaces them as their own row; the four headline buckets fold them into likely-known so the totals always add to `totalLetters`.

This deliberately separates the parent's current answer ("what do they confidently know today?") from the lifetime trophy set (`everMasteredLetters`), which continues to drive alphabet levels and celebration history. The ever-mastered union inside *confidently known* re-introduces the trophy only when current evidence also agrees; an ever-mastered letter that is *not* currently passing the loose check falls into likely-known / recently-slipped instead, so the headline never overstates.

`Profile.letterPracticeSummary` is a derived parent-dashboard aggregate over letter target attempts only: total attempts, total correct answers, attempted-letter count, and overall accuracy. It intentionally ignores distractor exposures so the top-line percentage matches "letters the child was actually asked to answer," while the row-level `Seen X · Tested Y` split still shows exposure volume.

`Profile.knowledgeState(for:)` rolls all of this up into a single `LetterKnowledgeState` enum used by the dashboard. The current dashboard categories are:

```
unseen
exposed
learning        enum case retained for dashboard labeling, not returned by current resolver
tentative       enum case retained for dashboard labeling, not returned by current resolver
needsHelp       attempts > 0, recent accuracy < 50%
gettingThere    attempts > 0, recent accuracy ≥ 50%, not yet confident
known           enum case retained for dashboard labeling; resolver currently returns confident
confident        isKnown, not mastered
mastered         currentlyMasteredLetters contains the letter
recentlySlipped  in `everMasteredLetters`, `wasKnownBefore`, and no longer passing loose `isKnown`
focus            current `currentFocusLetter` (checked after `.mastered`; a letter still in the 7/8 graduation window resolves as `.mastered`, not `.focus`)
markedKnown      parent override
parentReset      parent override
```

`exposed` includes letters that have only appeared as distractors. That can happen accidentally in the sparse-pool fallback path, or intentionally via a capped cameo letter. Either way, `targetAttempts == 0`, so the app treats the letter as seen but not tested or formally introduced.

The two parent-override states sit outside the data-driven flow and label themselves explicitly so the dashboard never confuses *"I marked it"* with *"they actually proved it"*:

```
markedKnown   (LetterOverride.markedKnown — "Marked known by parent")
parentReset   (LetterOverride.reset       — "Reset by parent")
```

### Alphabet levels & reading stages

[`AlphabetLevel`](Pismenka/Models/SkillLevel.swift), `NumberInstructionalBand`, and `ReadingStage` are separate tracks in the codebase. The alphabet and numbers tracks are active; `ReadingStage` exists as future-version scaffolding.

```
Alphabet track (active, shipped):
Novice → Beginner → Intermediate → Advanced → Expert crown

Numbers track (active peer layer; NumberInstructionalBand, never derived from AlphabetLevel):
Beginner → Developing → Strong → Fluent
(number recognition 0–100; drives the numbers confusion-policy stage and grid freeze/clamp)

Czech reading track (dormant; syllable/word sessions are not scheduled — each letters session plan clears `syllablesUnlockedAt` / `wordsUnlockedAt` even though graduation may briefly stamp unlock metadata; the next planned layer now that numbers have shipped):
Locked → Syllable Starter → Reader → Word Builder → Storyteller
```

Alphabet levels use `Profile.everMasteredLetters`, a monotonic `Set` so a letter can't double-count if it graduates → demotes → re-graduates.

| Alphabet level | Requirement | Grid / case relationship | Confusion / case behavior | Badge |
|---|---:|---|---|---|
| Novice | 0–9 mastered letters | Usually 4 options; the live grid is still computed from known/strong-known evidence, not the trophy alone. | Gentle: similar-shape distractors avoided. | 🌱 |
| Beginner | 10–14 mastered letters | Trophy tier only; 6 options also require the separate known/strong pool gate **and** grid-performance promotion evidence. | Safe fluent-known pairs: similar letters allowed only when both sides are accurate and quick. | 🌟 |
| Intermediate | 15–19 mastered letters | Often the first tier where the 6-option *pool-safety* gate can be satisfied (`known ≥ 15`, `strong ≥ 10`); promotion still needs `gridPerformance[4]` evidence. | Same as Beginner, with a larger known pool. | 🚀 |
| Advanced | 20+ but not all letters | Does not automatically mean 8 options; 8 requires about 85% of the active alphabet known, a strong-known pool, **and** `gridPerformance[6]` promotion evidence. | Intentional similar-shape practice; lowercase distractors and visual-only lookalikes can appear when fluent evidence allows them. | 🏆 |
| Expert | All letters in language | Usually keeps the widest earned letter grid; stays in letter maintenance in the current release. | Whole-alphabet crown and mixed-case review. Stays in letter maintenance in the current release (the Czech reading layer is dormant). | 👑 |

Reading stages (dormant; the reading layer never unlocks in the current build) use `syllablesUnlockedAt`, `everMasteredSyllables`, and `everMasteredWords`:

| Reading stage | Requirement | Badge |
|---|---|---|
| Locked | Reading layer not unlocked | 🔒 |
| Syllable Starter (`cvBridge`) | Reading unlocked, before 10 mastered slabiky | 🔤 |
| Reader (`syllableReader`) | 10 mastered slabiky | 📖 |
| Word Builder | Reader + 5 mastered words | 🧩 |
| Storyteller | Word Builder + 20 mastered words | ✨ |

The `0–9` / `10–14` / `15–19` letter thresholds are an intentional rebalance of the **alphabet trophy** toward longer early play. Tests should treat these values as the current alphabet-level contract, not a typo from the older 0–4 / 5–9 / 10–14 split.

Two alphabet fields plus two engine-only difficulty signals are tracked:

- **`alphabetLevel`** — parent-facing alphabet progress derived from `everMasteredLetters`; monotonic during normal play, but drops when `resetAllProgress` clears `everMasteredLetters`.
- **`instructionalBand`** — derived when building `Profile.snapshot` from `strongKnownLetters ∩ everMasteredLetters`. It gates confusable-distractor policy, automatic lowercase targets/distractors, and visual-only distractors, and can sit below `alphabetLevel` after recent slips.
- **`letterOptionsPerRound`** — computed on `Profile` via `AlphabetLevel.letterOptionsPerRound(...)` from known/strong **pool-safety** counts, `gridPerformanceStats` promotion evidence, and between-session hysteresis; not persisted. Pool-safety promotes at known ≥ 15 / strong ≥ 10 (6-grid) and known ≥ `max(20, ceil(0.85 * alphabetCount))` / strong ≥ threshold − 3 (8-grid), but only after the current tier's `GridPerformanceStat.supportsPromotion` passes.
- **`gridPerformanceStats`** — persisted `[Int: GridPerformanceStat]` keyed by displayed option count (4 / 6 / 8). Updated on independent (non-assisted, non-impulse) adaptive-daily target attempts in `ProfileManager.recordAnswer` when the displayed count is 4, 6, or 8. Measures visual-search skill separately from alphabet knowledge.
- **`lastFrozenLetterOptionsPerRound`** — persisted previous session grid for demotion hysteresis (known **and** strong within 2 of the promotion thresholds, plus `supportsMaintenance` on the held grid size). `ProfileManager.recordSessionFrozenGrid` writes it from `AdaptiveGameState` init. Survives `resetAllProgress` today, as does `gridPerformanceStats`, so hysteresis/performance evidence can carry over after a full wipe unless cleared separately.
- **`highestAlphabetLevelEverReached`** — monotonic alphabet trophy; never decreases, never reset by `resetAllProgress`. Surfaces in the dashboard as `Best:` whenever it diverges from the current alphabet level.

An alphabet level-up celebration fires **at most once per profile per alphabet level**. The receipt is `Profile.celebratedAlphabetLevels: Set<AlphabetLevel>` — durable across sessions, preserved through resets, indifferent to any future demotion path. New profiles default with `.novice` already celebrated so the first popup parents usually see is crossing into **Beginner** at 10 mastered letters (`AlphabetLevel.threshold(.beginner)`). (`threshold(.novice)` is 5 in code, but `from(letterMasteredCount:)` already returns `.novice` for 0–9, so that threshold is not a separate promotion step.)

The alphabet table is also the progression contract the tests check directly, but the engine splits difficulty-sensitive behavior: the frozen letter-grid size comes from `Profile.letterOptionsPerRound`, while the frozen `instructionalBand` controls confusable-distractor policy, automatic lowercase targets/distractors, and visual-only distractors. Dashboard badges and level-up celebrations keep reading `alphabetLevel` / `highestAlphabetLevelEverReached`; the reading-stage chip from older specs is not shown while the reading layer is dormant.

### Answer-grid sizing: 4 / 6 / 8 options

The answer-grid size is deliberately **not tied directly to `alphabetLevel`**. A child can be Beginner, Intermediate, Advanced, or Expert for trophy/dashboard purposes while the live grid is still decided by current known-letter **pool safety** plus demonstrated independent performance at the current grid size. The product behavior is:

```
newer / less certain profile  -> 4 options
pool safety + strong 4-grid performance  -> 6 options
near-whole alphabet safety + strong 6-grid performance  -> 8 options
```

The live resolver is `Profile.letterOptionsPerRound`, implemented by `AlphabetLevel.letterOptionsPerRound(...)`. It uses two alphabet-scoped counts plus `Profile.gridPerformanceStats`:

- `knownAlphabetLetterCount` — letters in `Profile.knownLetters`, which come from `LetterStat.effectiveIsKnown` (normally at least 80% over the last 5 target attempts with a 2-attempt minimum, plus parent `.markedKnown`; parent `.reset` removes the letter). The current focus letter is excluded until it graduates unless the parent explicitly marked it known.
- `strongKnownAlphabetLetterCount` — letters in `Profile.strongKnownLetters`, which require at least 4 target attempts, at least 80% recent accuracy, and `EvidenceStrength >= .solid`. Parent `.markedKnown` does not synthesize strong evidence.
- `gridPerformanceStats[optionCount]` — `GridPerformanceStat` for independent outcomes recorded while that many choices were on screen (rolling window of 20). Promotion needs enough trials, recent accuracy ≥ 0.85, and Wilson lower bound ≥ 0.70.

Pool-safety thresholds (necessary but not sufficient alone):

| Grid | Required pool safety | Required performance evidence |
|---:|---|---|
| 4 options | Default while wider gates are not satisfied. | — |
| 6 options | `knownAlphabetLetterCount >= 15` **and** `strongKnownAlphabetLetterCount >= 10`. | `gridPerformance[4]?.supportsPromotion(minimumTrials: 12)` |
| 8 options | `knownAlphabetLetterCount >= max(20, ceil(0.85 * alphabetCount))` **and** `strongKnownAlphabetLetterCount >= thatThreshold - 3`. English (26 letters) means 23 known / 20 strong. Czech (41 letters) means 35 known / 32 strong. | `gridPerformance[6]?.supportsPromotion(minimumTrials: 16)` |

Session behavior:

- The base grid is frozen at `GameView` / `AdaptiveGameState` init as `frozenLetterOptionsPerRound`, so a letter becoming known or slipping during a session does not resize the session baseline mid-run.
- Per round, `resolvedLetterOptionCount(for:profile:)` can still narrow the displayed count below that baseline: unknown / not-yet-known / recently-slipped / active-drill-focus targets stay at **4**; strong-but-not-fluent targets cap at **6**; fluent-known targets may use the full frozen grid. Progress-check audit buckets also force smaller grids (cohort/slipped/emerging/parentMarked → 4; solid → 6).
- `Profile.lastFrozenLetterOptionsPerRound` stores the previous session's frozen grid. Demotion hysteresis checks known **and** strong within 2 of the promotion thresholds **and** `gridPerformance[heldSize]?.supportsMaintenance` (recent ≥6 of last ≤8 samples at ≥75% accuracy; defaults to held while evidence is thin). Profiles that already had a 6/8 grid keep a continuity window until enough outcomes exist to demote on recent failure.
- `instructionalBand` is separate. It gates similar-shape distractors, lowercase behavior, and visual-only lookalikes; it does not directly choose 4 vs 6 vs 8.
- `LiveDifficulty == .easierUntilStreak` downshifts the displayed grid by **2 options per step** (`governorEaseSteps`, max 2: 8→6→4). Recovery requires **≥4 correct in the last 5 independent rounds** while the current eased `optionCount` is consistent with the step count, then steps back one tier at a time until `liveDifficulty` returns to `.normal` (a 3-round cooldown then blocks sticky re-trips from hearts-low / focus-accuracy latches).
- Numbers sessions run the whole contract through twins: `Profile.numberOptionsPerRound` (pool safety 12 known / 8 strong for 6 options, 25 known / 18 strong for 8, `numberGridPerformanceStats` promotion, `lastFrozenNumberOptionsPerRound` hysteresis) freezes the session grid, and `resolvedNumberOptionCount` clamps per target. See [Numbers peer layer](#numbers-peer-layer).
- Reading-layer slabika/word sessions are designed to stay at 4 options, but that layer is dormant in the current release.
### Daily spotlight, durable focus & scaffolding ladder

In the letter layer, the game now separates **daily variety** from **long-lived remediation**:

| Concept | Stored on | Meaning |
|---|---|---|
| Durable focus | `Profile.currentFocusLetter` plus `focusStartedDay` / `focusPracticedDays` | The letter the child is truly working through over multiple days, including scaffolding, remediation, graduation, and stuck-focus pause logic. |
| Daily spotlight | `SessionPlan.dailySpotlightLetter` | A fresh introduction for variety and the current six-session retention cohort. It can be drilled for the session without clearing an in-flight durable focus. |
| Introduced focus target | `SessionPlan.introducedFocusTarget` | The exact unit introduced today — a `.letter(...)` in letters sessions, a `.number(...)` in numbers sessions. `GameView` uses this for the layer-aware "Meet your letter" / "Meet your number" intro overlay so the UI promise matches the unit the session intends to teach. |
| Review/test plan set | `SessionPlan.weeklyReviewLetters` | Ordered audit letters for the current adaptive review/test plan. |
| Frozen assessment cohort | `Profile.activeWeeklyAssessment.cohortLetters` | The exact letters being measured for retained/watch/review outcomes during the committed review/test day. |

This distinction is important. A daily new letter should not erase `FocusTeachingMode`, `focusActiveDays`, remediation, or paused-focus state. If the child is in remediation, the durable focus continues to drive drilling. Otherwise, an introduction day may use the daily spotlight as the active drill focus while keeping `currentFocusLetter` persisted for the longer learning arc.

The UI contract is intentionally explicit: when `introducedNewFocusLetter == true`, the overlay displays `introducedFocusTarget?.displayText` first, then falls back to older plan fields only for legacy decoded checkpoints. It must not prefer `focusTarget` over the spotlight, because `focusTarget` can still represent the old durable focus while `dailySpotlightLetter` is the unit newly introduced today.

The durable focus letter persists in `currentFocusLetter` until graduation, stuck-focus pause, or parent reset. Parent/dashboard preview of the next teachable letter is `Profile.snapshot.nextFocusCandidate` (`LetterDifficulty.nextFocusWithReason` with paused-focus blocking only). Runtime **daily spotlight** selection uses the same core picker via `ProfileManager.pickNextDailyIntroductionLetter`, but with a stricter `blocked` set (introduced, weekly cycle, unsafe weekly confusables, paused focus). When `currentFocusLetter` is nil on an introduction day, the spotlight may also become the durable focus. Reading sessions are typed via `FocusTarget` (see below) but do not run in the current release and therefore do not participate in either weekly assessment store (letters use `activeWeeklyAssessment`; numbers use the twin `activeWeeklyNumberAssessment`).

The picker prefers:

- Stale introduced weaknesses that need re-teaching.
- Letters whose visually confusing prerequisites are mastered.
- Letters with enough known/learning distractors to teach safely.
- Letters not visually similar to currently weak letters.
- A tagged fallback when no candidate satisfies all readiness checks.

For Czech, diacritic variants are gated by `LetterDifficulty.diacriticBase`: `C` must be mastered before `Č`, `E` before `É` / `Ě`, and so on. The picker reason is persisted in `lastFocusSelection` only when the introduction also assigns `currentFocusLetter` (no durable focus yet). Spotlight-only introductions while durable focus is in flight do not overwrite `lastFocusSelection`.

When the profile's `instructionalBand` allows automatic lowercase targets, lowercase focus targets are introduced after the uppercase alphabet is mastered, even if the parent never changed the case-practice setting. `LetterDifficulty.isEligibleTarget(...)` is the central target gate: visual-only lookalikes such as `1` and `rn` are never eligible focus, mastery, or level-progress targets.

A letter may have appeared earlier as a cameo distractor. That low-pressure glyph exposure is useful, but it does **not** add the letter to `introducedLetters`, does not make it a focus candidate sooner by itself, and does not count as a target attempt.

For a letter-layer introduction day, `buildSessionPlan` (preview or commit) inserts the daily spotlight into `introducedLetters`, sets `lastNewLetterDay`, and may assign `currentFocusLetter` before the first round — formal introduction is not deferred until the letter first appears as a target.

Round generation then has two guardrails around the newly introduced spotlight:

- Warm-up only uses known letters and explicitly keeps the active focus/spotlight out of the option grid, so the new letter is not introduced as an unexplained wrong choice.
- Once drill begins, the spotlight is the active drill focus unless remediation is overriding it. The engine injects it as the target or as a distractor exposure, and `firstFocusAppearanceDeadline` forces it as a target by the second drill round if random target selection has not done so already. The regression contract for a full 25-round introduction session is at least three on-screen appearances and at least one target prompt for the introduced spotlight.

For durable letter-focus sessions, `FocusTeachingMode` determines the effective scaffolding. The teaching mode is `.scaffolded` for `focusActiveDays ≤ 2` and `.normal` afterward; remediation overrides both. Translated into per-round shape (with the standard 4-option Novice grid as the worked example):

| Day of practice | Teaching mode | `effectiveScaffoldingLevel` | Distractors when focus is the target | Confusion policy |
|---|---|---:|---|---|
| Day 1 | `scaffolded` | 3 | Easy slots try `fluentKnownLetters` first (via `pickEasyDistractors`), then fall back to top-confidence known letters | `avoid` |
| Day 2 | `scaffolded` | 3 | Same as Day 1 | `avoid` |
| Day 3 | `normal` | 1 | Easy slots: top-confidence / fluent-known picks with `ConfusionPolicy.avoid`. Normal slots: known letters under `allowFluentPairs` (B/D-type pairs OK if **both** are fluent-known). | Easy: `avoid`; normal: `allowFluentPairs` |
| Day 4+ | `normal` | 0 | All slots from normal known letters under `allowFluentPairs` (no easy tier when scaffolding is 0) | `allowFluentPairs` on normal slots |

At wider grids (6 or 8 options) the easy count is capped by `effectiveScaffoldingLevel`, and the remaining slots are drawn from the normal known pool under the listed confusion policy.

`focusActiveDays` is a **derived** count — `focusPracticedDays.count` — where `focusPracticedDays` is a `Set<LocalDay>`. Set semantics make multi-session-same-day inserts idempotent (multiple "Play again" taps don't bump the ladder twice in one day) and the ladder is recoverable after a crash from the persisted set alone. Remediation forces `effectiveScaffoldingLevel = 3` from the mode; it does not fake the day count.

**Remediation vs stuck-focus pause.** Remediation (`shouldUseRemediation`) enters after `focusActiveDays >= 5` with recent accuracy &lt; 50% on the durable focus, stays until accuracy reaches ≥ 60%, and pre-seeds rescue retries. Stuck-focus pause (`shouldPauseStuckLetterFocus`) fires at `focusActiveDays >= 8` with the same &lt; 50% bar: it moves the focus into `pausedFocusLetters`, clears `currentFocusLetter`, and consumes today's introduction quota (`lastNewLetterDay = today`) so the picker can choose easier material on a later day.

Daily spotlight scaffolding is evidence-based instead of day-count-based when the spotlight is not the durable focus:

| Spotlight evidence | Scaffolding behavior |
|---|---|
| No prior target attempts | Max scaffolding (`3`) and `ConfusionPolicy.avoid`. |
| Fewer than 3 target attempts, or recent accuracy below 50% | Max scaffolding (`3`) and `ConfusionPolicy.avoid`. |
| Some evidence but not yet known | Medium scaffolding (`2`) and `ConfusionPolicy.avoid`. |
| Known but not strong-known | Light scaffolding (`1`) and `ConfusionPolicy.avoid`. |
| Strong-known | No extra scaffolding (`0`) and safe fluent-pair confusables may be allowed. |

This lets a returning daily spotlight letter get appropriate help from its own `LetterStat` evidence rather than pretending it is always on focus day 1 or always inheriting the durable focus's `focusActiveDays`.

When the letter focus is **not** the target, it slips in as a distractor for extra exposure. Correctly avoiding it credits a partial `practiceProgress` toward the Practice Pro stamp.

Syllable focus sessions use `SyllableCurriculum.DistractorStage` instead of `FocusTeachingMode`. When `currentSyllableFocus` is the target, stage selection currently keys off **`profile.focusActiveDays`** (letter-focus practice days): days 0–1 → consonant-only contrasts, day 2 → add short-vowel contrasts, day 3+ → may reserve one length contrast. Non-focus syllable rounds use `.reviewMaintenance`. Word focus sessions use the session's audio-filtered `WordCurriculum.playableWords` pool and `WordCurriculum.distractors(for:candidates:profile:count:)` to prefer words with the same syllable count without selecting unplayable options.

A letter focus graduates when `isFocusGraduated` flips on a target-attempt round. On graduation:

- `currentFocusLetter` clears.
- `everMasteredLetters` grows by one.
- The graduation also **consumes today's formal-introduction quota** (sets the legacy-named `lastNewLetterDay = today`), so a same-day "Play again" doesn't silently introduce a fresh spotlight/focus. The next calendar day picks the next one.
- If this graduation completes the whole alphabet, the current session stays in celebration/letter review; it does **not** interrupt the child with syllable calibration mid-session.

### Numbers peer layer

Numbers (0–100 recognition) ship as a full peer of letters with their own pedagogy, mirrored onto the same engine skeleton. The model lives in [`NumberDifficulty.swift`](Pismenka/Models/NumberDifficulty.swift) and [`NumberInstructionalBand.swift`](Pismenka/Models/NumberInstructionalBand.swift).

**Per-number mastery.** `NumberStat` is a `typealias` of `LetterStat`, so numbers get the full evidence machinery for free: `recentResults`, target/exposure counters, the FSRS-inspired `memoryState` / `reviewPriority`, confusion evidence, response-time windows, and the `isKnown` / `isStrongKnown` / `isFluentKnown` / `isFocusGraduated` tiers. `Profile.knownNumbers` / `strongKnownNumbers` honor the stat's `parentOverride` field, but no numbers UI sets overrides today — the number dashboard has no mark-known/reset-override actions. `WeeklyNumberAssessment` is likewise a `typealias` of `WeeklyLetterAssessment` keyed by number strings.

**Typed units and the bare-digit trap.** Number keys are bare digit strings (`"26"`) in `numberStats` and plan fields, but every typed surface uses the `number:` storage prefix: `FocusTarget.number("5").storageKey == "number:5"`. `FocusTarget(storageKey:)` treats any **bare single character as a letter** (`"5"` → `.letter("5")` — the initializer comment says so explicitly), so number paths must never round-trip bare digits through that initializer. Rounds record `RoundEvent.unitKind == .number`, which the numbers dashboard uses to filter the shared round log to number rounds only.

**Introduction order & readiness.** `NumberDifficulty.introductionOrder` is 1…10, then 0, then the teens, then each decade as anchor-plus-fill (20, 21…29, 30, …), then 100. `isReadyToIntroduce` gates progression on evidence: 0 needs ≥ 7 known digits (or all 10 introduced), teens need ≥ 6 known digits, decade anchors need ≥ 3 known teens (or 15 introduced), within-decade fills need their anchor known/introduced, and 100 needs ≥ 3 known decade anchors (or 90 introduced). `nextFocusCandidate` additionally requires that a safe 4-option grid (3 distant distractors under `.avoid`) can actually be built before introducing a number.

**Confusion policy (`NumberDifficulty.ConfusionPolicy`).** Four stages instead of the letters' three: `.avoid` → `.allowSameOnes` → `.allowSameTens` → `.intentionallyPractice`. The hard-confusable relations are digit **transposes** (`26` ↔ `62`), **lookalike digits** (6/9, 0/8, 1/7), and **cross-length containment** (`1` vs `10`, `2` vs `12`/`20`). Transposes and lookalikes/containment are blocked in every policy short of `.intentionallyPractice` (transposes stay blocked even at `.allowSameTens`); `.avoid` also excludes shared-tens and shared-ones digits and prefers distant decades, so a beginner's grid never puts `26` next to `24`. `pickDistractors` front-loads hard confusables under `.intentionallyPractice`, and `buildNumberRound` relaxes the policy tier by tier (`allowSameOnes` → `allowSameTens` → `intentionallyPractice`) before ever under-filling a grid.

**Instructional band (`NumberInstructionalBand`).** Beginner → Developing → Strong → Fluent, derived in `Profile.snapshot` from introduced/known/strong-known **number** counts — never from `AlphabetLevel`: Developing at known ≥ 8 or introduced ≥ 15; Strong at known ≥ 20 or strong-known ≥ 12; Fluent at strong-known ≥ 40 or known ≥ 60. The band maps to the confusion stage (gentle / same-ones / same-tens / contrast) and, like the letters `instructionalBand`, is frozen at session start and persisted in `GameEngineSnapshot.numberBand` for checkpoint resume. Focus rounds are gentled: an actively scaffolded focus uses `.avoid`, and even a Fluent band's focus rounds cap at `.allowSameTens` — never straight to deliberate confusion drills. Rescue rounds and eased `LiveDifficulty` always fall back to `.avoid`.

**Grid freeze & clamp twins.** `Profile.numberOptionsPerRound` (via `NumberInstructionalBand.numberOptionsPerRound`) mirrors the letters grid contract with numbers-scale thresholds: 6 options need known ≥ 12 and strong ≥ 8 plus `numberGridPerformanceStats[4].supportsPromotion(minimumTrials: 12)`; 8 options need known ≥ 25 and strong ≥ 18 plus `numberGridPerformanceStats[6].supportsPromotion(minimumTrials: 16)`; demotion hysteresis holds a previous 6/8 grid while counts stay within 2 of the thresholds and `supportsMaintenance` passes on the held size. The frozen session grid persists to `Profile.lastFrozenNumberOptionsPerRound` via `recordSessionFrozenNumberGrid`, and the per-round `resolvedNumberOptionCount` clamps weak / slipped / active-focus targets to 4 and strong-but-not-fluent targets to 6, with the same assessment-bucket caps as letters. `numberGridPerformanceStats` update on independent, non-impulsive adaptive-daily number target attempts at displayed counts of 4/6/8.

**Focus ladder & trophies.** The number focus scaffolding level is day-derived — `numberFocusScaffoldingLevel = max(0, 4 − numberFocusActiveDays)` over the idempotent `numberFocusPracticedDays` set — and the stuck-focus pause twin fires at ≥ 8 practiced days below 50% recent accuracy (`pausedFocusNumbers`, 7-day cooldown). Graduation inserts into `everMasteredNumbers`, clears the focus, consumes the day's introduction quota (`lastNewNumberDay = today`), and updates the band trophies: `highestNumberBandEverReached` (monotonic) and `celebratedNumberBands` (one celebration per band, `.beginner` pre-celebrated on new profiles). Both trophies survive `resetAllProgress`, exactly like the alphabet crowns.

**What numbers do not have.** No cameo injection (the `numberCameoExposureDay` / `numberCameoExposuresToday` fields are persisted reserved twins that nothing increments today), no `contrast`/`maintenance` phases, no case practice, no visual-only distractor tokens, no per-number parent overrides or notes UI, and no parent skip for an unfinished number progress check.

### Czech reading progression (dormant scaffolding)

The Czech syllable and word layers are not reachable in the current release; this section documents the still-present scaffolding so future work can re-activate it without rediscovering the design. The letters branch of `ProfileManager.buildSessionPlan(...)` explicitly nils `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` and never promotes `primaryLayer` beyond `.letters` (the numbers layer is scheduled through its own `buildNumberSessionPlan` branch), so none of the reading gates below currently fire.

Czech reading is represented by typed learning units in [`LearningUnit.swift`](Pismenka/Models/LearningUnit.swift):

```
FocusTarget.letter("A")
FocusTarget.syllable("MA")
FocusTarget.word("MÁMA")
```

`FocusTarget.storageKey` prefixes persisted event keys (`letter:A`, `syllable:MA`, `word:MÁMA`) so a letter, syllable, and word can never collide in `RoundEvent` or checkpoints. Letter storage remains backward-compatible for existing bare keys such as `"A"` and `"A|lower"`.

The designed reading curriculum is Czech-only. English profiles that reach Expert remain in Expert letter maintenance, and so do Czech profiles in the current release. The UI frames this positively as "letter expert practice", not as a locked or broken reading path.

- [`SyllableCurriculum`](Pismenka/Models/SyllableCurriculum.swift) seeds **25** short open CV slabiky from `M/L/S/P/T × A/E/I/O/U`, plus **25** long-vowel variants such as `MÁ`, `LÉ`, `SÍ` (50 syllable units total).
- Short syllables depend on their component letters being mastered. The current dormant code also requires `profile.hasCompletedAlphabetForReading` (every alphabet letter in both `introducedLetters` and `everMasteredLetters`) before syllable-layer eligibility; the older early-CV-bridge-before-full-alphabet gate is not implemented in this branch.
- Long-vowel syllables depend on the matching short syllable being **known** (`knownSyllables`), e.g. `MÁ` requires `MA` in the known set — not full mastery.
- [`WordCurriculum`](Pismenka/Models/WordCurriculum.swift) seeds first words such as `MÁMA`, `TÁTA`, `PUSA`, `MÍSA`, `LASO`, each with a syllable decomposition for arcs/building.
- Words unlock when the profile has at least 8 known slabiky across at least 2 consonant families **and** the audio-filtered playable word pool has at least 4 entries with at least one target that can form a valid 4-option round (1 target + 3 audio-backed distractors). Word-reading round generation freezes that same playable pool for the session, persists it in `GameEngineSnapshot`, and passes it into `WordCurriculum.distractors(for:candidates:profile:count:)`; it must not fall back to the older unfiltered `distractors(for:profile:count:)` overload. Every persisted word `RoundEvent.options` set should be a subset of that session playable pool.

The profile stores parallel stats rather than merging every level into `LetterStat`:

| Field | Purpose |
|---|---|
| `syllableStats`, `wordStats` | `UnitProgressStat` dictionaries for reading units. |
| `everMasteredSyllables`, `everMasteredWords` | Lifetime mastery sets for reading stages. |
| `introducedSyllables`, `introducedWords` | Units intentionally shown as targets/focus. |
| `currentSyllableFocus`, `currentWordFocus` | Active reading focus unit. |
| `syllablesUnlockedAt`, `wordsUnlockedAt` | Local-day unlock gates. |
| `hasCompletedSyllableOnboarding`, `hasCompletedSyllableCalibration`, `hasCompletedWordOnboarding`, `hasCompletedWordCalibration` | Persisted flags reserved for reading-layer intro/calibration flows. |
| `readingPracticePaused` | Parent-facing toggle to keep a child in letter-only practice after the reading layer unlocks. Legacy `postExpertPracticePaused` payloads decode into this field. |

`UnitProgressStat` mirrors the target-vs-distractor accounting of `LetterStat`, but has no letter-only parent overrides or glyph-confusion policy. The game records typed answers through `ProfileManager.recordAnswer(profileId:target:...)`, which routes the attempt to the correct stat dictionary.

`CurriculumAudioAvailability` is a narrow model-layer protocol used by `SyllableCurriculum`, `WordCurriculum`, and `ProfileManager` so curriculum gates can ask whether a syllable or word has audio without depending on the concrete `AudioService`. It exposes `hasSyllableAudio` and `hasWordAudio`; production uses `AudioService.shared` via protocol conformance and tests can pass a stub. Reading next-focus previews are designed to use the same audio-filtered pool when audio availability is supplied; the profile snapshot does not synthesize an unfiltered word preview. In the current release, reading routing is forcibly cleared before it can use those predicates in normal gameplay, and no reading-layer `.m4a` files ship in `Pismenka/Sounds/`, so those gates always read as unavailable in production.

#### Syllable unlock UX (dormant)

The flow below is documented for the future reading-layer reactivation; the current build never runs it because reading unlock fields are forced to nil at session start.

When a Czech profile graduates the final letter and therefore satisfies `hasCompletedAlphabetForReading`:

1. The session finishes the current round and records `syllablesUnlockedAt = today`. If this happened through full alphabet mastery, the normal Expert/crown celebration still appears.
2. *(Not implemented in UI yet.)* Czech profiles are intended to see a short end-screen teaser: "Zítra budeme skládat písmenka do slabik."
3. No syllable onboarding or calibration starts in that same session, and same-day **Play again** stays in letter maintenance. This prevents a hard cognitive shift immediately after the unlock moment.
4. *(Not implemented in UI yet.)* On the next eligible calendar day (`today > syllablesUnlockedAt`), if `readingPracticePaused == false`, `GameView` is designed to show a non-scored syllable onboarding overlay before the first round (`M + A → MA`; audio via `AudioService.playSyllable` once `cz_syl_*.m4a` assets ship).
5. The first real answer after the overlay calls `commitSessionStartIfNeeded`; merely viewing the overlay does not update streaks or focus-day counters.
6. A 12-round syllable calibration follows (`GameState` ends the session after 12 `syllableCalibration` rounds via `completeSyllableCalibration`), using short CV slabiky only and no length contrasts. Completing calibration sets both `hasCompletedSyllableOnboarding = true` and `hasCompletedSyllableCalibration = true`; dismissing only the overlay does not persist onboarding completion, so the overlay can reappear if the child exits before calibration completes.

If the parent enables `readingPracticePaused` before that next session, the profile stays in letter-only practice. Resuming later continues the onboarding/calibration path until calibration completes.

Current daily-session routing in production:

```
letters (primaryLayer = .letters; reading unlock fields cleared each session start)
numbers (primaryLayer = .numbers via buildNumberSessionPlan when the home layer is Numbers)
```

`GameState` already implements `syllableCalibration`, `syllableRecognition`, `syllableBlending`, `wordReading`, and `wordBuilding` when a `SessionPlan` supplies `primaryLayer` / `activityKind` (see model tests), but **`ProfileManager` does not schedule them** in the shipping planner: `isSyllableLayerEligible` is unused, there is no "every fifth round" blending scheduler, and word onboarding/calibration flags remain persisted placeholders until reading is re-enabled.

### Syllable contrast policy

Slabiky do not use the letter-only `ConfusionPolicy`, but they **do** need a structural contrast policy. `SyllableCurriculum` must expose each CV unit's consonant, vowel, vowel length, and short-base key so distractors can be selected by dimension instead of by random shuffle.

| Stage | Distractor rule | Example for `MA` |
|---|---|---|
| Onboarding / calibration | Short CV only. Prefer same vowel, different consonant. No long-vowel pairs. | `LA`, `SA`, `PA` |
| Focus day 1 | All distractors differ by consonant and share the same short vowel. | `LA`, `SA`, `TA` |
| Focus day 2 | Mostly consonant contrasts, plus one short-vowel contrast when available. | `LA`, `SA`, `ME` |
| Focus day 3+ | Include exactly one length contrast when both the short and long forms are eligible; fill the rest from consonant/vowel contrasts. | `MÁ`, `LA`, `ME` |
| Review / maintenance | Mix consonant, vowel, and length contrasts based on weakest recent confusion dimension; never use an all-random eligible pool. | `MÁ`, `PA`, `MO` |
| Rescue or eased `LiveDifficulty` | Fall back to consonant-only short CV distractors; remove length contrasts. | `LA`, `SA`, `TA` |

Length contrasts (`MA` vs `MÁ`) are pedagogically important in Czech and should appear deliberately, not accidentally. A long-vowel syllable may become a target only after its short base is known, and a length-pair distractor should not be introduced before the child has heard both forms as targets or onboarding examples.

`UnitProgressStat.confusedWith` records the concrete selected unit. The dashboard can derive the confusion dimension (`consonant`, `vowel`, `length`) from `SyllableCurriculum` when explaining patterns to parents.

### Distractor selection (`DistractorTier` + `pickFiltered`)

Sparse known-letter pools are a real problem early on (a brand-new profile may have 1 known letter after calibration). Letter distractors are chosen in [`AdaptiveGameState.pickFiltered`](Pismenka/Models/GameState.swift), which walks a private `DistractorTier` enum in priority order:

```
known (caller-preferred, then remaining known)
→ parent-marked-known-but-unverified (at most one letter, still tagged as `.known`)
→ caseVariant (automatic upper/lower mixing when policy allows)
→ attempted
→ calibrationPool
→ otherIntroduced
→ visualOnly (only when policy is `.intentionallyPractice`)
→ unintroduced
```

Within the `.known` tier, pools are built from `profile.knownLetters` minus `parentMarkedKnownButUnverified`. `pickEasyDistractors` tries `fluentKnownLetters` first, then top-confidence known letters, before the tier walk fills any remainder. `fluentKnown` / `strongKnown` are evidence tiers in `ProfileLearningSnapshot`, not separate `DistractorTier` cases.

Higher tiers are exhausted before lower ones are touched. Parent-marked but system-unverified letters do not satisfy hard-role proof. `caseVariant` is used for automatic high-band uppercase/lowercase mixing. `visualOnly` contains non-letter lookalikes (`1`, `rn`) that can appear only under `.intentionallyPractice` when the target has fluent evidence; visual-only tokens never create target stats or exposure stats.

While `liveDifficulty == .easierUntilStreak`, `pickFiltered` walks only the **known** tiers (`knownOnlyWalkOrder`) — no attempted/calibration/unintroduced fallback walk until the governor recovers.

Reaching the bottom tier means an unintroduced letter was about to be exposed — the app **counts the leak** (`unintroducedExposuresThisSession`) so it's auditable, but the round still completes (we'd rather show a never-seen letter than crash). In practice this only happens in pathological sparse cases. Intentional cameo letters are injected after `pickFiltered` and do not consume this leak counter.

### Cameo letters

Cameo letters are intentional, low-stakes future-letter appearances. They make letter review feel fresher without changing the learning contract:

- A cameo can only replace one existing ordinary distractor slot; it never increases the band/eased 4/6/8 option count.
- A cameo is never the prompted target and never replaces the active focus distractor in drill rounds.
- A cameo records only distractor exposure (`distractorExposures` / `lastSeenAt`), not `targetAttempts`, `targetCorrect`, mastery, or `introducedLetters`.
- The daily budget is capped per profile/local day by `Profile.dailyCameoExposureLimit` (currently 3), using `cameoExposureDay` and `cameoExposuresToday`. Same-day **Play again** keeps using the same budget.
- The budget is spent only when the child answers and the exposure is actually recorded through `ProfileManager.recordCameoExposure(...)`; building a round and exiting does not consume a cameo.
- If a future letter from the child's typed name is otherwise eligible, it is preferred as the cameo so the app creates a gentle print/name connection without making name letters count as mastered.

Eligibility is deliberately conservative. Cameos require at least `max(optionsPerRound, 5)` known letters so the grid still has enough real distractors after replacing one slot. They are available in letter review/maintenance and in focus drill rounds where the target is already known, the focus is shown as a distractor, and `helloFocus` has already been earned. On `plainReview`, cameos run only when there is no active letter drill focus (`activeDrillFocus == nil`), which includes weekly review/test days once drill phase ends. They are disabled for warm-up, rescue, remediation, syllables, words, and eased `LiveDifficulty`.

Candidate letters come from `LetterDifficulty.introductionOrder(for:)`, but are filtered to future target letters only: not formally introduced, not known, not visual-only (`1`, `rn`), not visually confusable with the current target or focus, and not a Czech diacritic unless its base letter is already known. Among eligible candidates, the game prefers the one with the fewest prior distractor exposures so cameos rotate instead of repeating the same future letter.

This preserves three distinct concepts for maintainers:

- **Formal introduction** — a unit was assigned as focus or target; grows `introducedLetters` / `introducedSyllables` / `introducedWords`.
- **Intentional cameo** — a future letter appeared as a distractor under the daily cap; grows only exposure counters and cameo budget.
- **Accidental leak** — the fallback distractor tier had to use an unintroduced letter; increments `unintroducedExposuresThisSession` for auditing.

### Visually confusing pairs (`ConfusionPolicy`)

`LetterDifficulty.visuallyConfusingPairs` defines symmetric letter-to-letter pairs like B/D, M/W, P/Q, lowercase b/d, structural pairs such as E/F or P/R/B, and Czech base/diacritic contrasts such as C/Č, R/Ř, and E/É. Directional non-letter lookalikes live separately in `visualOnlyDistractorsByTarget`: for example, `1` can be a distractor for `I` / `L`, and `rn` can be a distractor for `m`, but those tokens can never become targets themselves. Base/diacritic edges are used for distractor gating without making base letters depend on future diacritic mastery; diacritics still use `diacriticBase` for the base-before-mark prerequisite.

The treatment is **phase- and band-dependent** via `LetterDifficulty.ConfusionPolicy` plus the frozen `instructionalBand.confusionStage`:

| Policy | When | What it does |
|---|---|---|
| `.avoid` | In-session warm-up; rescue; focus drill days 1–2; easy scaffolding slots on later focus days; eased `LiveDifficulty` | Never picks a confusable distractor for the given target. Initial profile calibration is a separate flow (`CalibrationView`), not this enum. |
| `.allowFluentPairs` | Focus drill **day 3+** (`focusActiveDays >= 3`) **and** instructional band ≥ `.safeKnownPairs` (not `.gentle`/novice) | Confusables OK only when **both** the target **and** the candidate are in `fluentKnownLetters`. Parent `.markedKnown` overrides do not satisfy this tier by themselves, and fallback filling keeps this legality filter. |
| `.intentionallyPractice` | Advanced+ instructional-band review of a fluent-known letter | Same fluent-known legality as `.allowFluentPairs`, but eligible confusables are pulled to the **front** of each tier's pool — explicit discrimination training (B/D, M/W, mixed-case pairs, etc.). |

Similar-shape reservation is probabilistic, not hard-coded into every round: advanced instructional-band review attempts to seed one similar option about 80% of eligible rounds inside `pickFiltered`, preserving round-to-round variety. Separately, ~1 in 5 eligible plain/maintenance sessions builds a dedicated **contrast** round (`shouldBuildContrastRound`) that forces a confusable pair under `.intentionallyPractice`.

This lets the app shield struggling kids early and deliberately train discrimination later, without two parallel game modes. The `instructionalBand` gate dominates history: even if a profile has `confusedWith` evidence, those pairs are not surfaced until the frozen session band allows them. Even on focus day 3+, a **novice** `instructionalBand` (`.gentle` confusion stage) keeps `.avoid` via `levelAdjustedPolicy`.

### Round generation & answer-position fairness

Letter rounds show a session-frozen baseline `letterOptionsPerRound` (4 by default; 6/8 after pool-safety **and** grid-performance promotion), then may narrow per target via `resolvedLetterOptionCount`. That baseline is persisted as `Profile.lastFrozenLetterOptionsPerRound` so the next session can apply demotion hysteresis (known + strong within 2 of the promotion thresholds, plus `supportsMaintenance`) instead of flickering after one slipped letter. Reading-layer sessions intentionally stay at 4 choices because the early slabika/word curricula and unlock gates are built around a 1+3 option shape. When `LiveDifficulty == .easierUntilStreak`, each `governorEaseSteps` value downshifts the displayed grid by **2 options** (max 2 steps: 8→6→4), floored at 4; rescue rounds follow the same eased count. Naive shuffling produces patterns toddlers exploit (correct answer always top-left, etc.). `AdaptiveGameState.placeAnswer(target:distractors:isFocusTarget:)` enforces:

- **No more than two correct answers in the same slot consecutively.** `recentCorrectPositions` keeps the last two positions and forbids a third repeat in that slot.
- **Even distribution across the session.** `sessionCorrectPositionCounts: [Int]` — preference rotates toward the least-used slot when ties allow.
- **Focus target slot rotates.** `recentFocusCorrectPositions: [Int]` ensures a brand-new focus unit doesn't get parked in the same slot every drill round, which would let the child memorize position instead of symbol shape.

`sessionCorrectPositionCounts` resizes with the current activity's option count, so a live-difficulty downshift or a narrower clamped round can change the grid without corrupting position history. Number rounds go through the same `placeAnswer` fairness rules with their own frozen `numberOptionsPerRound` baseline. Both the frozen grid sizes and the frozen bands (`instructionalBand` / `numberBand`) are set at session start, so level/evidence changes during a session do not silently resize the grid or unlock harder distractor behavior.

Progress-check sessions are intentionally routed through `plainReview`, even for Expert profiles, so the adaptive audit stays separate from ordinary Expert `maintenance`. The detailed evidence-ordering and conservative distractor rules live in [Six-session retention progress check](#six-session-retention-progress-check).

### Single source of truth: `ProfileLearningSnapshot`

`Profile.snapshot` is the single read model for "what does this child know right now?" The game, profile cards, end screen, focus picker preview, and dashboard all read the same derived state:

- `knownLetters` — override-aware, focus-exception-aware pool used for warm-up and distractors.
- `strongKnownLetters` — evidence-only strong tier used for accuracy confidence and curriculum gates; parent `.markedKnown` does not auto-promote into it, and `.reset` excludes a letter from it.
- `fluentKnownLetters` — strong-known plus quick, stable response time; used for the hardest distractor roles.
- `parentMarkedKnownButUnverified` — parent-known letters without strong system evidence; used cautiously, never as confusable/scaffolding proof.
- `currentlyMasteredLetters` — live strict-mastery signal (`isFocusGraduated` right now), used for dashboard category labels.
- `everMasteredLetters` — lifetime trophy set, used for alphabet-level math and session-end progress.
- `knownSyllables`, `currentlyMasteredSyllables`, `everMasteredSyllables` — reading-layer equivalents.
- `knownWords`, `currentlyMasteredWords`, `everMasteredWords` — word-layer equivalents.
- `alphabetLevel`, `readingStage` — separate computed progress tracks; the alphabet track (and, via `numberInstructionalBand`, the numbers band) is surfaced in the current UI while `readingStage` stays dormant.
- `learningLetters`, `unseenLetters`, `recentlySlipped` — dashboard and picker support pools.
- `unseenSyllables`, `unseenWords` — curriculum-derived unseen pools.
- `lettersByConfidence` — Wilson-only certainty ordering for parent display and easy distractors. No response-time discount: slow correct answers are still correct, and the right place to reward fluency is the additive `isFluentKnown` tier, not a subtractive penalty here.
- `lettersByReviewPriority` — warm-up/maintenance target ordering by `LetterStat.reviewPriority`, which delegates to the FSRS-inspired `AdaptiveLearningScheduler.priority`: recall risk (predicted retrievability below the 90% retention target) + recent weakness + lapse pressure + evidence uncertainty + overdueness + explicit follow-ups. Slowness is deliberately not a term — for a distractible 3-year-old, "slow on this letter" is mostly distraction noise rather than weakness, and drilling a known-but-slow letter at the expense of an actually-weak letter wasted practice time.
- `dueReviewLetters`, `weakReviewLetters`, `auditReviewLetters` — scheduler pools: introduced letters whose personalized review date has arrived (priority-ordered), introduced-but-not-currently-known letters ordered for remediation, and a small uncertainty-first audit pool of known letters used when nothing is due.
- `instructionalBand` — engine distractor/case band derived from `strongKnownLetters ∩ everMasteredLetters`; reading mastery does not raise this letter-session band in the current code.
- `currentFocusTarget`, `nextFocusTarget` — typed focus state at the API edge, currently populated only for letters while the reading layer is dormant. The method signature still carries the future word-audio hook, but the current implementation returns a letter target or `nil` rather than synthesizing syllable/word previews.
- `nextFocusCandidate` — letter-only preview retained for existing consumers; it is populated from the same prerequisite-aware letter picker used for focus selection.
- `knownNumbers`, `strongKnownNumbers`, `currentlyMasteredNumbers`, `everMasteredNumbers`, `learningNumbers`, `unseenNumbers`, `recentlySlippedNumbers` — the numbers-layer equivalents of the letter pools, derived from `numberStats` with the same override-aware / focus-exception rules.
- `numberInstructionalBand`, `highestNumberBandEver`, `totalNumbersInCurriculum` — the numbers band for the next session (never derived from `AlphabetLevel`), its monotonic trophy, and the 0–100 curriculum size. `parentNumberKnowledgeSummary(pool:)` is the numbers twin of the parent letter rollup, computed over a caller-supplied pool (the dashboards pass `numberKnowledgePool`, the introduced/practiced set — never all 101).

The `instructionalBand` is computed from `strongKnownLetters ∩ everMasteredLetters`, floored at `.novice`. It is never stored on `Profile`; `AdaptiveGameState.init` freezes the snapshot value for the session and persists that frozen value in `GameEngineSnapshot` so a restored checkpoint keeps the same distractor/case band it started with. The separate base answer-grid size is `Profile.letterOptionsPerRound`; it is frozen into the game state, saved to `GameEngineSnapshot.letterOptionsPerRound`, and recorded back to `Profile.lastFrozenLetterOptionsPerRound` for the next session's hysteresis.

This prevents mismatches like "the dashboard says A is mastered but the game keeps drilling A."

### Hearts (5)

Every non-impulsive wrong answer consumes one heart. The impulsive-tap threshold is adaptive: the **median of all pooled `recentResponseTimes` samples across the profile's letter stats** (not correct-only), multiplied by **0.35**, clamped between **0.35s** and **0.9s**, with **0.5s** as the fallback when fewer than four timing samples exist. (The pooling reads `letterStats` even during numbers sessions — number timing samples accumulate in `numberStats` but do not feed this threshold today, so a numbers-only profile uses the 0.5s fallback.) These constants are heuristic tuning values from product judgment, not measurements from real children; they should be treated as provisional until validated. A tap faster than that after the grid appears is classified as `MistakeType.impulsiveTap` by `AdaptiveGameState`: it is logged and visible, but it does not count as a true learning miss and does not cost a heart. Assisted mastery-discounted attempts are the exception to the impulse shortcut: rescue/revealed wrong answers are persisted as `.confusion` even if fast, remain discounted from mastery via `AttemptContext`, and still cost a heart / feed `LiveDifficulty` like a real miss. This is intentional: once the child is in a helper path, repeated wrong taps are treated as struggle, not accidental exploration.

Hearts pace one sitting; daily-goal persistence is defined in [Daily goal, Winner button, and progress strip](#daily-goal-winner-button-and-progress-strip).

### Attempt contexts & assisted discount

`RoundEvent.AttemptContext` explains whether a tap was independent practice or happened inside a helper path:

| Context | Source | Counts for mastery? | Wrong-answer routing |
|---|---|---|---|
| `.independent` | Ordinary round | Yes | `recordConfusion` / heart loss |
| `.immediateRescue` | Easy retry scheduled after **one intervening** round (`dueAfterRounds: 1`) | No | `recordConfusion`, heart loss, affects `LiveDifficulty` / rescue flow |
| `.delayedRescue` | Mid-difficulty retry 2–3 rounds later | No | `recordConfusion`, heart loss, affects `LiveDifficulty` / rescue flow |
| `.revealed` | Second-miss reveal/highlight path | No | `recordConfusion`, heart loss, affects `LiveDifficulty` / rescue flow |
| `.extraPractice` | Parent-directed practice | Yes | Normal answer semantics |

`AttemptContext.isAssistedForMastery` is true for `.immediateRescue`, `.delayedRescue`, and `.revealed`. Those attempts still create a `RoundEvent` and update exposure/replay/diagnostic fields, but they do not append fresh `recentResults` or increment `targetAttempts`; the original independent miss already recorded the mastery evidence. If a delayed rescue is also revealed, `.revealed` wins because the highlight made the attempt assisted.

`RoundEvent.wasDiscounted` is true whenever learning stats were discounted, whether the reason was an impulsive tap or assisted practice. Parent explanations distinguish those cases: impulse copy says it was an impulsive tap; assisted copy says the child was helped after a miss and the attempt was not counted as independent practice.

Weekly assessment evidence uses an even narrower gate than the visible daily bar: the attempt must be a `.weeklyAssessment` target round from adaptive daily play with `AttemptContext == .independent` and `shouldCountForLearning` true (not impulse-discounted and not assisted rescue/reveal). That means the review/test progress strip can advance on helper-path or filler rounds, but `WeeklyAssessmentLetterResult.independentAttempts` advances only on unassisted recognition during true audit rounds.

### Day streak (clock-tolerant)

Streak math runs on `LocalDay` (year/month/day, not `Date`) so time-zone travel and DST don't cause weirdness. The signed delta between today and `lastSessionDay` drives the branch:

| Delta | Action |
|---|---|
| `0` | Same calendar day. **No streak change.** (Multi-session same-day.) |
| `1` | Played yesterday. Streak +1. |
| `≥ 2` | Genuine gap. Streak resets to 1. |
| `< 0` | Device clock moved backward (time-zone travel, manual change, restored backup). **Streak preserved**, all day-keyed mutations skipped for this session. |

The backward-clock branch deliberately doesn't update `lastSessionDay`, `focusPracticedDays`, or `lastNewLetterDay`, so a rolled-back clock can't be used as a loophole for extra same-day formal introductions.

`bestDailyStreak` is a lifetime trophy — never decreases, never reset by `resetAllProgress`. Streak messaging is celebratory only ("Day 5 in a row!", "Best streak: 8 days!"). There is no "don't lose your streak" copy.

### "Today's sticker card" stamps

Three opener stamps plus session-specific follow-up stamps. `AdaptiveGameState` decides at `init` which opener applies and which non-opener slots are achievable. `SessionEndView` displays the same `applicableStamps` set.

| Stamp | Earned when |
|---|---|
| `warmupStar` *(opener)* | Normal letter session: warm-up phase completed with ≥ 80% correct. |
| `braveStart` *(opener)* | Sparse profile or syllable calibration: first correct answer in a no-warm-up session. |
| `reviewStar` *(opener)* | No-focus, Expert maintenance, or weekly review/test session: 5 correct review rounds. |
| `helloFocus` | First target round for today's focus unit, **whether the child got it right or wrong**. In letter drill sessions, the focus is forced to appear as the target by round `warmupLength + 2` if it hasn't shown up naturally; syllable/word focus recognition rounds target the active focus directly. |
| `practicePro` | Focus session: weighted `practiceProgress ≥ 5.0`. Correct focus target = `+1.0`; correctly avoiding focus as a distractor = `+0.5`. No-focus / weekly review/test session: 10 total correct rounds. |
| `streakStar` | Any 5-correct streak within the session. |

`helloFocus` replaces the older letter-centric `helloLetter` name. Stamps are session-local, so no persisted migration is needed. End-screen copy now frames these as stickers/encouragement, not as a second hidden daily goal. The visible daily goal is the bottom progress strip; the sticker card is a light celebration layer on top.

`reviewStar` opener sessions drop only the `helloFocus` slot. They still include `practicePro` (awarded after 10 correct review answers) and `streakStar`.

### Multi-session same-day contract

The contract is documented inline on `ProfileManager.buildSessionPlan` (`previewSessionPlan` vs `commit: true`). `GameView` calls `commitSessionStartIfNeeded` on the **first answer**, so streak, focus-day, spotlight introduction, and `dailyPracticeDay` bookkeeping do not run when the session screen merely opens. There is no public `startSessionIfNeeded` API.

| Concern | Behavior across same-day sessions |
|---|---|
| Target attempts | **Count, every session** (`recordAnswer` is session-agnostic) |
| Distractor exposures | **Count, every session** |
| Cameo exposures | **Count only up to the daily cameo cap** (`cameoExposuresToday`; same-day replay does not reset it) |
| Focus graduation | **Can happen, any session** |
| Reading unlock | **May be stamped mid-session** on Czech alphabet completion (`syllablesUnlockedAt`), but `buildSessionPlan` clears reading unlock/focus fields each session start and only schedules letters today; onboarding/calibration would start no earlier than the next eligible calendar day if reading were re-enabled |
| Daily spotlight / new focus unit | **At most one formal introduction per calendar day** (graduation also consumes the day's quota); spotlight introduction does not wipe an unrelated durable focus |
| Daily goal count | **Persists across same-day sessions** through `dailyPracticeDay` / `dailyPracticeAttempts` | **Introduction days:** only **correct** adaptive-daily **target** rounds advance it. **Review/test days:** every answered **target** round advances it (correct or incorrect) while `activeWeeklyAssessment` is set. |
| Per-letter target asks | **Accumulate across same-day sessions** through `dailyTargetAskDay` / `dailyTargetAskCounts`; each new sitting seeds `AdaptiveGameState.sessionTargetCounts` from them (merged per-letter-max with any restored checkpoint), so the introduction-day 10-ask cap holds per calendar day |
| Weekly assessment | **Persists across same-day review/test sessions** through `activeWeeklyAssessment`; a naturally completed assessment remains active until the next local day, while a parent-skipped assessment is archived immediately and clears the way for a same-day introduction session |
| Day streak | **Unchanged** on same-day re-entry |
| `focusActiveDays` | **Unchanged** — `Set<LocalDay>` insertion is idempotent |
| Stamps | **Session-local** — fresh card per `GameView` lifetime |
| Parent dashboard | **Updates live** as rounds happen |

Net effect: a child can play 1 / 3 / 10 sessions on a single day, keep accruing real attempts, may graduate the active focus, but won't inflate the day streak, won't earn extra "active days" on the scaffolding ladder, won't be served a second formal spotlight/focus introduction beyond the day's quota, and won't get unlimited cameo letters through repeated same-day sessions.

Numbers sessions follow the same contract through their twin fields (`numberDailyPractice*`, `numberDailyTargetAsk*`, `lastNewNumberDay`, `numberFocusPracticedDays`, `activeWeeklyNumberAssessment`), and because the day streak is shared, mixing letters and numbers sessions on one day still counts as a single "played today."

### Adaptive struggle response

Mistakes no longer end adaptive daily or weekly review/test sessions by themselves. The child keeps playing until they tap Winner, leave with Home, or lose all hearts. Older checkpoints that contain the legacy `tiredSignal` value are ignored on restore when hearts remain, so a stale saved session cannot immediately jump to the summary screen.

Struggle still adapts the next rounds. The session difficulty governor trips when the child gets 3 of the last 4 wrong, drops to 2 hearts or fewer, or shows low focus accuracy after the session is underway. While eased, the app avoids confusing distractors, halves focus-target pressure, downshifts the displayed grid by 2 options per governor step (max 2 steps), restricts `pickFiltered` to known tiers only, and drains rescue retries sooner. Recovery requires **≥4 correct in the last 5 independent rounds** (with the eased `optionCount` matching the current step), then walks the governor back one tier at a time until normal difficulty is restored; a short cooldown then prevents sticky latch re-trips.

A trip (or a deepening of an existing ease while already eased) only ever fires on a **wrong** answer — a correct answer never makes the grid harder. This matters because `heartsLow` (hearts only fall within a session) and `focusAccuracyLow` (a slow cumulative average) are sticky latches: without the wrong-answer guard, the round right after a streak recovery would re-trip purely from the stale latch and the option grid would flicker back down (e.g. 6 → 4) even on a correct answer. The next genuine miss re-trips if the child is still struggling.

### Adaptive signals & feedback loops

The app records both aggregate learning stats and a local rolling round narrative.

`LetterStat` and reading `UnitProgressStat` track:

- `targetAttempts`, `targetCorrect`, `distractorExposures`, `lastSeenAt`, `lastTestedAt`
- `confusedWith` for real confusions and `impulsiveSelections` for instant taps
- `promptReplayCount`, `recentResponseTimes`, `medianResponseTime`, `responseTimeBucket`. Response-time recording uses an **asymmetric speed rule** — see [Asymmetric speed rule](#asymmetric-speed-rule) below.
- `wasKnownBefore` and `demotedAt` for recently slipped letters
- `reviewPriority` for stale/weak review ordering. `LetterStat` delegates to the FSRS-inspired `AdaptiveLearningScheduler.priority` (recall risk + weakness + lapse pressure + uncertainty + overdueness + follow-ups); dormant reading `UnitProgressStat` still uses the simpler `0.7*weakness + 0.3*staleness`. Neither uses a slowness term.
- `EvidenceStrength` (`notEnoughData`, `emerging`, `solid`, `strong`) so the parent dashboard does not overtrust 1/1 = 100%

#### Asymmetric speed rule

A 3-year-old's response time is asymmetric evidence: a single slow tap could be distraction (kid looked away, parent talked nearby, set the phone down) rather than slow recall, while sustained fast responses earn the separate `isFluentKnown` tier. We treat it that way:

- `recordTargetAttempt` drops any response time at or above `LetterStat.distractionResponseCutoff` (5.0 s) from the rolling response-time window. The accuracy signal still updates — the answer they eventually gave still counts toward `recentResults`, `targetAttempts`, and `targetCorrect` — but the time itself is treated as noise and never enters the median.
- `certaintyScore` is now pure Wilson 95% lower bound. A slow correct answer never demotes certainty below an identical-accuracy fast answer. This brings `LetterStat` in line with `UnitProgressStat`, which always computed pure Wilson.
- `confidenceScore` (game-side strength ordering and certainty tiebreaker) is pure recent/lifetime accuracy blend, no speed multiplier.
- `reviewPriority` no longer includes the slowness term (was 0.2 weight).
- Speed only ever earns a *positive* upgrade via `isFluentKnown` (strong-known plus ≥ 4 samples with fast median). That tier still gates the hardest distractor roles, mixed-case work, and visual-only traps — the places where genuinely automatic recognition matters.

The net effect: a distractible child who knows their letters is no longer silently penalized for the natural attention drift of their age, and the parent-facing "Confidently known" headline no longer fluctuates because of toddler latency noise. The previous design discovered the problem the hard way: a child at 91% lifetime accuracy across 779 attempts showed only 11/41 letters as confidently known, primarily because slow-but-correct answers were being treated as evidence-against rather than evidence-for.

`WeeklyLetterAssessment` is a separate persisted diagnostic snapshot for the six-session retention progress check. It deliberately does not try to infer retention later from aggregate `LetterStat`, because aggregate stats mix calibration, ordinary drill, rescue, cameos, and historical attempts. The assessment stores:

- `scheduledFor` — the local day the check was planned for (normally the same day the child starts it after six completed 25-answer sessions).
- `startedOn` — the local day the child actually started it (usually the same as `scheduledFor`).
- `cohortLetters` — the frozen ordered audit set.
- `strategy`, `assessmentRoundTarget`, `dailyGoalTarget`, `hardRoundCap` — legacy-vs-adaptive shape and frozen progress/cap numbers.
- `results` — one `WeeklyAssessmentLetterResult` per audit letter, each with bucket, planned attempts, extension allowance, independent attempts, independent correct count, and response-time samples.
- `completedOn` — set when the adaptive audit resolves, when the independent-evidence hard cap is reached after every planned letter has at least one independent attempt, or when a parent explicitly skips the unfinished test and archives the partial result.

The outcome helper reports `.pending`, `.retained`, `.watch`, `.observed`, or `.needsReview` according to the frozen bucket. Legacy decoded assessments default to the previous 4-attempt, 3-correct rule, so in-flight old tests remain readable and finish under their original contract.

`RoundEvent` keeps the last 200 local-only events per profile — one shared log across layers. Each event stores target, displayed options, selected answer, correctness, response time, phase, `RoundIntent`, optional `unitKind`, optional `activityKind`, mistake type, replay count, discount status, optional `AttemptContext`, optional `cameoLetter`, `includedFocusAsDistractor`, optional `RoundPlanReason`, hearts after the answer, `LiveDifficulty`, and rescue metadata. Numbers rounds write `unitKind: .number` (with `number:`-prefixed storage keys); the numbers dashboard filters the shared log by that kind, while the letters dashboard's raw-history card is currently unfiltered. There is deliberately no `RoundIntent.cameoExposure`: intent remains the primary pedagogical purpose, while cameo and focus-as-distractor are orthogonal flags so a single round can carry both signals.

`RoundIntent.weeklyAssessment` marks adaptive audit evidence rounds. `RoundPlanReason` is the machine-readable debug payload for generated rounds: primary goal, target source, distractor policy, and expected difficulty. It is not parent copy; it exists so tests and future simulation tooling can assert why the adaptive engine made a round. Weekly assessment rounds use `RoundPrimaryGoal.weeklyAssessment`; audit targets use `RoundTargetSource.weeklyAssessmentCohort`.

Parent rows derive plural `parentExplanations` from that data in priority order: discount/impulse explanations first, then cameo/focus exposure notes, then fallback round-purpose notes such as contrast-pair, stale-review, or weekly-assessment evidence. That order lets a single round honestly say both "helped after a miss; not counted as independent practice" and "M appeared as a preview", while keeping parent-trust-critical discount copy first. Legacy events with `intent == .focusDistractorExposure` still produce the focus-distractor note even when the newer boolean field is absent.

For letter sessions, `FocusTeachingMode` is the game-side strategy switch for durable focus/remediation:

- `scaffolded` — early focus days, max easy-elimination help.
- `normal` — standard scaffolding fade.
- `remediation` — stuck focus (`focusActiveDays >= 5` and recent accuracy < 50%): max scaffolding (`3`, deliberately not `0`), lower focus-target pressure, and pre-seeded rescue retries. Clears when recent accuracy reaches 60%. If the same focus reaches `focusActiveDays >= 8` and is still below 50%, the focus is paused in `pausedFocusLetters`, the daily new-focus quota is consumed, and the picker moves to easier review/prerequisites on a later session.
- `contrast` — explicit confused-pair discrimination round.
- `maintenance` — expert no-focus mixed review.

Paused focus letters are skipped for 7 local days via `pausedFocusLetterDays`, or until a parent reset/override reopens that letter. After the cooldown, the letter can re-enter the picker if its prerequisites and recent confusion signals make it a safe candidate again.

Repetition is intentionally tuned down compared with the older focus-heavy loop. Focus-target chance is lower in scaffolded/normal modes, recent target letters are remembered so the same symbol is less likely to appear immediately again, needs-work targets are weighted-sampled rather than always taking the top-scored letter, no letter may be the target more than 10 times per local day on introduction days (persisted across sittings), and ordinary rescue retries are spaced by at least one round when possible. Daily spotlight adds visible variety, while the six-session progress check gives a structured retention checkpoint without clearing durable remediation pressure.

Audio feedback also participates in the model. Replaying the prompt increments `promptReplayCount`. Tap replays the current target prompt at normal speed. On progress-check (`.reviewTest`) days, a two-second long-press on the replay button opens the parent gate so a parent can skip/end the active progress check early (same archive semantics as **Skip current progress check** in the dashboard). `AudioService.playLetterSlow(..., rate: 0.7)` exists for future tuning but is not wired in the current UI. On a second miss of the same letter in one session, the correct tile enters a reveal state, pulses, and replays the target prompt before the next round.

---

## Parent controls

### Case practice

The settings screen labels lowercase behavior as **Case practice**. The default option is **Automatic at high levels** (`LowercaseMode.uppercaseOnly`): uppercase-first introduction until the parent picks a non-default mode or the profile reaches bands that mix case automatically.

**Runtime (code truth):**

- Focus **introduction order** uses the persisted `lowercaseMode` only when `instructionalBand.allowsAutomaticLowercaseTargets` is **false**. At **Expert+**, `ProfileManager.pickNextDailyIntroductionLetter` **overrides** the picker to `.afterUppercaseMastery` regardless of the setting.
- `LetterDifficulty.introductionOrder` treats any mode **other than** `uppercaseOnly` the same: after all uppercase letters are in `everMasteredLetters`, lowercase keys are appended. There is **no separate behavior** for **Mixed case after both** yet — `mixedAfterBothStable` exists only in settings UI/persistence.
- Lowercase **distractors** during play come from `InstructionalBand.allowsAutomaticLowercaseDistractors` (Advanced+), not from the Case practice picker.

The picker still exposes **Lowercase after uppercase** and **Mixed case after both** for compatibility and future tuning; subtitles in `LowercaseMode.settingsSubtitle` explain intent.

### Parent gate

`ParentGateView` requires a parent gesture before sensitive entry points. The default is a swipe-up drag; settings can switch the gate to an accessible hold-two-buttons method. It guards:

- Creating new profiles (`ProfileSelectView` **+**)
- Opening the parent dashboard (**View results** on a held profile card)
- Opening profile edit (**Edit profile** on a held profile card)
- Opening **Settings** from the profile-select gear icon
- Skipping an unfinished progress check **from inside the game** (two-second long-press on the replay button during a `.reviewTest` session → gate → `skipActiveWeeklyAssessment`, then `commitSessionStartIfNeeded`, `endSession`, checkpoint clear, and immediate `startGame` — no `SessionEndView`)

Profile-card parent actions use iOS `.contextMenu` (long-press → **View results** / **Edit profile**); the gate runs after the menu choice, not on hold alone.

**Not** re-gated behind `ParentGateView` once you are already in the parent dashboard: **Sound settings**, granular resets, progress-check skip (confirmation alert only), backup/export, and per-letter actions. Those assume the adult already passed the gate to reach `ParentDashboardView`.

Reset/delete profile and full progress reset live in `EditProfileView`, reachable only after the edit-profile gate on the profile card.

The gate is intended to be hard for a toddler to discover but trivial for an adult.

### Personalized letters

`SettingsView` includes a **Personalized letters** row in the Play settings. When off, the app uses the standard Czech example prompts. Turning it on opens a parent-facing unlock sheet before `settings.personalizedCzechLettersEnabled` is set and `AudioService.setPersonalizedCzechLettersEnabled(true)` is called; turning it off immediately clears both the persisted setting and the audio-service runtime flag.

The unlock sheet is deliberately explicit that the family code is **4 digits**:

- Copy says "Enter the 4-digit family code..." and a small "4 digits" chip sits below the entry row.
- The code UI is four separate rounded digit boxes, backed by one hidden `TextField` so paste/autofill and deletion still behave like a normal field.
- Input is filtered to numbers and capped at four digits. The Unlock button is disabled until all four digits are entered.
- The hidden field is focused on sheet appearance via `@FocusState`, so the iOS number keyboard pops automatically without requiring an extra tap.
- The active digit box gets a sky accent and slight scale lift; invalid attempts turn the boxes/chip toward the berry error color and keep keyboard focus for quick retry.

### Per-letter overrides

`LetterStat.parentOverride: LetterOverride?` lets a parent express *"I know my kid; treat this letter as known (or as fresh) regardless of what the attempt history says"* without polluting the child's actual performance data. Two cases:

- **`.markedKnown(date:)`** — `effectiveIsKnown` returns `true`. The letter is included in `Profile.knownLetters` immediately (bypassing the focus-graduation exception), so it can appear in warm-up and ordinary known-letter distractor pools. Until the child verifies it in-app, it also appears in `parentMarkedKnownButUnverified`, which keeps it out of confusable-pair proof, first-choice scaffolding evidence, and other hard roles. It does **not** enter `strongKnownLetters` or `fluentKnownLetters` unless the underlying stat independently satisfies those tiers. Underlying `recentResults` / `targetAttempts` are **unchanged**. `everMasteredLetters` is **not** updated by overrides — that set is reserved for genuine in-app graduation.
- **`.reset(date:)`** — `effectiveIsKnown` returns `false`. The letter is treated as not-yet-known for game purposes and is excluded from `strongKnownLetters` even if historical evidence was strong. Used for "let's re-teach this one" without wiping the data.

The dashboard surfaces overrides as a distinct knowledge state ("Marked known by parent" / "Reset by parent") with its own color, so parents can always see *why* a letter is in its current state.

Overrides and per-letter notes are set from each letter row's **Actions** menu (`ellipsis.circle` → confirmation dialog) in the dashboard: **Clear override**, **Mark as known**, **Reset (re-teach)**, **Extra practice**, **Add/Edit note**, **Wipe stats** (when data exists). `ProfileManager.setLetterOverride` / `updateLetterNote` do not participate in **Undo last reset** — only the five reset APIs and profile deletion snapshot the profile first.

Setting any override clears that letter from the paused-focus cooldown. If a parent marks the **current** focus as known, `setLetterOverride` also clears the focus and matching `lastFocusSelection` so the next session can pick a fresh letter without pretending the override was earned mastery.

### Granular resets

Reset operations on `ProfileManager`, smallest blast radius first. Each is documented in code with its exact preserved/cleared field set. The letters-layer resets have numbers twins:

| Operation | Wipes | Preserves |
|---|---|---|
| `resetCalibrationOnly` | `hasCompletedCalibration` flag | All letter/syllable/word stats, focus, streak, trophies |
| `resetNumberCalibrationOnly` | `hasCompletedNumberCalibration` flag | All number learning history |
| `resetCurrentFocus` | `currentFocusLetter`, `currentSyllableFocus`, `currentWordFocus`, `focusStartedDay`, `focusPracticedDays`, `lastFocusSelection` | Letter/syllable/word stats, `lastNewLetterDay`, streak |
| `resetCurrentNumberFocus` | `currentFocusNumber`, `numberFocusStartedDay`, `numberFocusPracticedDays`, `lastNumberFocusSelection` | Number stats; `lastNewNumberDay` is intentionally kept so the one-new-number-per-day rule still holds |
| `resetLetterStats(letter:)` | One letter's `LetterStat` (counters, timestamps, override); removes it from `everMasteredLetters`, `introducedLetters`, and paused-focus cooldown state; clears focus if it **was** the focus; clears `lastFocusSelection` if it described that letter | Other letters, streak, calibration, lifetime trophy fields |
| `resetNumberStats(number:)` | One number's `NumberStat`; removes it from `everMasteredNumbers`, `introducedNumbers`, and paused-focus cooldown state; clears the focus/`lastNumberFocusSelection` if they referenced that number | Other numbers, streak, calibration, band trophies |
| `resetStreak` | `dailyStreakCount`, `lastSessionDay` | `bestDailyStreak`, all learning stats, focus. The streak is shared, so this affects both layers' "Day N" banner. |
| `resetAllProgress` | **Both layers.** All learning history across letters/slabiky/words, calibration, unlock flags, focus, weekly assessment state/history, streak, mastery sets, introduced sets, paused-focus state, focus-selection reason, raw round events, `bestSessionStreak`, daily-practice day/counters/winner flags, `dailyTargetAskDay` / `dailyTargetAskCounts`, `weeklyIntroducedLetters`, `learningCycleStartDay`, `completedLetterSessionsInCycle`, reading-layer scaffold flags, **plus every number twin field**: `numberStats`, `introducedNumbers`, `everMasteredNumbers`, `currentFocusNumber` + focus days/selection, `hasCompletedNumberCalibration`, `lastNewNumberDay`, paused focus numbers, `numberDailyPractice*` / `numberCameoExposure*` / `numberDailyTargetAsk*`, `numberLearningCycleStartDay`, `weeklyIntroducedNumbers`, `completedNumberSessionsInCycle`, `activeWeeklyNumberAssessment`, `recentWeeklyNumberAssessments`, **and** `numberGridPerformanceStats` / `lastFrozenNumberOptionsPerRound` | Avatar, name, language, and profile-level `parentNote`; lifetime trophies in both layers: `bestDailyStreak`, `highestAlphabetLevelEverReached`, `celebratedAlphabetLevels`, `highestNumberBandEverReached`, `celebratedNumberBands`. Letter-grid evidence (`lastFrozenLetterOptionsPerRound` and `gridPerformanceStats`) is historically **not** cleared — an asymmetry with the numbers side, whose grid stats **are** wiped |

`skipActiveWeeklyAssessment` is separate from the resets: it archives the in-progress **letters** progress check, clears the active cycle, and may reset daily-practice counters so a same-day introduction can run (dashboard alert, no second gate). It has no numbers twin.

`ProfileManager` stores `lastResetSnapshot` before each reset API (letters and numbers) **and** before `deleteProfile`, enabling a single **Undo last reset** step on either dashboard. Undo restores the snapshotted profile JSON (re-appending a deleted profile when under the four-profile cap) but does **not** restore cleared `SessionCheckpointStore` envelopes. Dashboard confirmations call `checkpointStore.clear(profileId:)` (the numbers dashboard clears the `.numbers` layer slot) so resume checkpoints do not disagree with wiped state.

`resetLetterStats` may lower the derived `alphabetLevel` if that letter was the only evidence holding the current tier (see `ProfileManager` comment).

UI surfacing:

- Per-letter wipe → letter row **Actions** dialog (**Wipe stats for …**), not a context menu. Per-number reset → number map tile dialog (**Reset {n} (re-teach)**) on the numbers dashboard.
- Current-focus reset → dashboard overflow menu (`Pick a new focus letter` / `Pick a new focus number`). The letters action also clears syllable/word focus in `ProfileManager`, but the current UI only shows it while a **letter** focus is active.
- Calibration resets → each dashboard's overflow menu (`Re-run calibration` / `Re-run numbers calibration`); streak reset → letters dashboard overflow menu only (`Reset day streak`).
- Full reset → `EditProfileView`'s "Reset progress" button (wipes both layers).
- `readingPracticePaused` is persisted on `Profile` for the dormant reading layer but is **not** surfaced as a toggle anywhere in the current shipping UI. If/when the reading layer reactivates, an `EditProfileView` toggle would be the intended home.

---

## Architecture & file map

```
Pismenka/
├── PismenkaApp.swift              `PismenkaApp` entry, `PismenkaAppDelegate` (Firebase bootstrap), and `ContentView` first-launch gate + four-screen state machine with checkpoint resume
├── Models/
│   ├── Profile.swift              Per-child profile (letter/number/syllable/word stats, per-layer weekly assessments, focus twins, streaks, trophies, letter+number grid stats)
│   ├── ProfileLearningSnapshot.swift  Single source of truth for derived learning state (letter pools + number pools/band, parent letter & number knowledge summaries)
│   ├── LearningUnit.swift         UnitKind, FocusTarget (incl. `.number` + `number:` storage prefix), LearningLayer, LearningActivityKind, LearningRound
│   ├── LetterStat.swift           Per-letter mastery + LetterOverride + LetterKnowledgeState (reused by numbers via the `NumberStat` typealias)
│   ├── AdaptiveLearningScheduler.swift  FSRS-inspired memory model: LetterMemoryState (difficulty, stability, retrievability, due dates), review priority, pair-level LetterConfusionEvidence, GridPerformanceStat
│   ├── UnitProgressStat.swift     Shared syllable/word mastery aggregate (dormant in current release)
│   ├── LetterSymbol.swift         Typed API-edge wrapper for base/form/language
│   ├── FocusSelectionReason.swift Persisted "why this focus?" explanation
│   ├── RoundEvent.swift           Local rolling round log + RoundIntent/MistakeType/LiveDifficulty/RoundPlanReason
│   ├── LetterDifficulty.swift     introductionOrder, diacriticBase, ConfusionPolicy, confusing pairs
│   ├── NumberDifficulty.swift     0–100 introduction order, readiness gates, digit transpose/lookalike/containment rules, number ConfusionPolicy + distractor picker, calibration pool (incl. unwired age seed)
│   ├── NumberInstructionalBand.swift  Numbers band (Beginner→Fluent), confusion-stage mapping, `numberOptionsPerRound` grid gates; `NumberStat` / `WeeklyNumberAssessment` typealiases
│   ├── SyllableCurriculum.swift   Czech CV slabika DAG + syllable distractors (dormant)
│   ├── WordCurriculum.swift       Czech seed words + playable word-pool gates (dormant)
│   ├── CurriculumAudioAvailability.swift  Model-layer protocol for audio-backed curriculum gating
│   ├── SkillLevel.swift           AlphabetLevel + ReadingStage (reading stages dormant), Comparable, trophy support, `letterOptionsPerRound` pool-safety + grid-performance gates
│   ├── LocalDay.swift             Calendar-day value type (year/month/day, daysSince, today(); `nextSunday` exists but is unused by the live six-session planner)
│   ├── GameState.swift            `SessionPlan`, `AdaptiveGameState` — phases, typed rounds (letter + number builders), daily goals, progress-check targeting, spotlight drill, hearts, stamps, distractors, position fairness, governor, frozen letter/number bands and grids
│   ├── AppSettings.swift          Audio, comfort, reminders, case-practice, parent-gate, personalized-Czech-letters, first-launch onboarding (`hasCompletedFirstLaunchOnboarding`, `defaultGameLanguage`), and the local-only `activeLearningLayer` Letters/Numbers switch (excluded from `AppSettingsSnapshot`)
│   └── SessionCheckpoint.swift    Versioned exact-resume checkpoints
├── Services/
│   ├── ProfileManager.swift       Profile CRUD; layer-aware session lifecycle (`buildSessionPlan(layer:)` routes `.numbers` to `buildNumberSessionPlan`); per-layer six-session progress-check planners; assessment scoring; typed recordAnswer (letters + numbers); overrides; letter and number granular resets. The letters branch clears reading-unlock fields on every commit; only the reading layers are forced off.
│   ├── AudioService.swift         Bundled letter + number audio playback, SFX, hard letter/SFX missing-asset validation plus soft `missingNumberAssetNames` diagnostic, `playNumber` with spoken-word TTS fallback (`NumberSpokenForm`), optional Čermák personalized Czech letter prompts. `requiredCurriculumVoiceAssets(for:)` currently returns `[]`, so syllable/word validation is disabled in the current release.
│   ├── HapticService.swift        Haptic feedback wrapper
│   ├── SessionCheckpointStore.swift  Local resume-checkpoint persistence, one slot per learning layer (letters / numbers)
│   ├── NotificationService.swift  Parent opt-in local reminder (7:00 AM local time)
│   ├── ProfileExportService.swift Versioned JSON backup import/export
│   └── FirebaseBackupService.swift Sign in with Apple + Google + Firestore recovery mirror
├── Resources/
│   └── RoutingCoverage.geojson    Marketing/availability map; not consumed by app gameplay
├── Views/
│   ├── Profile/
│   │   ├── ProfileSelectView.swift  Profile cards with layer-aware Confident n/m, pinned Letters/Numbers switch, layer-aware View-results routing
│   │   ├── ParentGateView.swift   Parent gate: swipe-up or accessible hold-buttons mode
│   │   ├── CreateProfileView.swift  Also defines `FirstLaunchOnboardingView` (language + optional backup)
│   │   └── EditProfileView.swift  Avatar + name editing, Reset progress, Delete profile (parent-gated). No reading-practice toggle in the current shipping UI.
│   ├── Game/
│   │   ├── CalibrationView.swift  One-time per-layer calibration (letters pool + name seed, or numbers 1…10 pool via `NumberDifficulty.calibrationPool()`): early stop ~10–12 when evidence is clear; otherwise up to 20–22 rounds (pool ×2)
│   │   ├── GameView.swift         Adaptive game session (letters or numbers per `plan.primaryLayer`; layer-aware intro overlay and Winner claim)
│   │   └── EasyModeGrid.swift     Defines `LetterGrid` + `LetterButton`; renders the option tiles
│   ├── Summary/
│   │   └── SummaryView.swift      Defines `SessionEndView` (file kept named for project stability)
│   ├── Settings/
│   │   └── SettingsView.swift     Music toggle, voice-and-sounds (SFX) toggle, Personalized letters (Čermák), Reduce motion, Confetti, Parent gate, Case practice, Daily reminder, Audio check, Export/Import backup, cloud recovery, Copy diagnostic summary. Also defines `AudioCheckView`, which exposes only the first four language letters as `Replay "Find X"` plus the replayable game SFX clips (`Correct`, `Wrong`, `Streak 5`, `Streak 10`, `Click`).
│   ├── Parent/
│   │   ├── ParentDashboardView.swift  Three-tier letters dashboard: Tier 1 (header/recommendation/needs-attention/focus/progress-glance + the green/yellow/red letter-map palette over the full alphabet), Tier 2 (progress-check summary, sortable+filterable letters list, reading progress — the reading-progress section is dormant), Tier 3 (collapsible diagnostics for retention/test rounds/confusions/raw history). Glossary alert + ellipsis menu for overrides, granular resets, progress-check skip.
│   │   └── ParentNumberDashboardView.swift  Focused numbers sibling: header with band chip, knowledge buckets + number map over the introduced pool (`numberKnowledgePool`), recent number rounds (filtered by `unitKind == .number`), common confusions, numbers-layer resets and extra practice. Also defines the `numberKnowledgePool` snapshot extension.
│   └── Components/
│       ├── ConfettiView.swift
│       ├── DesignSystem.swift     Brand colors, typography, button styles, `BrandBackground`
│       └── ShareSheet.swift
├── Assets.xcassets/
├── Sounds/                        See "Required assets → Audio" for the full layout
├── Pismenka.entitlements          Sign in with Apple and other target capabilities
└── Info.plist

website/                           Separate Astro static marketing site (pismenka.com: home, privacy, support) deployed to Cloudflare Pages; not part of the iOS learning engine
```

Three file-naming quirks worth knowing about (kept this way to avoid churning the Xcode project file):

- `EasyModeGrid.swift` defines `LetterGrid`, not an `EasyModeGrid` type.
- `SummaryView.swift` defines `SessionEndView`, not a `SummaryView` type.
- `Settings/SettingsView.swift` also contains `AudioCheckView`, `PersonalizedLettersCodeSheet`, and the shared `BrandPrimaryButtonStyle` / `BrandSecondaryButtonStyle` — they were intentionally kept in the same file to colocate the parent-area UI.
- `CreateProfileView.swift` also contains `FirstLaunchOnboardingView` (app-level language + optional backup before profile select).

---

## Data storage

Progress is saved locally first and the app does not need network access for gameplay, learning, calibration, dashboards, audio, or checkpoints. `ProfileManager` persists to `UserDefaults` under the key **`pismenka_profiles_v2`**, with **`pismenka_profiles_v2_last_good`** and **`pismenka_profiles_v2_recovery`** used for last-readable backup and corrupt-payload preservation. Local profile saves run after most mutations (including each recorded answer) and are forced at session-end via `ProfileManager.endSession`. During active game/calibration sessions, `scenePhase` transitions to inactive/background persist **session checkpoints**; calibration checkpoint persistence also calls `ProfileManager.flushPendingSave()`. `FirebaseBackupService` separately listens for `applicationWillResignActive` and `willTerminate` to push cloud backups when signed in (same flush path as backgrounding).

Firebase is optional parent-controlled backup only. If enabled, local profiles are mirrored to Firebase for Apple or Google account recovery; if disabled or offline, the learning experience is unchanged.

`FirebaseBackupService` signs the parent in with Apple or Google via Firebase Auth and writes a compact backup document to Firestore at **`users/{uid}/backups/current`**. The document stores metadata (`schemaVersion`, `savedAt`, `appVersion`, `payloadBytes`, `payloadEncoding`) plus a binary `payload` containing a JSON `CloudBackupEnvelope`, compressed with LZFSE when that is smaller. Payloads larger than about **900 KB** are rejected before upload. Profile and settings changes schedule a debounced auto-backup (**2 s** after the last local mutation) while signed in; **Sync now** cancels any pending debounced write, flushes local saves, forces an immediate upload, and waits for Firestore to acknowledge pending writes before reporting success. On sign-in, launch, and explicit **Restore**, the service automatically merges profiles by `Profile.id`, keeping the newer `modifiedAt` for matching profiles and adding new profiles up to the four-profile limit. The settings **Cloud recovery** row exposes Sign in with Apple (system `SignInWithAppleButton`), **Sign in with Google**, **Sync now**, **Restore**, and **Sign out** when authenticated. App settings are restored from the newest settings snapshot. Session checkpoints stay local-only because they are short-lived resume state, not long-term learning progress.

Each `Profile` carries:

| Field | Type | Purpose |
|---|---|---|
| `id`, `name`, `avatarId`, `language` | identity | Profile identity & locale |
| `modifiedAt` | `Date` | Last profile mutation; used to merge automatic Firebase recovery snapshots |
| `letterStats` | `[String: LetterStat]` | Per-letter mastery (recent results, lifetime totals, exposures, timestamps, override) |
| `syllableStats`, `wordStats` | `[String: SyllableStat]` / `[String: WordStat]` (`typealias` of `UnitProgressStat`) | Per-syllable and per-word mastery |
| `everMasteredLetters` | `Set<String>` | Lifetime mastery — drives `alphabetLevel`; deduplicates re-graduations |
| `everMasteredSyllables`, `everMasteredWords` | `Set<String>` | Lifetime reading mastery — drives `ReadingStage` |
| `introducedLetters` | `Set<String>` | Letters intentionally introduced as focus/target; accidental fallback distractors do not enter this set |
| `cameoExposureDay`, `cameoExposuresToday` | `LocalDay?`, `Int` | Per-local-day budget for intentional cameo distractor exposures |
| `dailyPracticeDay`, `dailyPracticeAttempts` | `LocalDay?`, `Int` | Visible daily progress counter; backs `dailyGoalStartCount` and persists 25/adaptive progress across same-day sessions |
| `dailyPracticeWinnerClaimedDay`, `dailyPracticeWinnerClaimedMilestone` | `LocalDay?`, `Int` | Same-day Winner receipt; hides the Winner button until another full goal chunk is completed |
| `dailyTargetAskDay`, `dailyTargetAskCounts` | `LocalDay?`, `[String: Int]` | Per-letter target asks for the current local day; makes the introduction-day 10-ask cap hold across sittings |
| `learningCycleStartDay`, `weeklyIntroducedLetters` | `LocalDay?`, `Set<String>` | Informational cycle start and spotlight cohort retained under legacy storage names |
| `completedLetterSessionsInCycle` | `Int` | Claimed 25-answer letter sessions in the current cycle; the next session becomes a progress check at six |
| `activeWeeklyAssessment` | `WeeklyLetterAssessment?` | Current frozen review/test audit and per-letter retained/watch/review evidence. Completed same-day assessments remain here until the next local day. |
| `recentWeeklyAssessments` | `[WeeklyLetterAssessment]` | Completed weekly assessment snapshots, capped to the latest 12, for parent-dashboard retention history. |
| `introducedSyllables`, `introducedWords` | `Set<String>` | Reading units intentionally introduced as focus/target |
| `currentFocusLetter` | `String?` | Durable letter-layer focus/remediation target. Today's variety may instead come from `SessionPlan.dailySpotlightLetter`, while the overlay reads `SessionPlan.introducedFocusTarget`. |
| `currentSyllableFocus`, `currentWordFocus` | `String?` | Today's reading focus |
| `syllablesUnlockedAt`, `wordsUnlockedAt` | `LocalDay?` | Sequential reading-layer unlock gates |
| `readingPracticePaused` | `Bool` | Parent toggle for letter-only practice after Czech reading unlock |
| `pausedFocusLetters`, `pausedFocusLetterDays` | `Set<String>`, `[String: LocalDay]` | Stuck-focus escape hatch; paused letters are skipped by the next-focus picker for 7 local days or until reset/reopened |
| `lastFocusSelection` | `FocusSelectionReason?` | Why the current focus was selected (`prerequisiteReady`, `staleWeakness`, `diacriticAfterBaseMastered`, etc.) |
| `recentRoundEvents` | `[RoundEvent]` | Last 200 local-only round logs for dashboard/debugging |
| `focusStartedDay`, `focusPracticedDays` | `LocalDay?`, `Set<LocalDay>` | Focus scaffolding ladder; `focusActiveDays` is `focusPracticedDays.count` |
| `lastSessionDay`, `lastNewLetterDay` | `LocalDay?` | Day-streak engine + one-formal-introduction-per-day gate. The `lastNewLetterDay` key is retained for migration compatibility, but the gate now applies to letters, slabiky, and words. |
| `dailyStreakCount` | `Int` | Current streak |
| `bestDailyStreak` | `Int` | Lifetime trophy — preserved across resets |
| `bestSessionStreak` | `Int` | Best in-session correct-streak |
| `highestAlphabetLevelEverReached` | `AlphabetLevel` | Monotonic alphabet trophy |
| `celebratedAlphabetLevels` | `Set<AlphabetLevel>` | Receipts — guarantees one alphabet level-up celebration per alphabet level per profile |
| `lastFrozenLetterOptionsPerRound` | `Int?` | Last session's frozen 4/6/8 letter-grid size; gives the next session a hysteresis baseline so one slipped letter does not immediately shrink the grid. |
| `gridPerformanceStats` | `[Int: GridPerformanceStat]` | Independent recognition outcomes keyed by displayed option count (4 / 6 / 8). Feeds promotion and maintenance in `AlphabetLevel.letterOptionsPerRound`; updated on independent adaptive-daily target attempts. |
| `hasCompletedCalibration` | `Bool` | Routes to letter calibration on first launch |
| `hasCompletedSyllableOnboarding`, `hasCompletedSyllableCalibration`, `hasCompletedWordOnboarding`, `hasCompletedWordCalibration` | `Bool` | Reading-layer intro/calibration receipts |
| `numberStats` | `[String: NumberStat]` | Per-number mastery, keyed by bare digit string (`"0"`…`"100"`); `NumberStat` is a `typealias` of `LetterStat` |
| `introducedNumbers`, `everMasteredNumbers` | `Set<String>` | Numbers intentionally introduced as focus/target; lifetime number mastery set |
| `currentFocusNumber`, `numberFocusStartedDay`, `numberFocusPracticedDays` | `String?`, `LocalDay?`, `Set<LocalDay>` | Durable number focus and its idempotent practice-day ladder (`numberFocusActiveDays` is the set count; `numberFocusScaffoldingLevel = max(0, 4 − days)`) |
| `lastNewNumberDay` | `LocalDay?` | One-formal-number-introduction-per-day gate (also consumed by number focus graduation) |
| `pausedFocusNumbers`, `pausedFocusNumberDays` | `Set<String>`, `[String: LocalDay]` | Numbers stuck-focus escape hatch with the same 7-day cooldown |
| `lastNumberFocusSelection` | `FocusSelectionReason?` | Provenance of the most recent number-focus pick |
| `hasCompletedNumberCalibration` | `Bool` | Routes to numbers calibration on the first Numbers-mode profile tap |
| `numberDailyPracticeDay`, `numberDailyPracticeAttempts` | `LocalDay?`, `Int` | Numbers twin of the visible daily progress counter |
| `numberDailyPracticeWinnerClaimedDay`, `numberDailyPracticeWinnerClaimedMilestone` | `LocalDay?`, `Int` | Numbers twin of the Winner claim receipt |
| `numberDailyTargetAskDay`, `numberDailyTargetAskCounts` | `LocalDay?`, `[String: Int]` | Numbers twin of the per-day target-ask cap seed |
| `numberCameoExposureDay`, `numberCameoExposuresToday` | `LocalDay?`, `Int` | Reserved numbers cameo budget twins — persisted, but nothing increments them today (numbers rounds do not inject cameos) |
| `numberLearningCycleStartDay`, `weeklyIntroducedNumbers` | `LocalDay?`, `Set<String>` | Numbers twin of the cycle start / spotlight cohort |
| `completedNumberSessionsInCycle` | `Int` | Claimed 25-answer number sessions in the current cycle; the next numbers session becomes a progress check at six |
| `activeWeeklyNumberAssessment`, `recentWeeklyNumberAssessments` | `WeeklyNumberAssessment?`, `[WeeklyNumberAssessment]` | Numbers twin of the frozen progress-check audit and its capped history (`WeeklyNumberAssessment` is a `typealias` of `WeeklyLetterAssessment`) |
| `numberGridPerformanceStats`, `lastFrozenNumberOptionsPerRound` | `[Int: GridPerformanceStat]`, `Int?` | Numbers twin of the grid promotion evidence and frozen-grid hysteresis baseline. Unlike the letter fields, both **are** wiped by `resetAllProgress` |
| `highestNumberBandEverReached`, `celebratedNumberBands` | `NumberInstructionalBand`, `Set<NumberInstructionalBand>` | Monotonic numbers band trophy and one-celebration-per-band receipts (`.beginner` pre-celebrated); preserved across resets like the alphabet crowns |
| `parentNote` | `String?` | Free-form parent note attached to the profile. Informational only; never feeds the adaptive model. (`LetterStat` has its own per-letter `parentNote` with the same contract.) |

`Profile`, `LetterStat`, `UnitProgressStat`, `WeeklyLetterAssessment`, `RoundEvent`, `SessionPlan`, and checkpoint snapshots implement tolerant `Codable` paths where needed so older payloads or missing new fields decode cleanly (e.g., legacy `Date` fields → `LocalDay`, `lifetimeAttempts` → `targetAttempts`, missing `RoundEvent` cameo/focus fields, missing daily-goal/session-plan fields such as `introducedFocusTarget`, and old `GameEngineSnapshot` payloads without `instructionalBand`).

Hardening migrations are intentionally additive; no on-disk schema bump is required for these fields:

- `LetterStat` / `UnitProgressStat` evidence-tier additions are computed properties, so no stored profile field or schema bump is required.
- `AttemptContext`, `cameoLetter`, `includedFocusAsDistractor`, and `planReason` are optional/default-valued `RoundEvent` additions. Missing `attemptContext` remains stored as `nil`, and consumers semantically default it to independent practice with `attemptContext ?? .independent`; missing cameo/focus fields read as no cameo / no focus-distractor flag.
- `Profile.dailyPracticeDay`, `dailyPracticeAttempts`, `learningCycleStartDay`, and `weeklyIntroducedLetters` default to nil/zero/empty on old profiles. They start participating the next time a daily plan is committed.
- `Profile.activeWeeklyAssessment` defaults to nil and `recentWeeklyAssessments` defaults to empty on old profiles. New progress-check assessment history begins with the first committed six-session review/test after this code runs; old aggregate `LetterStat` history is not backfilled into fake retained/watch/review verdicts.
- `Profile.gridPerformanceStats` defaults to empty on older profiles; until enough independent outcomes exist at the current grid size, promotion stays at 4 options even when known/strong pool-safety thresholds are met. Existing 6/8-grid profiles keep a continuity window via `lastFrozenLetterOptionsPerRound` + `supportsMaintenance` until demotion evidence appears.
- Every number twin field decodes with a nil/zero/empty default on pre-numbers profiles. A few get smarter backfills: `introducedNumbers` is seeded from `numberStats` keys plus the focus number when absent, graduated stats re-seed `everMasteredNumbers`, `completedNumberSessionsInCycle` backfills from the claimed number Winner milestone, and the band trophies (`highestNumberBandEverReached` / `celebratedNumberBands`) are derived from current number evidence when missing.
- `SessionPlan.dailyGoalTarget`, `dailyGoalStartCount`, `dailyPracticeKind`, `weeklyReviewLetters`, `dailySpotlightLetter`, and `dailyGoalClaimedCount` all have decode defaults so older checkpoints or tests that lack the new fields still load. Older plans default to a 25-round introduction day with zero starting progress and no spotlight.
- `readingPracticePaused` reads legacy `postExpertPracticePaused` payloads; new saves write the broader reading-practice name.
- `pausedFocusLetters` defaults to empty on older profiles, and legacy paused letters get a migration-time `pausedFocusLetterDays` value for the 7-day cooldown.
- `lastFrozenLetterOptionsPerRound` defaults to nil on older profiles; the first new `AdaptiveGameState` session records a fresh frozen 4/6/8 grid size for future hysteresis.
- `alphabetLevel`, `readingStage`, and `instructionalBand` are computed inside `Profile.snapshot`; no stored `Profile` field and no `displayLevel` alias exist. Legacy `highestLevelEverReached` / `celebratedLevels` payloads decode into the alphabet trophy fields, with old reading-level values folded back to `.expert`.
- `GameEngineSnapshot.instructionalBand`, `letterOptionsPerRound`, and `sessionPlayableWords` are persisted only for checkpoint resume consistency. Older checkpoints without `instructionalBand` decode; on restore, `AdaptiveGameState` init falls back to the live profile's `ProfileLearningSnapshot.instructionalBand`, and `apply(_:)` only overrides the band when the snapshot carries a non-nil value. Older checkpoints without `letterOptionsPerRound` fall back to the live profile's current grid gate. Older checkpoints without `sessionPlayableWords` decode and recompute the pool from current audio/profile state when `plan.primaryLayer == .words`. Checkpoints are cleared on session completion, home navigation, or invalid/missing checkpoint payloads — not because the profile snapshot is temporarily unavailable.
- Tightened `wordsShouldUnlock` can delay a future word-layer unlock when audio or playable distractors are missing, but profiles that already have `wordsUnlockedAt` keep it because the predicate is consulted only before unlock.

Letters are stored as flat `String` storage keys. `LetterSymbol` is the typed API-edge wrapper (`base`, `form`, `language`) used to keep lowercase and per-language expansion honest without making JSON dictionary keys complicated. Uppercase legacy letters keep their bare key (`"A"`, `"Č"`), so existing stored profiles decode intact.

Typed round/event keys use `FocusTarget.storageKey` prefixes (`letter:A`, `syllable:MA`, `word:MÁMA`) wherever a mixed learning-unit namespace is needed.

Schema versions:

| Payload | Current schema / storage |
|---|---:|
| UserDefaults profiles | Key `pismenka_profiles_v2`; payload is a JSON `[Profile]` array (no envelope wrapper) |
| Local JSON export | `ProfileExportEnvelope.currentSchemaVersion = 3` (schema 2 imports still decode — schema 2 predates the numbers layer, so profiles decode with number defaults and the envelope upgrades to 3 in memory; re-exports never write schema 2) |
| Firebase backup | `CloudBackupEnvelope.currentSchemaVersion = 3` (same schema-2 upgrade path as local export) |
| Session checkpoint | `SessionCheckpointEnvelope.currentSchemaVersion = 2`; stored locally under `pismenka_session_checkpoint_v2` as a per-layer map keyed by `LearningLayer.rawValue` (`"letters"` / `"numbers"`) |

`SessionCheckpointEnvelope` fields: `schemaVersion`, `profileId`, `kind` (`.calibration` | `.game`), `learningLayer` (pre-layer envelopes decode as `.letters`), `savedAt`, plus kind-specific payloads — `calibration: CalibrationSnapshot?` (schedule, index, grid, intro/finale flags) or `sessionPlan: SessionPlan?` + `game: GameEngineSnapshot?` for in-progress adaptive sessions (`SessionPlan` is defined in `GameState.swift`; `GameEngineSnapshot` in `SessionCheckpoint.swift`). `SessionCheckpointStore` keeps **one slot per learning layer** under `pismenka_session_checkpoint_v2`, so switching the home-screen layer never discards the other layer's in-flight session; clearing one layer's slot leaves the other intact. A legacy single-slot envelope under `pismenka_session_checkpoint_v1` migrates into the letters slot on first load, and the old key is removed.

**Shared streak vs. twin counters.** Letters and numbers share one day-streak engine: `dailyStreakCount` / `lastSessionDay` are single fields, so a numbers session after a letters session on the same `LocalDay` counts as "played today" without double-incrementing the streak. Everything cycle- and goal-related is a **per-layer twin**: `completedLetterSessionsInCycle` / `completedNumberSessionsInCycle`, `dailyPractice*` / `numberDailyPractice*`, `learningCycleStartDay` / `numberLearningCycleStartDay`, `activeWeeklyAssessment` / `activeWeeklyNumberAssessment`, and so on. Claiming a Winner with `layer: .numbers` moves only the numbers cycle counter and vice versa.

**Active layer is local-only.** `AppSettings.activeLearningLayer` (the Letters/Numbers home-screen switch) persists in `UserDefaults` but is deliberately **excluded from `AppSettingsSnapshot`**, so cloud backup/restore never overwrites which layer a device is showing.

---

## Required assets

### App icon

1024×1024 PNG at `Pismenka/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. `Contents.json` references this file, so a fresh workspace must include it before archiving. The current repo snapshot bundles a working PNG at that path; replace it with your own artwork before shipping.

### Audio

The live required audio surface is **letter prompts plus game SFX**. Number prompts under `Sounds/Numbers/` are part of the shipped curriculum surface for Numbers mode, but they stay on the **soft** validation path (see below) so a partial pack never bricks launch. The reading layer is dormant, so syllable / blend / word recordings are not required, validated, reported in the parent audio check, or reachable in normal gameplay. The Xcode project includes `Pismenka/Sounds/` as a folder resource, so everything currently in that folder is bundled; only the hard-required letter+SFX surface below is enforced by `AudioService.missingAssetNames(...)`.

Number voice clips (`{en|cz}_{0…100}.m4a` under `Sounds/Numbers/` — 202 files) are validated **softly**: `AudioService.missingNumberAssetNames(...)` is a diagnostic deliberately kept out of `missingAssetNames`. A **missing** number clip degrades to runtime `AVSpeechSynthesizer` with the same spoken-word forms the generator uses (`NumberSpokenForm`: "twenty-six" / "dvacet šest" — never the raw digit string). Note the fallback fires only when the file is absent from the bundle (`resolveURL` returns nil); a present-but-broken file does not reroute to TTS.

**Current pack state (verify before shipping).** The 202 files in the repo snapshot are tiny **placeholder stubs** — essentially empty ~257-byte M4A containers, versus ~15–25 KB per real Chirp letter clip — so they carry no usable audio. The intended ship path is regenerating the pack with the same Google Chirp pipeline as the letters (`python3 generate_audio_assets.py --provider google --numbers --force --skip-sfx`, see [Recording voice](#recording-voice)); until that runs, either replace the stubs with real clips or delete them so the spoken-word TTS fallback can engage at runtime.

Live required files are organized into subdirectories that the private `resolveBundledAudioURL` helper in `AudioService.swift` searches in order:

```
Pismenka/Sounds/
├── Letters/                         # default English + Czech letter prompts
│   ├── en_a.m4a … en_z.m4a
│   └── cz_a.m4a … cz_z.m4a + every Czech diacritic in GameLanguage.czech.letters
├── Numbers/                         # English + Czech number prompts (0…100)
│   ├── en_0.m4a … en_100.m4a
│   └── cz_0.m4a … cz_100.m4a
├── PersonalizedLetters/
│   └── Cermak/                      # optional Čermák-family Czech letter pack
│       └── cz_<letter>.m4a          # mirrors the base Czech letter set the family has recorded
├── sfx_correct.mp3
├── sfx_wrong.mp3
├── sfx_streak_5.mp3
├── sfx_streak_10.mp3
├── sfx_click.mp3
├── sfx_applause.mp3
└── sfx_wow_en.m4a                   # English "Wow!" used in the Winner celebration for every language
```

The dormant reading layer is designed around `cz_syl_<key>.m4a`, `cz_blend_<key>.m4a`, `cz_word_<key>.m4a`, and `cz_word_<key>_slabikované.m4a` files (with blend variants resolving first in an optional `Sounds/Blends/` subdirectory — not present in the current tree — then the root `Sounds/` folder). Those clips are **not** in the current app bundle; `AudioService.requiredCurriculumVoiceAssets(for:)` returns `[]`, so launch-time validation and the parent **Audio check** screen do not require or report syllable/word assets. When the reading layer reactivates, regenerate or restore the curriculum recordings, add them back under `Pismenka/Sounds/`, and grow `requiredCurriculumVoiceAssets(for:)` to enumerate the slabika and word recordings expected for the active language.

`AudioService` validates SFX and all letters for English and Czech on app launch in `DEBUG` builds, and whenever the parent opens the audio-check screen. The **Audio check** sheet replays the first four letters of the profile language's alphabet (e.g. `A`–`D` for English) and five tap SFX clips (`Correct`, `Wrong`, `Streak 5`, `Streak 10`, `Click`); it does not include replay buttons for `sfx_applause.mp3` or `sfx_wow_en.m4a`, though missing-asset validation still reports any required bundle gaps including applause and Winner clips. Letter prompts replay the letter audio directly (`playFindPrompt` is a thin alias around `playLetter`), lowercase storage keys reuse the uppercase audio file (`Q|lower` looks for `en_q.m4a`), and letter prompts fall back to `AVSpeechSynthesizer` if an asset is missing. Missing files are shown to parents in the audio-check sheet, and playback failures fail gracefully rather than crashing.

List or verify the expected bundled letter/SFX set without regenerating anything:

```bash
python3 generate_audio_assets.py --dry-run
```

Personalized Czech letter prompts are opt-in. The settings screen's **Personalized letters** row triggers `PersonalizedLettersCodeSheet`, which unlocks with the 4-digit family code **`2436`** and toggles `AppSettings.personalizedCzechLettersEnabled`. When enabled, the asset resolver searches `Sounds/PersonalizedLetters/Cermak/` before `Sounds/Letters/`, so any Čermák-recorded Czech letter overrides the default voice. Letters the family has not yet recorded simply fall back to the default `Sounds/Letters/cz_*.m4a` clip, so personalization is additive rather than destructive.

Visual-only distractors (`1`, `rn`) do not need prompt audio because they are never target letters.

#### Recording voice

All curriculum voice clips (letters **and** numbers) are **machine-generated** — there is no human-recording step in the shipping pipeline. The shipped default letter (and intended shipped number) recordings use **Google Cloud Text-to-Speech Chirp 3 HD**:

- Czech: `cs-CZ-Chirp3-HD-Achernar`.
- American English: `en-US-Chirp3-HD-Aoede`.

Regenerate the reviewed default letter sets with `gcloud` authenticated and the Cloud Text-to-Speech API enabled:

```bash
python3 generate_audio_assets.py --provider google --only-czech-letters --force --skip-sfx
python3 generate_audio_assets.py --provider google --only-english-letters --force --skip-sfx
```

Regenerate the full Numbers pack (0…100 × EN/CZ = 202 files) the same way — word-form prompts and Czech counting overrides (`jedna` / `dvě`, compounds like `dvacet jedna`) live in `generate_audio_assets.py` (`NUMBER_SPOKEN_FORMS` / Google text overrides); never feed digit strings to TTS:

```bash
python3 generate_audio_assets.py --provider google --numbers --force --skip-sfx
```

`generate_audio_assets.py` uses the active `gcloud` project as the quota project, or `GOOGLE_OAUTH_ACCESS_TOKEN` / `GOOGLE_CLOUD_PROJECT` when those environment variables are set. Override the default voices with `GOOGLE_CZ_VOICE` or `GOOGLE_EN_VOICE`. The script's default `--provider` is `say` (macOS Samantha/Zuzana) for offline scaffolding; the **shipped** default letter sets were generated with `--provider google` and the Chirp 3 HD voices above, and numbers should match that same Google Chirp pipeline before release. The Google provider also carries the reviewed Czech pronunciation overrides for the cases Google otherwise expands awkwardly: standalone long vowels, `ě`, `x`, `ý`, and `z`, plus the number spoken-form table.

Prompts keep pronunciation-friendly punctuation: Czech letter prompts use a comma pause such as `Bé, jako banán.`. The dormant reading-layer prompts are designed to use comma-separated components (`m, á, má` for blends, `má, ma` for segmented words) and natural lowercase for fluent reads (`máma`).

When the reading layer reactivates, syllable/word recordings will be required `.m4a` files for every seeded curriculum unit — slabiky use `cz_syl_<key>.m4a` and `cz_blend_<key>.m4a`, words use `cz_word_<key>.m4a` and `cz_word_<key>_slabikované.m4a` — and the child-facing prompts will not fall back to system speech because Czech vowel length and prosody are part of the lesson. The curriculum gates in `SyllableCurriculum`, `WordCurriculum`, and `wordsShouldUnlock` already consult `CurriculumAudioAvailability`, so a missing recording will keep that unit out of onboarding, calibration, focus selection, and word prerequisites, and gameplay will replan around it.

The current `Pismenka/Sounds/` snapshot contains the live letter-and-SFX surface plus the Numbers pack:

- Six gameplay SFX clips (`sfx_correct.mp3`, `sfx_wrong.mp3`, `sfx_streak_5.mp3`, `sfx_streak_10.mp3`, `sfx_click.mp3`, `sfx_applause.mp3`).
- Daily-Winner celebration voice clip: `sfx_wow_en.m4a` ("Wow!"), played for every profile language.
- English base letters `en_a.m4a` … `en_z.m4a` (26 files) in `Sounds/Letters/`.
- Czech base letters `cz_a.m4a` … `cz_z.m4a` plus every diacritic letter in `GameLanguage.czech.letters` (`cz_á`, `cz_č`, `cz_ď`, `cz_ě`, `cz_é`, `cz_í`, `cz_ň`, `cz_ó`, `cz_ř`, `cz_š`, `cz_ť`, `cz_ú`, `cz_ů`, `cz_ý`, `cz_ž`) — 41 files total in `Sounds/Letters/`.
- Numbers `en_0.m4a` … `en_100.m4a` and `cz_0.m4a` … `cz_100.m4a` (202 files) in `Sounds/Numbers/`. **Currently placeholder stubs** (~257 bytes each, no usable audio) — regenerate with `--provider google` (Chirp 3 HD, same voices as the letters) before release; a local `--provider say` pass is only offline scaffolding.
- Optional Čermák personalized Czech letter pack in `Sounds/PersonalizedLetters/Cermak/` (41 files), used only when the parent unlocks the **Personalized letters** setting. The current pack mirrors the full Czech alphabet.
- **Not bundled today:** Czech reading-layer clips (`cz_syl_*`, `cz_blend_*`, `cz_word_*`, segmented `cz_word_*_slabikované`), legacy decomposed letter filenames, or a `Sounds/Blends/` subdirectory. Older generations of those files may still exist under repo backup folders outside the app target; they are intentionally omitted from the shipped bundle while the reading layer stays dormant.

#### Daily-Winner celebration audio

The Winner moment plays a two-clip sequence in `AudioService.playWinnerCelebration(language:)`: `sfx_wow_en.m4a` first, then `sfx_applause.mp3` starting 0.55 s later so the crowd reaction overlaps the tail of the spoken exclamation the way a real audience would. The same English "Wow!" plays for every profile language — the exclamation reads as universally celebratory and avoids the awkward Czech-tail overlap a longer per-language clip produced. The `language:` parameter is preserved on the API in case future per-language variants are reintroduced.

- `sfx_wow_en.m4a` is generated via ElevenLabs (`eleven_multilingual_v2`) using `ELEVENLABS_EN_VOICE_ID` or the script's ElevenLabs English default. The celebration clip overrides the default ElevenLabs voice settings (lower `stability`, higher `style`) via `ELEVENLABS_VOICE_SETTINGS_OVERRIDES` in `generate_audio_assets.py` so the exclamation has real energy. Regenerate with `python3 generate_audio_assets.py --provider elevenlabs --only-files <(echo 'sfx_wow_en.m4a') --skip-sfx --force`.
- `sfx_applause.mp3` was sourced once from Wikimedia Commons file `Clapping_hurray_(cropped).oga` (~9.8 s, public domain — released by author Zack and friends, uploaded by Starlite), trimmed to ~3.5 s, fade-in/out applied, normalized to -14 LUFS, and re-encoded to 128 kbps mono mp3. The bundled clip is committed as a static asset; no re-fetch script is checked into this repo today, so any future regeneration is a manual ffmpeg pass against an equivalent public-domain source.
- In gameplay, `GameView` calls `AudioService.playWinnerCelebration` only when **Voice and sounds** is enabled in settings (`settings.sfxEnabled`). Visual celebration (confetti / "WOW!") still runs if SFX is off.

---

## Building

Open `Pismenka.xcodeproj` in **Xcode 16+** (see [`README.md`](../README.md)) and run the `Pismenka` scheme on iOS 17+. Command-line build:

```bash
xcodebuild -project Pismenka.xcodeproj -scheme Pismenka -destination 'generic/platform=iOS Simulator' build
```

### App Store Connect CLI release flow

Use an App Store Connect API key for non-interactive releases. Never use an Apple ID password in chat or scripts, and never commit the private key. The repo `.gitignore` excludes `AuthKey_*.p8`, `build/`, and local Xcode artifacts.

Current App Store identifiers:

| Field | Value |
|---|---|
| Apple ID / app id | `6771856001` |
| Bundle ID | `CY-C7DBCED6-A931-11E9-A784-3F0DCDF3F5B5.com.electratea` |
| Team ID | `6VJV65V7PB` |
| Platform | `IOS` |

Credential setup:

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. Generate an API key with the **App Manager** role.
3. Download the `.p8` exactly once and place it at the repo root as `AuthKey_<KEY_ID>.p8`.
4. Store `<KEY_ID>` and `<ISSUER_ID>` in a password manager. Treat the `.p8` as a secret; revoke it in App Store Connect if it is exposed.

Before each release:

```bash
# Example: public version 1.4, build 1. Update both Debug and Release app/test
# MARKETING_VERSION / CURRENT_PROJECT_VERSION values in project.pbxproj.
VERSION=1.4
BUILD=1
KEY_ID=<KEY_ID>
ISSUER_ID=<ISSUER_ID>
P8_PATH="$PWD/AuthKey_${KEY_ID}.p8"
APP_ID=6771856001
BUNDLE_ID=CY-C7DBCED6-A931-11E9-A784-3F0DCDF3F5B5.com.electratea
```

Build, test, archive, and upload:

```bash
xcodebuild test \
  -project Pismenka.xcodeproj \
  -scheme Pismenka \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' \
  -derivedDataPath build/DerivedData

xcodebuild archive \
  -project Pismenka.xcodeproj \
  -scheme Pismenka \
  -destination 'generic/platform=iOS' \
  -archivePath "build/Pismenka-${VERSION}-${BUILD}.xcarchive" \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "build/Pismenka-${VERSION}-${BUILD}.xcarchive" \
  -exportOptionsPlist build/AppStoreExportOptions.plist \
  -exportPath "build/AppStoreUpload-${VERSION}-${BUILD}" \
  -allowProvisioningUpdates
```

`build/AppStoreExportOptions.plist` should use `method = app-store-connect`, `destination = upload`, `teamID = 6VJV65V7PB`, and `manageAppVersionAndBuildNumber = false`. The export/upload may warn about missing dSYMs for Firebase/grpc binary frameworks; that did not block App Store upload or review submission.

Generate a JWT for App Store Connect API calls. `altool` prints a banner before the token, so extract the JWT explicitly:

```bash
TOKEN="$(
  xcrun altool --generate-jwt \
    --api-key "$KEY_ID" \
    --api-issuer "$ISSUER_ID" \
    --p8-file-path "$P8_PATH" 2>&1 \
  | /usr/bin/grep -Eo 'eyJ[A-Za-z0-9_.-]+' \
  | tail -n 1
)"
```

Useful API checks:

```bash
# Confirm API access to this app.
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=${BUNDLE_ID}"

# Wait until the uploaded build is VALID and APP_STORE_ELIGIBLE.
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${APP_ID}&filter%5Bversion%5D=${BUILD}&include=preReleaseVersion&sort=-uploadedDate&limit=10"
```

Create the App Store version if it does not already exist:

```bash
python3 - <<PY > /tmp/pismenka-create-version.json
import json
print(json.dumps({
  "data": {
    "type": "appStoreVersions",
    "attributes": {"platform": "IOS", "versionString": "$VERSION"},
    "relationships": {"app": {"data": {"type": "apps", "id": "$APP_ID"}}}
  }
}))
PY

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-create-version.json \
  "https://api.appstoreconnect.apple.com/v1/appStoreVersions"
```

Record the returned `APP_STORE_VERSION_ID`. Query the created version with `include=appStoreVersionLocalizations,build` to get the localization id:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=${VERSION}&include=appStoreVersionLocalizations,build"
```

Attach the processed build. `PATCH` may return an empty body on success, so verify afterward:

```bash
python3 - <<PY > /tmp/pismenka-attach-build.json
import json
print(json.dumps({"data": {"type": "builds", "id": "<BUILD_ID>"}}))
PY

curl -sS -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-attach-build.json \
  "https://api.appstoreconnect.apple.com/v1/appStoreVersions/${APP_STORE_VERSION_ID}/relationships/build"
```

Set release notes and IDFA answer:

```bash
python3 - <<PY > /tmp/pismenka-whats-new.json
import json
print(json.dumps({
  "data": {
    "type": "appStoreVersionLocalizations",
    "id": "<LOCALIZATION_ID>",
    "attributes": {
      "whatsNew": "Adds a parent dashboard letter map for a faster at-a-glance view of known, maybe-known, and not-yet-practiced letters."
    }
  }
}))
PY

curl -sS -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-whats-new.json \
  "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/<LOCALIZATION_ID>"

python3 - <<PY > /tmp/pismenka-idfa.json
import json
print(json.dumps({
  "data": {
    "type": "appStoreVersions",
    "id": "$APP_STORE_VERSION_ID",
    "attributes": {"usesIdfa": False}
  }
}))
PY

curl -sS -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-idfa.json \
  "https://api.appstoreconnect.apple.com/v1/appStoreVersions/${APP_STORE_VERSION_ID}"
```

Submit for review:

```bash
python3 - <<PY > /tmp/pismenka-create-review-submission.json
import json
print(json.dumps({
  "data": {
    "type": "reviewSubmissions",
    "attributes": {"platform": "IOS"},
    "relationships": {"app": {"data": {"type": "apps", "id": "$APP_ID"}}}
  }
}))
PY

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-create-review-submission.json \
  "https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
```

Record the returned `REVIEW_SUBMISSION_ID`, add the app version as an item, then submit:

```bash
python3 - <<PY > /tmp/pismenka-review-item.json
import json
print(json.dumps({
  "data": {
    "type": "reviewSubmissionItems",
    "relationships": {
      "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": "$REVIEW_SUBMISSION_ID"}},
      "appStoreVersion": {"data": {"type": "appStoreVersions", "id": "$APP_STORE_VERSION_ID"}}
    }
  }
}))
PY

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-review-item.json \
  "https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems"

python3 - <<PY > /tmp/pismenka-submit-review.json
import json
print(json.dumps({
  "data": {
    "type": "reviewSubmissions",
    "id": "$REVIEW_SUBMISSION_ID",
    "attributes": {"submitted": True}
  }
}))
PY

curl -sS -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/pismenka-submit-review.json \
  "https://api.appstoreconnect.apple.com/v1/reviewSubmissions/${REVIEW_SUBMISSION_ID}"
```

Successful submission returns `state: WAITING_FOR_REVIEW`.

### Firebase / cloud backup setup

1. Create or reuse a Firebase project.
2. Add an iOS app in Firebase with the bundle ID currently configured in the app target: `CY-C7DBCED6-A931-11E9-A784-3F0DCDF3F5B5.com.electratea`.
3. Add `GoogleService-Info.plist` at the project root so the existing Xcode project file can bundle it in the `Pismenka` app target. The plist is listed in `.gitignore` and is **not** committed to git — download it from your Firebase iOS app and place it at the repo root before building cloud backup or running model tests that assert plist bundling. `FirebaseBootstrap.configureIfPossible()` no-ops when the plist is missing, so the app can still build for local letter-only play, but the cloud backup path requires it.
4. Enable Firebase Authentication → Google provider.
5. Create Cloud Firestore in production mode and apply rules equivalent to the snippet below. This repo does **not** currently include `firebase.json`, `firestore.rules`, or `.firebaserc`; create/link those files before using `firebase deploy --only firestore:rules`, or paste the rules manually in the Firebase console.
6. In Xcode, ensure the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` matches the URL scheme in `Pismenka/Info.plist`. The checked-in scheme is `com.googleusercontent.apps.46536499967-hfc1pbvdbepkk0tjcme9k2hrb3v6ol1u`.
7. Verify the app icon and all required audio files are present.
8. Select your development team.
9. Build and run on iOS 17+ device or simulator.

### Development verification cadence

Adaptive-engine changes should be batched before expensive Xcode runs. Use IDE diagnostics while editing, then run one full app build of the `Pismenka` scheme and one `PismenkaTests` suite run after the related phases are implemented. Place `GoogleService-Info.plist` at the repo root before running tests that assert Firebase bundling (`testGoogleServiceInfoPlistIsBundledAndMatchesApp`, URL-scheme alignment). If a new Swift file is added, ensure the Xcode project target membership is updated before that final build.

`PismenkaTests` covers the main planner/engine invariants: daily goals (25 / adaptive 8–40), same-day progress, weekly assessment scheduling and scoring, checkpoints, overrides, cameos, letter grids, hearts vs session end, assisted-discount behavior, and tolerant legacy decode. Reading-layer tests are mostly routing/typed-round smoke tests (no positive full-alphabet syllable-unlock assertion, no syllable 4-option grid test). See the test file for the authoritative list rather than treating any prose inventory as exhaustive.

Firestore rules:

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/backups/current {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## Technical notes

- **Exact resume** — `ContentView` restores an in-progress calibration or adaptive game from `SessionCheckpointStore` on launch; checkpoints clear on normal session end, home, profile delete/reset, backup import merge, and other explicit `checkpointStore.clear(...)` paths. Selecting a different profile from the profile picker does not delete another profile's saved checkpoint; one checkpoint is stored per learning layer (letters / numbers), each keyed by `profileId`.
- **Portrait lock** — the app only runs in portrait orientation.
- **Third-party cloud** — Firebase Auth + Firestore and Google Sign-In provide recovery without Apple iCloud entitlements. Firebase Analytics / Crashlytics are not integrated.
- **iOS 17.0+ runtime; Xcode 16+ to build.** The project sets `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; minimum Xcode is documented in `README.md`, not in `project.pbxproj`.
- **Hardening trade-offs.** Conservative gates can make the app feel one session behind sudden improvement, but they avoid promoting unsupported distractors, unplayable reading units, or assisted attempts into mastery evidence.
- **Deferred follow-ups.** Longitudinal retention decay beyond the progress-check assessment snapshot, richer rhyme/first-sound/clap-syllables mini-games, parent voice packs/name recording, optional tracing UI, micro-phrases, font policy, and physically blocking input for the first 300-400 ms after options appear are intentionally outside the current hardening contract.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](../LICENSE) (`AGPL-3.0-only`).

Code may be used, studied, modified, and shared under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
