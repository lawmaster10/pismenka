# Písmenka 🔤

A profile-based **adaptive** pre-reading game for toddlers (ages 3-5). Open it once a day; the app figures out which letters your child knows, gives them a visible daily practice goal, introduces a fresh daily spotlight letter without destroying longer-term remediation state, explicitly shows and drills that same introduced unit, and runs a Sunday-anchored weekly letter review/test for retention. The Expert alphabet crown remains the long-term trophy.

iOS 17+, SwiftUI.

> **Current release scope.** The shipped app is **100 % letter-based**. The Czech syllable (`slabiky`) and word-reading models, gates, focus state, distractor pools, calibration phases, and `ReadingStage` ladder all still live in the codebase as future-version scaffolding, but they are **silent in the current build** — not scheduled, not unlocked, not shown in the UI, and not validated as required assets. The live required audio surface is English/Czech letter prompts, the optional personalized Czech letter pack, and game SFX only; `AudioService.requiredCurriculumVoiceAssets(for:)` returns `[]`, so syllable/blend/word clips are neither required nor bundled in the current `Pismenka/Sounds/` tree (115 tracked files: 67 letter prompts, 41 optional Čermák Czech prompts, 7 SFX/Winner clips). `AudioService` still knows the future reading filenames/paths (`cz_syl_*`, `cz_blend_*`, `cz_word_*`, optional `Sounds/Blends/`), but those recordings are absent from the app bundle today — older copies may still exist in repo backup folders such as `audio_backups/` outside the Xcode target. Session planning in `ProfileManager.previewSessionPlan(...)` uses a local profile copy with `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` nilled out; the committed first-answer path persists the same clearing and hard-codes `primaryLayer = .letters`. Throughout this document, any subsection describing syllable/word behavior — CV bridge, `syllableCalibration` / `syllableRecognition` / `syllableBlending` / `wordReading` / `wordBuilding` phases, `WordCurriculum` audio gates, reading-stage badges, the `readingPracticePaused` toggle, and so on — describes **dormant scaffolding kept healthy for a future release**, not behavior the current build exposes. The README is the short product-scope statement; this document carries the exact repo asset inventory.
>
> **Roadmap (not yet in the codebase).** The next planned learning track is **numbers** (number recognition, counting, early quantity work), which will land *before* the Czech reading layer is re-activated. There is no `NumberCurriculum`, `NumberStat`, or numbers-layer plumbing in the repository yet — the order is intentional: numbers first, reading second. Plan the eventual schema and routing work as a peer of the existing letter/reading layers (its own `UnitKind`, its own `requiredCurriculumVoiceAssets(...)` entries, its own `LearningLayer` case, its own dashboard surfaces, its own reset semantics) so that turning the silent reading scaffolding back on remains a separate later step.

---

## Table of contents

- [What the app does](#what-the-app-does)
- [User flow](#user-flow)
  - [First launch](#1-first-launch--profile-creation)
  - [Calibration](#2-calibration-one-time-per-profile)
  - [Daily session](#3-daily-session)
  - [Daily goal, Winner button, and progress strip](#daily-goal-winner-button-and-progress-strip)
  - [Weekly Sunday Review/Test](#weekly-sunday-reviewtest)
  - [Session end & "Play again"](#4-session-end--play-again)
  - [Parent dashboard](#5-parent-dashboard)
- [The adaptive learning model](#the-adaptive-learning-model)
  - [Per-letter mastery (`LetterStat`)](#per-letter-mastery-letterstat)
  - [Alphabet levels & reading stages](#alphabet-levels--reading-stages)
  - [Answer-grid sizing: 4 / 6 / 8 options](#answer-grid-sizing-4--6--8-options)
  - [Daily spotlight, durable focus & scaffolding ladder](#daily-spotlight-durable-focus--scaffolding-ladder)
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
| Profiles | Up to 4, each fully independent |
| Languages | English 🇺🇸 and Czech 🇨🇿 (per profile) |
| Network | Not needed for gameplay or learning; optional Google/Firebase backup for parents |
| Core loop | Hear a letter → pick the matching letter from a playful options grid (slabika/word loops remain dormant scaffolding) |
| Difficulty | Self-adjusting per child, per letter, per day, with a Sunday-anchored weekly letter review/test and persisted retention assessment |
| Session length | ~3-7 minutes per sitting, paced by 5 hearts; daily progress persists toward and beyond a visible 25/adaptive-round goal |
| Parent surface | Hold a profile card → iOS context menu → **View results** (parent gate → dashboard) or **Edit profile** (parent gate → edit sheet) |

---

## User flow

```
ProfileSelectView
   │
   ├──[gear + parent gate]──────────────────▶ SettingsView
   │
   ├──[hold profile → iOS context menu]
   │      │
   │      ├──[View results + parent gate]──▶ ParentDashboardView
   │      │                                   │
   │      │                                   └──[practice letter]──▶ GameView
   │      │
   │      └──[Edit profile + parent gate]──▶ EditProfileView
   │
   └──[tap profile]──▶ (first time?) ──▶ CalibrationView ──▶ GameView
                       (calibrated)   ──▶                    GameView
                                                                │
                                                                ▼
                                                         SessionEndView
                                                          │      │
                                                  replay icon   home icon
                                                          │      │
                                                  GameView ◀┘    └──▶ ProfileSelectView
```

The profile card uses iOS's standard `.contextMenu` so the gesture is discoverable (long-press triggers the system menu, with a haptic). A small hint line — `Tap a card to play · Hold for parent options.` — sits below the profile grid so parents can find it without a tutorial. Both context menu actions still pass through `ParentGateView` before the dashboard or edit sheet opens.

Root navigation lives in [`PismenkaApp.swift`](Pismenka/PismenkaApp.swift) as a four-screen state machine: `profileSelect → calibration → game → sessionEnd`.

### 1. First launch — profile creation

`ProfileSelectView` shows the existing profile cards, up to the four-profile limit, plus a bottom `+` button. When no profiles exist yet, a first-run card explains how to add a child and points parents to the gear icon for settings, backup, and recovery. Tapping `+` triggers the configured parent gate (`ParentGateView`) before `CreateProfileView` opens. The default gate is a swipe-up drag; settings can switch it to a hold-two-buttons accessibility mode.

In `CreateProfileView` the parent picks:

- **Avatar** — emoji picker drives the profile's color theme.
- **Name** — limited to 8 characters; ASCII keyboard, autocorrect off (so "Lulu" doesn't become "Lulu's").
- **Language** — English or Czech. Sets the alphabet and bundled audio prefix for that profile.

The level **is not** chosen — the app discovers it during calibration. There's no "novice/beginner/expert" question for the parent.

### 2. Calibration (one-time per profile)

[`CalibrationView`](Pismenka/Views/Game/CalibrationView.swift) plays a friendly 10-20 round calibration drawn from a 10-letter calibration pool: the nine starter-familiar letters `B V T M J O A C S` plus the next pedagogical letter (English: `P`). The pool is **front-loaded** with the starter-familiar letters so the very first session feels like a stream of small wins, not an assessment.

- Each round records a real `targetAttempts` / `targetCorrect` event; nothing is synthetically pre-marked.
- Distractor selection during calibration uses `ConfusionPolicy.avoid` (no B/D, M/W, P/Q traps yet).
- Calibration can stop after 10-12 rounds when confidence is already clear or fatigue appears; mixed evidence continues to the full 20.
- When calibration ends, the profile flips `hasCompletedCalibration = true` and is routed straight into `GameView`.

A child who already knows most of these letters will exit calibration with several `LetterStat`s already at 2/2 or 4/5, and immediately enter the daily loop with a populated "known letters" set. A child who knows few will exit with mostly weak stats — but no harm done; the next session either shortens or skips warm-up based on the known-letter pool (see below).

### 3. Daily session

`ProfileManager.previewSessionPlan(profileId:)` builds a non-mutating session preview when `GameView` opens. `AdaptiveGameState.commitSessionStartIfNeeded(...)` commits that plan on the first real answer, so merely opening the game does not count as practice. The committed session:

1. Updates the day streak based on the signed delta between today and `lastSessionDay` (in `LocalDay`, not `Date` — see [Day streak](#day-streak-clock-tolerant)).
2. Hard-codes the primary layer to `letters`. The planner deliberately nils out `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` on every commit so the dormant reading-layer scaffolding cannot accidentally enter the live session.
3. Resolves the daily practice contract: ordinary introduction day (`25` target rounds) or a Sunday-or-next-played weekly review/test day with an adaptive frozen target.
4. Decides whether to introduce a fresh **daily spotlight** letter today. The spotlight is intentionally separate from the durable remediation/focus state, so a new day does not automatically wipe an in-flight `currentFocusLetter`.
5. Returns a `SessionPlan` describing warm-up length, durable `focusTarget`, `introducedFocusTarget`, learning layer (always `.letters` for now), activity kind, scaffolding level, daily goal fields, weekly review letters, optional `dailySpotlightLetter`, and streak banners to show.

A session is structured into phases by [`AdaptiveGameState`](Pismenka/Models/GameState.swift):

| Phase | Trigger | Round shape |
|---|---|---|
| `warmup` | Letter sessions only, when the engine starts in warm-up | Target chosen from known letters ordered by review priority; distractors are other known letters. Warm-up deliberately excludes the active focus/spotlight, so a just-introduced letter is not hidden among warm-up distractors before drill begins. Warm-up uses `ConfusionPolicy.avoid`. Current reading-layer sessions return `warmupLength = 0` and start directly in their reading phases. |
| `drill` | Letter sessions after warm-up, while either a durable focus or daily spotlight is active | Mostly the active drill focus as target (with progressive scaffolding); the focus/spotlight also slips in as a "clearly wrong" distractor for extra exposure. Durable remediation focus wins when the child is stuck; otherwise the daily spotlight becomes the active drill focus without clearing `currentFocusLetter`. In a completed 25-round introduction session, the introduced spotlight is expected to appear at least three times and be asked as a target at least once. |
| `plainReview` | Letter sessions when no drill focus is active, including no-focus review and weekly review/test days | Normal review pulls from known letters, weak/stale letters, and confidence-ordered pools. Weekly review/test days first prioritize the frozen weekly assessment cohort until every cohort letter has enough independent evidence, then fall back to weak/stale/global review. The frozen `instructionalBand` gates similar-shape, mixed-case, and visual-only distractors while cameo eligibility follows its own conservative rules. Weekly review/test days use safer confusable rules than later Expert maintenance and do not inject contrast rounds. |
| `maintenance` | Alphabet Expert, no current letter focus | Mixed letter review ordered by `reviewPriority`, with deliberate confusable-pair, mixed-case practice, and eligible cameo letters. Reading stage does not decide letter maintenance by itself. |
| `contrast` | ~1 in 5 eligible review/maintenance rounds | Target is a letter the child often confuses, with the confused letter deliberately shown as a distractor. |
| `rescue` | After a wrong answer | Two-tier re-ask: immediate easy retry; if missed again, a mid-difficulty retry 2–3 rounds later. |
| `syllableCalibration` *(dormant)* | First Czech reading session after reading unlock. In the current code, that dormant unlock path is tied to full alphabet completion, not an early CV bridge. | 12 short-CV recognition rounds with same-vowel consonant contrasts; no long-vowel pairs yet. **Not reachable in the current release** — reading unlock fields are forced to nil at session start. |
| `syllableRecognition` *(dormant)* | Czech profile while the syllable layer is active | Target is the active syllable focus when one exists, otherwise a known/playable CV slabika such as `MA`; options are structurally selected eligible slabiky. |
| `syllableBlending` / `syllableSegmenting` *(dormant)* | Scheduled reading-production activities | Blending adds `M + A -> MA` style segment metadata; segmenting uses word/syllable segment metadata when routed. |
| `wordReading` *(dormant)* | Czech word layer after enough known slabiky | Target is a seeded word such as `MÁMA`; options are eligible words with matching syllable shape where possible. |
| `wordBuilding` *(dormant)* | Scheduled word-production activity | Uses two-syllable tiles and `expectedSequence` / `selectedSequence` in `LearningRound` when invoked. |

Letter sessions use a session-frozen 4/6/8 answer grid from `Profile.letterOptionsPerRound`, based on current known-letter and strong-known-letter counts, not directly on the alphabet-level badge. See [Answer-grid sizing: 4 / 6 / 8 options](#answer-grid-sizing-4--6--8-options) for the exact contract. `instructionalBand` still gates the harder distractor/case behavior, but it no longer directly decides the answer count. `LiveDifficulty` can downshift the frozen grid during struggle. Early slabika and word sessions are designed to stay at 4 choices even when the child is already Expert in letters, but they are not reachable in the current release.

#### Daily goal, Winner button, and progress strip

The daily goal is now a first-class `SessionPlan` contract, not an accidental by-product of stamps or hearts:

| Day type | `DailyPracticeKind` | Visible target | Product meaning |
|---|---|---:|---|
| Ordinary introduction day | `.introduction` | `25` | Enough completed target rounds to count as the child's daily letter practice, with any newly introduced spotlight receiving real drill exposure during the run. |
| Weekly review/test day | `.reviewTest` | Adaptive, floor `8`, hard cap `40` | A Sunday-or-next-played retention audit prioritized by new/weak evidence, capped so the planned test stays child-sized. Test completion cannot leave a planned audit letter at `0/0 independent`. |

`AdaptiveGameState.dailyGoalTotalCount` is:

```
max(0, plan.dailyGoalStartCount + roundsThisSession)
```

`dailyGoalStartCount` comes from `Profile.dailyPracticeCount(on:)`, so a child can do 10 rounds in the morning, run out of hearts, come back later, and see `10 / 25` already filled. Hearts end the **current sitting** only; they do not reset or fail the daily goal.

After the first target is reached, the counter keeps going instead of stopping at `25 / 25` or the frozen review/test target. The visible count switches to extra rounds: `+1`, `+5`, `+25`, and so on. Tapping the Winner button records the highest completed milestone for that local day in `dailyPracticeWinnerClaimedMilestone`. On the next same-day session, Winner stays hidden until the child completes another full goal chunk: after claiming `25`, the next Winner appears at `+25` (`50` total); after claiming an adaptive review/test goal, the next Winner appears after one more full goal chunk.

The Winner tap is intentionally a larger celebration than ordinary correct-answer feedback: it uses full-screen confetti, shows a big `WOW!`, then plays applause before handing off to the session-end screen.

The `GameView` card header and bottom progress strip show the contract visually and numerically:

- Card header eyebrow/title: `TODAY / Daily letters` on introduction days, `REVIEW / Weekly test` on review/test days (parent-directed letter practice uses `Practice / Practicing <letter>` instead).
- Progress strip count: `5 / 25`, `10 / 25`, `25 / 25`, then `+1`, `+5`, `+25`, using monospaced digits via `dailyGoalDisplayText`.
- Progress strip right label: `Winner soon` until the daily goal is reached, then `Goal reached` while extra-round chunks continue.
- Line: a linear `GradientProgressBar`; before the first Winner it fills toward the first goal, and after a Winner claim it refills toward the next full extra chunk.
- The progress strip stays visible during adaptive daily play so the child and parent can predict exactly when Winner appears or reappears.

Only completed adaptive-daily **target** rounds advance `Profile.dailyPracticeAttempts`. This is explicit at the persistence boundary via `countsTowardDailyPractice`:

- Counts: ordinary target rounds, rescue/assisted target rounds, revealed target rounds, and impulsive target attempts when they came from the adaptive daily game flow.
- Does not count: distractor exposure, cameo exposure, visual-only distractors, parent-directed extra practice, opening a preview, or any non-adaptive flow that does not pass the daily counter flag.
- Mastery remains stricter than daily participation. Assisted and impulsive rounds may advance the visible daily bar while still being discounted from `recentResults` / `targetAttempts` where appropriate.

This deliberately separates three ideas that used to be too easy to conflate: **daily participation** (visible 25/adaptive bar), **session pacing** (5 hearts), and **mastery evidence** (`LetterStat` / `UnitProgressStat`).

#### Weekly Sunday Review/Test

The letter layer anchors the longer review/test to Sunday, with "next played day" as a catch-up path:

```
Monday-Saturday: introduce one daily spotlight letter, target 25 rounds/day
Sunday:          adaptive review/test day, frozen target from the audit plan
Missed Sunday:   next played day runs the pending review/test
```

Scheduling is handled in `ProfileManager.resolveDailyPractice(...)`:

- `learningCycleStartDay` marks the start of the current Sunday-anchored cycle.
- `LocalDay.nextSunday()` finds the first Sunday **after** that start day. If the cycle starts on a Sunday, the review is scheduled for the following Sunday so a new profile never tests on day 1.
- When `today >= scheduledReviewDay` and there are at least two eligible weekly letters, the session becomes `.reviewTest`. The visible `dailyGoalTarget` is frozen from the adaptive audit plan rather than hard-coded to 50. It has an `adaptiveSessionFloor` of 8 and treats `adaptiveSessionCeiling` (currently 40) as a hard cap: when full coverage would exceed 40, lower-priority audit entries are omitted from the frozen test. The test ends as soon as every planned audit letter has a non-pending outcome, or after the independent-evidence cap is reached **only once every planned letter has at least one independent attempt**.
- If the child does not play on Sunday, the same pending test remains due and runs on the next played day.
- If fewer than two weekly letters exist when the review would be due, the app keeps the day as `.introduction` (`25`) and does not clear the cycle. There is not enough weekly material for a meaningful test.
- A due letter review/test always runs in the letter layer, because the reading layer is dormant in this release. (The planner is wired so that even if reading routing returns, a due letter review/test still wins.)

The state lives on `Profile`:

| Field | Purpose |
|---|---|
| `dailyPracticeDay`, `dailyPracticeAttempts` | Local-day counter behind the visible 25/adaptive progress bar and extra-round display. |
| `dailyPracticeWinnerClaimedDay`, `dailyPracticeWinnerClaimedMilestone` | Local-day Winner claim receipt; prevents same-day Winner from reappearing until the next full goal chunk is complete. |
| `learningCycleStartDay` | Start of the current Sunday-anchored letter cycle. |
| `weeklyIntroducedLetters` | Letters introduced as daily spotlights during this cycle. |
| `activeWeeklyAssessment` | The frozen adaptive audit and per-letter evidence for the current review/test. |
| `recentWeeklyAssessments` | Completed weekly assessment snapshots, capped to recent history. |

The review/test is deliberately two-layered: a visible participation goal plus a stricter retained/watch/review assessment.

**1. Audit freeze.** `previewSessionPlan` can show that today is a review/test day without mutating the profile. On the first real answer, `commitSessionStartIfNeeded` starts `activeWeeklyAssessment` if needed and freezes an adaptive audit into `cohortLetters` and `results`. The planner prioritizes eligible target-introduced letters (`introducedLetters`, plus any historical target-attempt stats), parent-marked-but-unverified letters, and **letters introduced during the current weekly cycle** — even ones that already look fluent mid-week — but it caps the frozen audit at 40 planned questions so the review/test stays child-sized. Distractor-only exposure (`distractorExposures`, cameo letters, or accidental wrong-option leaks) stays out of the audit because the child was never asked to produce that answer. The whole point of Sunday is the across-days retention check, so a strong-looking spotlight letter from Monday still earns its 4-attempt rerun rather than being demoted to a 1-tap probe. Parent `.reset` overrides still excise a letter entirely. The frozen `dailyGoalTarget` keeps the progress bar stable for same-day resumes, and unfinished tests reuse persisted assessment evidence as the starting progress on following days.

**2. Target ordering.** During `.reviewTest`, `AdaptiveGameState.buildPlainReviewRound(...)` first asks letters that still need audit evidence. The very first round of the day prefers a fluent (or solid) audit letter as a "warm win" so the kid gets a confident success before the cohort grind. After that, candidate scoring favors new/weak/slipped material, previous misses, remaining planned attempts, and review priority while avoiding immediate repeats. A quota-aware coverage guard takes over near the end of the planned evidence budget: if the remaining planned independent slots are no more than the number of zero-attempt audit letters, the picker forces those unattempted letters before spending another slot on repeats. After the adaptive audit is resolved, remaining daily rounds are filler review and are tagged as ordinary review, not assessment evidence:

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

**4. Completion, skip, and archive.** Adaptive assessments complete as soon as every audit letter has a non-pending outcome. The frozen hard cap is a fallback over independent weekly-assessment evidence, and it can complete the assessment only after every planned audit letter has at least one independent attempt; it cannot produce completed `0/0 independent` rows. Completed assessments are appended to `recentWeeklyAssessments` immediately, capped to the latest 12 completed assessments, and `weeklyIntroducedLetters` is cleared. The same completed `activeWeeklyAssessment` remains available for same-day "Play again" sessions so the day can continue as filler review without accidentally starting a new cycle. On the next local day, the planner clears the completed active assessment and starts a fresh Sunday cycle from that day. Legacy in-flight assessments without adaptive metadata keep their old evidence rules, but their visible target is capped at 40.

Parents can also skip an unfinished weekly test from the parent dashboard's ellipsis menu (`Skip current weekly test`). During an in-progress weekly test session, a parent can reach the same action by long-pressing the replay button for two seconds; `GameView` opens the parent gate and then archives the active assessment through `ProfileManager.skipActiveWeeklyAssessment(...)`. Skip does not delete the test: it completes the active assessment with the evidence collected so far, archives that partial snapshot in `recentWeeklyAssessments`, clears the resume checkpoint, clears the active weekly cycle, and starts a new cycle from the current local day. The next same-day play session can therefore be an ordinary introduction day and may introduce a new letter, while the partial test remains visible in the dashboard's **Weekly test** card and in **Diagnostics → Letter retention**.

Daily spotlight candidate selection also skips letters visually confusable with this week's set unless the related weekly letter is already strongly known. For example, if `B` was introduced this week and still lacks strong evidence, candidates like `D`, `P`, and `Q` are skipped for the rest of that cycle. This keeps the daily-variety promise without stacking visually similar new symbols too early.

The Sunday review/test is letter-specific. Reading-layer sessions are dormant, so the 25-round / adaptive review-test contract is the only daily contract the shipped app exposes.

#### Warm-up length adapts to sparse data

```
warmupPoolCount ≥ 6  →  planner returns 5-round warm-up
                ≥ 4  →  planner returns 3-round warm-up
                ≥ 3  →  planner returns 2-round warm-up
                < 3  →  planner returns no warm-up
```

`warmupPoolCount` is `knownLetters.count` because only letter sessions have an executable warm-up phase. The dormant syllable/word phases return `warmupLength = 0` in their planner branches and would start directly in `syllableRecognition`, `syllableCalibration`, or `wordReading` if they were ever reached.

A `SessionPlan` must be exactly executable by `AdaptiveGameState`: the planner does not promise a 2-round warm-up with only 2 known letters, and the dormant reading branches do not promise warm-ups the engine would skip.

`AdaptiveGameState.init` treats this as a developer contract too: debug assertions flag a letter plan that promises warm-up with fewer than 3 known letters, or any reading-layer plan that promises warm-up before a real reading warm-up phase exists.

### 4. Session end & "Play again"

[`SessionEndView`](Pismenka/Views/Summary/SummaryView.swift) (the file is named `SummaryView.swift` for project-history reasons but the type is `SessionEndView`) is **always celebratory**, regardless of how the session ended:

- Daily goal complete → "You did it!"
- Hearts depleted → "Nice try today!"
- Home tapped → "Great practicing!"
- Legacy fatigue checkpoint → "Great practicing!" only for old saved summaries; adaptive daily play no longer auto-ends because of mistakes while hearts remain.
- Parent-directed practice complete → "Practice complete!"

There is no "you lost" UX. Day-streak messaging is purely positive.

Two icon actions are offered:

- **Replay arrow** — same-day re-entry. Builds a fresh `previewSessionPlan`; `commitSessionStartIfNeeded` remains idempotent for the streak and the focus-active-day counter on the first real answer (see [Multi-session same-day contract](#multi-session-same-day-contract)).
- **House** — back to `ProfileSelectView`.

### 5. Parent dashboard

Holding a profile card → context menu → **View results** → parent gate → [`ParentDashboardView`](Pismenka/Views/Parent/ParentDashboardView.swift). The dashboard is deliberately built around two parent use cases — the **15-second glance** between sessions and the **5-minute audit** every week or two — and the layout is organized into three tiers so that both work without scrolling past content meant for the other:

```
Tier 1 — 15-second read       Tier 2 — 1-2 minute audit       Tier 3 — 5-minute deep dive
─────────────────────────     ─────────────────────────       ─────────────────────────
headerCard                    weeklyTestSummarySection        diagnosticsSection (collapsed)
recommendationCard            lettersSection                    ├─ letterRetentionListCard
needsAttentionSection         unitsProgressSection              ├─ weeklyAssessmentRoundsListCard
focusCard                                                       ├─ commonConfusionsListCard
progressGlanceCard                                              └─ rawRoundsListCard
```

#### Tier 1 — the 15-second read

This is what a parent sees in the time it takes to glance during a snack: identity, what to do today, what is on fire, and the four-bucket headline.

- **Header card** — avatar, `Alphabet: <level>` with badge, inline `info.circle` button that opens the glossary alert, day-streak chip (`flame.fill` plus `N-day streak`, or `No streak yet` for empty streaks), best-streak chip when it differs from current, and a `Best level:` row when the lifetime-best alphabet level is higher than the current one. The reading-stage chip described in older specs is not rendered in the current build because the reading layer is dormant. In `DEBUG` builds, long-pressing the header reveals the `AdaptiveDebugOverlay`.
- **Try this today (`recommendationCard`)** — one short recommendation line chosen from recent impulses, confusions, slow-but-correct letters, or the child's name. (The Czech CV readiness recommendation path lives in the dormant reading layer and is not exercised in the current release.)
- **Needs attention** — at-a-glance rows for letters or patterns that need follow-up: current needs-practice letters, recently slipped letters, weekly-test watch/review outcomes, and common confusions. Drawn from the same snapshot, weekly-assessment, and round-event fields the dashboard already uses everywhere else.
- **Today's focus card** — the current focus letter, the day count of practice, and a one-sentence explanation of why the engine picked it. (The card is typed to render slabiky/words as well; only letters surface today.)
- **Progress at a glance (`progressGlanceCard`)** — the four-bucket headline used by both the profile cards and the dashboard, in a single rich card:
  - Headline `<confidentlyKnown> / <totalLetters> confidently known` with a green linear progress bar.
  - 3-up stat tiles for **Likely known**, **Needs practice**, **Not introduced** (recently-slipped letters fold into Likely known, matching `parentLetterKnowledgeSummary`).
  - Below the divider, a `Total attempts` / `Overall accuracy` pair derived from `Profile.letterPracticeSummary` (target attempts only).
  - A single descriptive line that mirrors the row-level `Seen X · Tested Y` split so the headline and the per-letter rows agree.

#### Tier 2 — the 1-2 minute audit

The mid-density slice. A parent who is *checking in* — not debugging — gets the latest weekly test result, an actionable per-letter list, and reading progress when relevant.

- **Weekly test (`weeklyTestSummarySection`)** — latest weekly review/test summary. Title plus date, optional `Adaptive audit · N assessment rounds` line, a small `outcomeBadge` (`Retained` / `Review` / `Watch` / `Observed` / `Pending`), the new-letter confidence tile grid for the current cohort, and a 4-tile metric row counting **Retained / Review / Watch / Pending** where parent-marked `Observed` letters are folded into the Watch tile. A `Show per-letter rows` / `Hide per-letter rows` button reveals dense `independentCorrect/independentAttempts` rows per cohort letter with bucket label and average response time. The retention history, the round log, and the confusion pairs are no longer in this card — they live behind the diagnostics expander to keep Tier 2 calm. Partial test results from a parent-skipped weekly assessment also appear here.
- **Letters (`lettersSection`)** — every letter the child has interacted with, with header controls:
  - A `Menu` on the right of the section title cycles `LettersSortMode`: **Needs help first** (default), **Strongest first**, **A → Z**. Default puts problem letters at the top so a five-minute audit reaches them without scrolling past mastered ones.
  - For Czech profiles, a row of capsule filter chips selects `LettersCharsetFilter`: **All** (default), **Base** (drop diacritic letters), **Diacritic** (only diacritic letters). The filter is hidden for English profiles.
  - Letters are bucketed into knowledge groups in priority order: `Needs help`, `Getting there`, `Recently slipped`, `Practicing now` (the active focus), `Confident`, `Mastered`, `Marked known by parent`, `Reset by parent`, `Not yet seen`. The `strongestFirst` sort reverses that group order; `alphabetical` keeps the order but sorts letters within each group.
  - Each row is the same `LetterStatRow` as before:
    - The letter itself, color-coded by knowledge state.
    - Accuracy percentage, certainty percentage, and `EvidenceStrength` label (`Strong`, `Solid`, `Emerging`, `Not enough data`).
    - `Seen X · Tested Y` — distractor exposures vs target attempts, kept separate.
    - Confused-with badge, response-time pip, replay-needed flag, recently-slipped marker.
    - Optional "Marked known by parent" / "Reset by parent" badge for overridden letters.
    - **Per-letter context menu** with practice, override, reset, and parent-note actions.
- **Reading progress (`unitsProgressSection`)** — dormant in the current release (`EmptyView()` today). Designed to surface mastered slabiky/words plus recent syllable and word stats once the reading layer reactivates.

#### Tier 3 — the 5-minute deep dive

Everything raw is collapsed into a single expander so it never crowds the top of the screen. The expander only renders when there is something to show.

- **Diagnostics (`diagnosticsSection`)** — a single button card with title `Diagnostics` and subtitle `Retention, test rounds, confusions, raw history`. Tapping it unfolds:
  - **Letter retention** (`letterRetentionListCard`) — per-letter retention rolled across every *completed* weekly assessment in `recentWeeklyAssessments`, with an `Across N tests` count. Drawn from independent-evidence buckets only, so parent overrides don't leak in as "passed."
  - **Recent test rounds** (`weeklyAssessmentRoundsListCard`) — the last 50 `RoundEvent`s with `intent == .weeklyAssessment`, newest first. Each row shows `target → selected`, the intent label, response time, and any stacked `parentExplanations`.
  - **Common confusions** (`commonConfusionsListCard`) — top confused-with pairs once any pair reaches 3+ real confusions. Impulsive taps are excluded, so a single rage-tap doesn't show up as a "confusion."
  - **Raw round history** (`rawRoundsListCard`) — the most recent `RoundEvent`s with a `Show 30` / `Show all` toggle, capped to `RoundEvent.maxRetained`. Includes intent, response time, the `discounted` flag, and the full `parentExplanations` list per round.

#### Overflow menu, glossary, and notes

The toolbar's `ellipsis.circle` button opens a confirmation dialog with profile-level actions, in this order: **Edit profile**, **Sound settings**, **Add / Edit parent note**, **What do labels mean?** (opens the glossary alert), **Undo last reset** (when one is available), **Skip current weekly test** (only when an unfinished `activeWeeklyAssessment` exists — archives partial evidence and lets the next same-day session return to ordinary introduction flow), **Re-run calibration**, **Pick a new focus letter** (only when one is active), and **Reset day streak**. The granular reset operations described in [Granular resets](#granular-resets) are reached from this menu and from the per-letter row context menu.

The glossary is the single source of truth for parent-facing taxonomy and is reused everywhere a label appears. It documents both the four headline buckets (`Confidently known`, `Likely known`, `Needs practice`, `Not introduced`) and the per-letter knowledge states (`Needs help`, `Getting there`, `Recently slipped`, `Practicing now`, `Confident`, `Mastered`, plus the two override states). The header's inline `info.circle` and the ellipsis menu's `What do labels mean?` both open the same alert text, so a parent never has to guess how the summary tiles relate to the per-letter rows.

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

Four named evidence tiers:

- **`isKnown`** — ≥ 80% of the last 5 target attempts (minimum 2 attempts for letters). Drives `Profile.knownLetters`, warm-up, and ordinary review/distractor pools.
- **`isStrongKnown`** — at least 4 target attempts, ≥ 80% recent accuracy, and `EvidenceStrength >= .solid` (Wilson 95% lower bound ≥ 0.6, no longer multiplied by response speed). Drives strong accuracy evidence and backs ordinary easy slots.
- **`isFluentKnown`** — strong-known plus at least 4 timing samples with a fast median response. The single place response time matters: it earns a *positive* upgrade for the hardest roles (confusable-pair proof, mixed-case/visual-only traps, safest easy distractors). Slow medians never demote a letter out of `isStrongKnown` — they just fail to promote it to `isFluentKnown`. See [Asymmetric speed rule](#asymmetric-speed-rule).
- **`isFocusGraduated`** — ≥ 7/8 of the last 8 target attempts (minimum 8). Stricter; only the current focus needs to clear this bar to graduate and add itself to `everMasteredLetters`.

`UnitProgressStat` uses the same 80% of last-5 shape with a 3-attempt minimum for syllables and words.

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

The dashboard reads weekly-test evidence read-only from existing persisted state. The Tier 2 **Weekly test** card surfaces `activeWeeklyAssessment` (or the most recent completed entry from `recentWeeklyAssessments`) as a compact cohort tile grid plus a 4-tile retained/review/watch/pending summary. The dense per-cohort-letter rows live behind the card's `Show per-letter rows` expander. Per-letter retention rolled across every completed weekly assessment, the last 50 `RoundEvent`s filtered to `.weeklyAssessment`, common-confusion pairs, and the raw `RoundEvent` history all move out of the summary card and into the Tier 3 **Diagnostics** expander, so a parent doing a 15-second glance never has to scroll past row-by-row analytics.

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
recentlySlipped  ever mastered, but no longer currently known
focus            currently being drilled, regardless of stat
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

[`AlphabetLevel`](Pismenka/Models/SkillLevel.swift) and `ReadingStage` are separate tracks in the codebase. Only the alphabet track is active in the current release; `ReadingStage` exists as future-version scaffolding, and the numbers track is on the roadmap but not yet in the codebase.

```
Alphabet track (active, shipped):
Novice → Beginner → Intermediate → Advanced → Expert crown

Numbers track (planned next; NOT yet in the codebase):
(no enum yet — number recognition / counting / quantity work,
 scheduled to land before the Czech reading layer is re-activated)

Czech reading track (dormant; reading layer is silent in the current build,
expected to come back after numbers ship):
Locked → Syllable Starter → Reader → Word Builder → Storyteller
```

Alphabet levels use `Profile.everMasteredLetters`, a monotonic `Set` so a letter can't double-count if it graduates → demotes → re-graduates.

| Alphabet level | Requirement | Grid / case relationship | Confusion / case behavior | Badge |
|---|---:|---|---|---|
| Novice | 0–9 mastered letters | Usually 4 options; the live grid is still computed from known/strong-known evidence, not the trophy alone. | Gentle: similar-shape distractors avoided. | 🌱 |
| Beginner | 10–14 mastered letters | Trophy tier only; 6 options require the separate known-letter grid gate. | Safe fluent-known pairs: similar letters allowed only when both sides are accurate and quick. | 🌟 |
| Intermediate | 15–19 mastered letters | Often the first tier where the 6-option gate can be satisfied (`known ≥ 15`, `strong ≥ 10`). | Same as Beginner, with a larger known pool. | 🚀 |
| Advanced | 20+ but not all letters | Does not automatically mean 8 options; 8 requires about 85% of the active alphabet known plus a strong-known pool. | Intentional similar-shape practice; lowercase distractors and visual-only lookalikes can appear when fluent evidence allows them. | 🏆 |
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

- **`alphabetLevel`** — parent-facing alphabet progress derived from `everMasteredLetters`; monotonic during normal play, but can reset when progress is explicitly reset.
- **`instructionalBand`** — derived in `ProfileLearningSnapshot` from `strongKnownLetters ∩ everMasteredLetters`. It gates confusable-distractor policy, automatic lowercase targets/distractors, and visual-only distractors, and can sit below `alphabetLevel` after recent slips.
- **`letterOptionsPerRound` / `lastFrozenLetterOptionsPerRound`** — the live 4/6/8 grid-size gate. It promotes to 6 options at `known ≥ 15` and `strong ≥ 10`, promotes to 8 at `known ≥ max(20, ceil(0.85 * alphabetCount))` and `strong ≥ threshold - 3`, and uses the previous frozen session size for ±2 demotion hysteresis.
- **`highestAlphabetLevelEverReached`** — monotonic alphabet trophy; never decreases, never reset by `resetAllProgress`. Surfaces in the dashboard as `Best:` whenever it diverges from the current alphabet level.

An alphabet level-up celebration fires **at most once per profile per alphabet level**. The receipt is `Profile.celebratedAlphabetLevels: Set<AlphabetLevel>` — durable across sessions, preserved through resets, indifferent to any future demotion path.

The alphabet table is also the progression contract the tests check directly, but the engine splits difficulty-sensitive behavior: the frozen letter-grid size comes from `Profile.letterOptionsPerRound`, while the frozen `instructionalBand` controls confusable-distractor policy, automatic lowercase targets/distractors, and visual-only distractors. Dashboard badges and level-up celebrations keep reading `alphabetLevel` / `highestAlphabetLevelEverReached`; the reading-stage chip from older specs is not shown while the reading layer is dormant.

### Answer-grid sizing: 4 / 6 / 8 options

The answer-grid size is deliberately **not tied directly to `alphabetLevel`**. A child can be Beginner, Intermediate, Advanced, or Expert for trophy/dashboard purposes while the live grid is still decided by current known-letter evidence. The product behavior is:

```
newer / less certain profile  -> 4 options
more known + strong evidence  -> 6 options
near-whole alphabet evidence  -> 8 options
```

The live resolver is `Profile.letterOptionsPerRound`, implemented by `AlphabetLevel.letterOptionsPerRound(...)`. It uses two alphabet-scoped counts:

- `knownAlphabetLetterCount` — letters in `Profile.knownLetters`, which come from `LetterStat.effectiveIsKnown` (normally at least 80% over the last 5 target attempts with a 2-attempt minimum, plus parent `.markedKnown`; parent `.reset` removes the letter). The current focus letter is excluded until it graduates unless the parent explicitly marked it known.
- `strongKnownAlphabetLetterCount` — letters in `Profile.strongKnownLetters`, which require at least 4 target attempts, at least 80% recent accuracy, and `EvidenceStrength >= .solid`. Parent `.markedKnown` does not synthesize strong evidence.

Promotion thresholds:

| Grid | Required evidence |
|---:|---|
| 4 options | Default while the wider-grid gates are not satisfied. |
| 6 options | `knownAlphabetLetterCount >= 15` **and** `strongKnownAlphabetLetterCount >= 10`. |
| 8 options | `knownAlphabetLetterCount >= max(20, ceil(0.85 * alphabetCount))` **and** `strongKnownAlphabetLetterCount >= thatThreshold - 3`. English (26 letters) means 23 known / 20 strong. Czech (41 letters) means 35 known / 32 strong. |

Session behavior:

- The base grid is frozen at `GameView` / `AdaptiveGameState` init as `frozenLetterOptionsPerRound`, so a letter becoming known or slipping during a session does not resize the grid mid-run.
- `Profile.lastFrozenLetterOptionsPerRound` stores the previous session's frozen grid. It gives demotion hysteresis: once a 6- or 8-option grid is earned, one slipped letter should not immediately shrink the next session.
- `instructionalBand` is separate. It gates similar-shape distractors, lowercase behavior, and visual-only lookalikes; it does not directly choose 4 vs 6 vs 8.
- `LiveDifficulty == .easierUntilStreak` can temporarily downshift the frozen letter grid by one tier per governor step (`8 -> 6 -> 4`, `6 -> 4`), floored at 4, while the child is struggling.
- Reading-layer slabika/word sessions are designed to stay at 4 options, but that layer is dormant in the current release.

### Daily spotlight, durable focus & scaffolding ladder

In the letter layer, the game now separates **daily variety** from **long-lived remediation**:

| Concept | Stored on | Meaning |
|---|---|---|
| Durable focus | `Profile.currentFocusLetter` plus `focusStartedDay` / `focusPracticedDays` | The letter the child is truly working through over multiple days, including scaffolding, remediation, graduation, and stuck-focus pause logic. |
| Daily spotlight | `SessionPlan.dailySpotlightLetter` | Today's fresh introduction for variety and the Sunday-anchored weekly review/test. It can be drilled for the session without clearing an in-flight durable focus. |
| Introduced focus target | `SessionPlan.introducedFocusTarget` | The exact letter, syllable, or word just introduced today. `GameView` uses this for the "New letter today!" overlay so the UI promise always matches the unit the session intends to teach. |
| Review/test plan set | `SessionPlan.weeklyReviewLetters` | Ordered audit letters for the current adaptive review/test plan. |
| Frozen assessment cohort | `Profile.activeWeeklyAssessment.cohortLetters` | The exact letters being measured for retained/watch/review outcomes during the committed review/test day. |

This distinction is important. A daily new letter should not erase `FocusTeachingMode`, `focusActiveDays`, remediation, or paused-focus state. If the child is in remediation, the durable focus continues to drive drilling. Otherwise, an introduction day may use the daily spotlight as the active drill focus while keeping `currentFocusLetter` persisted for the longer learning arc.

The UI contract is intentionally explicit: when `introducedNewFocusLetter == true`, the overlay displays `introducedFocusTarget?.displayText` first, then falls back to older plan fields only for legacy decoded checkpoints. It must not prefer `focusTarget` over the spotlight, because `focusTarget` can still represent the old durable focus while `dailySpotlightLetter` is the unit newly introduced today.

The durable focus is picked by the shared prerequisite-aware helper behind `Profile.snapshot.nextFocusCandidate`. The daily spotlight uses a related but stricter selection path: it avoids already introduced letters, paused focus letters, the current weekly set, and unsafe weekly confusables. Reading sessions are typed via `FocusTarget` (see below) but do not run in the current release and therefore do not participate in the letter-only weekly assessment store.

The picker prefers:

- Stale introduced weaknesses that need re-teaching.
- Letters whose visually confusing prerequisites are mastered.
- Letters with enough known/learning distractors to teach safely.
- Letters not visually similar to currently weak letters.
- A tagged fallback when no candidate satisfies all readiness checks.

For Czech, diacritic variants are gated by `LetterDifficulty.diacriticBase`: `C` must be mastered before `Č`, `E` before `É` / `Ě`, and so on. The selected reason is persisted in `lastFocusSelection` for the parent dashboard.

When the profile's `instructionalBand` allows automatic lowercase targets, lowercase focus targets are introduced after the uppercase alphabet is mastered, even if the parent never changed the case-practice setting. `LetterDifficulty.isEligibleTarget(...)` is the central target gate: visual-only lookalikes such as `1` and `rn` are never eligible focus, mastery, or level-progress targets.

A letter may have appeared earlier as a cameo distractor. That low-pressure glyph exposure is useful, but it does **not** add the letter to `introducedLetters`, does not make it a focus candidate sooner by itself, and does not count as a target attempt.

For a letter-layer introduction day, round generation has two guardrails around the newly introduced spotlight:

- Warm-up only uses known letters and explicitly keeps the active focus/spotlight out of the option grid, so the new letter is not introduced as an unexplained wrong choice.
- Once drill begins, the spotlight is the active drill focus unless remediation is overriding it. The engine injects it as the target or as a distractor exposure, and `firstFocusAppearanceDeadline` forces it as a target by the second drill round if random target selection has not done so already. The regression contract for a full 25-round introduction session is at least three on-screen appearances and at least one target prompt for the introduced spotlight.

For durable letter-focus sessions, `FocusTeachingMode` determines the effective scaffolding. The teaching mode is `.scaffolded` for `focusActiveDays ≤ 2` and `.normal` afterward; remediation overrides both. Translated into per-round shape (with the standard 4-option Novice grid as the worked example):

| Day of practice | Teaching mode | `effectiveScaffoldingLevel` | Distractors when focus is the target | Confusion policy |
|---|---|---:|---|---|
| Day 1 | `scaffolded` | 3 | Easy slots try `strongKnownLetters` first, then fall back to ordinary known letters (easy elimination) | `avoid` |
| Day 2 | `scaffolded` | 3 | Same as Day 1 — all easy slots | `avoid` |
| Day 3 | `normal` | 1 | 1 easy slot + the rest from normal known letters | `allowFluentPairs` (B/D-type pairs OK if **both** are fluent-known) |
| Day 4+ | `normal` | 0 | All slots from normal known letters | `allowFluentPairs` |

At wider grids (6 or 8 options) the easy count is capped by `effectiveScaffoldingLevel`, and the remaining slots are drawn from the normal known pool under the listed confusion policy.

`focusActiveDays` is a **derived** count — `focusPracticedDays.count` — where `focusPracticedDays` is a `Set<LocalDay>`. Set semantics make multi-session-same-day inserts idempotent (multiple "Play again" taps don't bump the ladder twice in one day) and the ladder is recoverable after a crash from the persisted set alone. Remediation forces `effectiveScaffoldingLevel = 3` from the mode; it does not fake the day count.

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

Syllable focus sessions use `SyllableCurriculum.DistractorStage` instead of `FocusTeachingMode`: focus days 0–1 use consonant-only contrasts, day 2 adds short-vowel contrasts, and day 3+ may reserve one heard length contrast. Word focus sessions use the session's audio-filtered `WordCurriculum.playableWords` pool and `WordCurriculum.distractors(for:candidates:profile:count:)` to prefer words with the same syllable count without selecting unplayable options.

A letter focus graduates when `isFocusGraduated` flips on a target-attempt round. On graduation:

- `currentFocusLetter` clears.
- `everMasteredLetters` grows by one.
- The graduation also **consumes today's formal-introduction quota** (sets the legacy-named `lastNewLetterDay = today`), so a same-day "Play again" doesn't silently introduce a fresh spotlight/focus. The next calendar day picks the next one.
- If this graduation completes the whole alphabet, the current session stays in celebration/letter review; it does **not** interrupt the child with syllable calibration mid-session.

### Czech reading progression (dormant scaffolding)

The Czech syllable and word layers are not reachable in the current release; this section documents the still-present scaffolding so future work can re-activate it without rediscovering the design. `ProfileManager.previewSessionPlan(...)` explicitly nils `syllablesUnlockedAt`, `wordsUnlockedAt`, `currentSyllableFocus`, and `currentWordFocus` and hard-codes `primaryLayer = .letters`, so none of the gates below currently fire.

Czech reading is represented by typed learning units in [`LearningUnit.swift`](Pismenka/Models/LearningUnit.swift):

```
FocusTarget.letter("A")
FocusTarget.syllable("MA")
FocusTarget.word("MÁMA")
```

`FocusTarget.storageKey` prefixes persisted event keys (`letter:A`, `syllable:MA`, `word:MÁMA`) so a letter, syllable, and word can never collide in `RoundEvent` or checkpoints. Letter storage remains backward-compatible for existing bare keys such as `"A"` and `"A|lower"`.

The designed reading curriculum is Czech-only. English profiles that reach Expert remain in Expert letter maintenance, and so do Czech profiles in the current release. The UI frames this positively as "letter expert practice", not as a locked or broken reading path.

- [`SyllableCurriculum`](Pismenka/Models/SyllableCurriculum.swift) seeds 50 open CV slabiky from `M/L/S/P/T × A/E/I/O/U`, then long-vowel variants such as `MÁ`, `LÉ`, `SÍ`.
- Short syllables depend on their component letters being mastered. The current dormant code also requires `profile.hasCompletedAlphabetForReading` before syllable-layer eligibility; the older early-CV-bridge-before-full-alphabet gate is not implemented in this branch.
- Long-vowel syllables depend on the matching short syllable being known, e.g. `MÁ` requires `MA`.
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
2. Czech profiles see one short teaser on the end screen: "Zítra budeme skládat písmenka do slabik."
3. No syllable onboarding or calibration starts in that same session, and same-day **Play again** stays in letter maintenance. This prevents a hard cognitive shift immediately after the unlock moment.
4. On the next eligible calendar day (`today > syllablesUnlockedAt`), if `readingPracticePaused == false`, `GameView` opens with a non-scored syllable onboarding overlay before the first round. The overlay demonstrates `M + A → MA`; a future reading release would play `AudioService.playSyllable("MA", ...)` once matching `cz_syl_<key>.m4a` assets are intentionally promoted back into the required reading-audio surface.
5. The first real answer after the overlay calls `commitSessionStartIfNeeded`; merely viewing the overlay does not update streaks or focus-day counters.
6. A 12-round syllable calibration follows, using short CV slabiky only and no length contrasts. Completing calibration sets both `hasCompletedSyllableOnboarding = true` and `hasCompletedSyllableCalibration = true`; dismissing only the overlay does not persist onboarding completion, so the overlay can reappear if the child exits before calibration completes.

If the parent enables `readingPracticePaused` before that next session, the profile stays in letter-only practice. Resuming later continues the onboarding/calibration path until calibration completes.

Current daily-session routing is sequential:

```
letters → Expert crown / full alphabet → next-day syllable onboarding → syllableCalibration → syllableRecognition/blending → wordReading/building
```

The router now schedules the modeled production activities: roughly every fifth eligible syllable round becomes `syllableBlending`, and roughly every fifth eligible word round becomes `wordBuilding`. The word onboarding/calibration flags are persisted but currently reserved; the router enters `wordReading` / `wordBuilding` when words unlock.

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

### Distractor selection (`DistractorTier`)

Sparse known-letter pools are a real problem early on (a brand-new profile may have 1 known letter after calibration). The `DistractorTier` enum codifies a deterministic fallback in [`AdaptiveGameState.pickFiltered`](Pismenka/Models/GameState.swift):

```
fluentKnown → strongKnown → ordinaryKnown → parentMarkedKnownButUnverified → caseVariant → attempted → calibrationPool → otherIntroduced → visualOnly → unintroduced
```

Higher tiers are exhausted before lower ones are touched. `fluentKnown` provides the hardest safe distractors, `strongKnown` provides reliable easy/ordinary distractors, `ordinaryKnown` keeps the gentle known pool available, and `parentMarkedKnownButUnverified` is a capped fallback only. Parent-marked but system-unverified letters do not satisfy hard-role proof. `caseVariant` is used for automatic high-band uppercase/lowercase mixing. `visualOnly` contains non-letter lookalikes (`1`, `rn`) that can appear only when the frozen instructional band allows visual-only distractors and the target has fluent evidence; visual-only tokens never create target stats or exposure stats.

Reaching the bottom tier means an unintroduced letter was about to be exposed — the app **counts the leak** (`unintroducedExposuresThisSession`) so it's auditable, but the round still completes (we'd rather show a never-seen letter than crash). In practice this only happens in pathological sparse cases.

### Cameo letters

Cameo letters are intentional, low-stakes future-letter appearances. They make letter review feel fresher without changing the learning contract:

- A cameo can only replace one existing ordinary distractor slot; it never increases the band/eased 4/6/8 option count.
- A cameo is never the prompted target and never replaces the active focus distractor in drill rounds.
- A cameo records only distractor exposure (`distractorExposures` / `lastSeenAt`), not `targetAttempts`, `targetCorrect`, mastery, or `introducedLetters`.
- The daily budget is capped per profile/local day by `Profile.dailyCameoExposureLimit` (currently 3), using `cameoExposureDay` and `cameoExposuresToday`. Same-day **Play again** keeps using the same budget.
- The budget is spent only when the child answers and the exposure is actually recorded through `ProfileManager.recordCameoExposure(...)`; building a round and exiting does not consume a cameo.
- If a future letter from the child's typed name is otherwise eligible, it is preferred as the cameo so the app creates a gentle print/name connection without making name letters count as mastered.

Eligibility is deliberately conservative. Cameos are available only in letter review/maintenance and in focus drill rounds where the target is already known, the focus is shown as a distractor, and `helloFocus` has already been earned. They are disabled for warm-up, rescue, remediation, syllables, words, and eased `LiveDifficulty`.

Candidate letters come from `LetterDifficulty.introductionOrder(for:)`, but are filtered to future target letters only: not formally introduced, not known, not visual-only (`1`, `rn`), not visually confusable with the current target or focus, and not a Czech diacritic unless its base letter is already known. Among eligible candidates, the game prefers the one with the fewest prior distractor exposures so cameos rotate instead of repeating the same future letter.

This preserves three distinct concepts for maintainers:

- **Formal introduction** — a unit was assigned as focus or target; grows `introducedLetters` / `introducedSyllables` / `introducedWords`.
- **Intentional cameo** — a future letter appeared as a distractor under the daily cap; grows only exposure counters and cameo budget.
- **Accidental leak** — the fallback distractor tier had to use an unintroduced letter; increments `unintroducedExposuresThisSession` for auditing.

### Visually confusing pairs (`ConfusionPolicy`)

`LetterDifficulty.visuallyConfusingPairs` defines symmetric letter-to-letter pairs like B/D, M/W, P/Q, lowercase b/d, and structural pairs such as E/F or P/R/B. Directional non-letter lookalikes live separately in `visualOnlyDistractorsByTarget`: for example, `1` can be a distractor for `I` / `L`, and `rn` can be a distractor for `m`, but those tokens can never become targets themselves.

The treatment is **phase- and band-dependent** via `LetterDifficulty.ConfusionPolicy` plus the frozen `instructionalBand.confusionStage`:

| Policy | When | What it does |
|---|---|---|
| `.avoid` | Calibration; warm-up; rescue rounds; focus drill days 1–2 | Never picks a confusable distractor for the given target. |
| `.allowFluentPairs` | Focus drill day 3+ | Confusables OK only when **both** the target **and** the candidate are in `fluentKnownLetters`. Parent `.markedKnown` overrides do not satisfy this tier by themselves, and fallback filling keeps this legality filter. |
| `.intentionallyPractice` | Advanced+ instructional-band review of a fluent-known letter | Same fluent-known legality as `.allowFluentPairs`, but eligible confusables are pulled to the **front** of each tier's pool — explicit discrimination training (B/D, M/W, mixed-case pairs, etc.). |

Similar-shape reservation is probabilistic, not hard-coded into every round: advanced instructional-band review attempts to seed one similar option about 80% of eligible rounds, preserving round-to-round variety.

This lets the app shield struggling kids early and deliberately train discrimination later, without two parallel game modes. The `instructionalBand` gate dominates history: even if a profile has `confusedWith` evidence, those pairs are not surfaced until the frozen session band allows them.

### Round generation & answer-position fairness

Letter rounds show the session's frozen `letterOptionsPerRound`: 4 options by default, 6 once the known-letter and strong-known pools are large enough, and 8 once the child has about 85% of the active alphabet known with enough strong evidence. That grid size is persisted as `Profile.lastFrozenLetterOptionsPerRound` so the next session can apply ±2 demotion hysteresis instead of flickering after one slipped letter. Reading-layer sessions intentionally stay at 4 choices because the early slabika/word curricula and unlock gates are built around a 1+3 option shape. When `LiveDifficulty == .easierUntilStreak`, each `governorEaseSteps` value downshifts the frozen letter grid by one tier (8→6→4, 6→4), floored at 4; rescue rounds follow the same eased count. Naive shuffling produces patterns toddlers exploit (correct answer always top-left, etc.). `AdaptiveGameState.placeAnswer(target:distractors:isFocusTarget:)` enforces:

- **No same correct position 3+ times in a row.** Rolling `recentCorrectPositions: [Int]` window, last 2.
- **Even distribution across the session.** `sessionCorrectPositionCounts: [Int]` — preference rotates toward the least-used slot when ties allow.
- **Focus target slot rotates.** `recentFocusCorrectPositions: [Int]` ensures a brand-new focus unit doesn't get parked in the same slot every drill round, which would let the child memorize position instead of symbol shape.

`sessionCorrectPositionCounts` resizes with the current activity's option count, so a live-difficulty downshift or a 4-choice reading round can change the grid without corrupting position history. Both the base letter-grid size and the `instructionalBand` are frozen at session start, so level/evidence changes during a session do not silently resize the grid or unlock harder distractor behavior.

Weekly review/test sessions are intentionally routed through `plainReview`, even for Expert profiles, so the adaptive audit stays separate from ordinary Expert `maintenance`. The detailed evidence-ordering and conservative distractor rules live in [Weekly Sunday Review/Test](#weekly-sunday-reviewtest).

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
- `alphabetLevel`, `readingStage` — separate computed progress tracks; only the alphabet track is surfaced in the current UI.
- `learningLetters`, `unseenLetters`, `recentlySlipped` — dashboard and picker support pools.
- `unseenSyllables`, `unseenWords` — curriculum-derived unseen pools.
- `lettersByConfidence` — Wilson-only certainty ordering for parent display and easy distractors. No response-time discount: slow correct answers are still correct, and the right place to reward fluency is the additive `isFluentKnown` tier, not a subtractive penalty here.
- `lettersByReviewPriority` — warm-up/maintenance target ordering: `0.6*weakness + 0.4*staleness`. Slowness used to be a third 0.2 term but was removed — for a distractible 3-year-old, "slow on this letter" is mostly distraction noise rather than weakness, and drilling a known-but-slow letter at the expense of an actually-weak letter wasted practice time.
- `instructionalBand` — engine distractor/case band derived from `strongKnownLetters ∩ everMasteredLetters`; reading mastery does not raise this letter-session band in the current code.
- `currentFocusTarget`, `nextFocusTarget` — typed focus state at the API edge, currently populated only for letters while the reading layer is dormant. The method signature still carries the future word-audio hook, but the current implementation returns a letter target or `nil` rather than synthesizing syllable/word previews.
- `nextFocusCandidate` — letter-only preview retained for existing consumers; it is populated from the same prerequisite-aware letter picker used for focus selection.

The `instructionalBand` is computed from `strongKnownLetters ∩ everMasteredLetters`, floored at `.novice`. It is never stored on `Profile`; `AdaptiveGameState.init` freezes the snapshot value for the session and persists that frozen value in `GameEngineSnapshot` so a restored checkpoint keeps the same distractor/case band it started with. The separate base answer-grid size is `Profile.letterOptionsPerRound`; it is frozen into the game state, saved to `GameEngineSnapshot.letterOptionsPerRound`, and recorded back to `Profile.lastFrozenLetterOptionsPerRound` for the next session's hysteresis.

This prevents mismatches like "the dashboard says A is mastered but the game keeps drilling A."

### Hearts (5)

Every non-impulsive wrong answer consumes one heart. The impulsive-tap threshold is adaptive: `medianCorrectResponseTime * 0.35`, clamped between 0.35s and 0.9s, with 0.5s as the sparse-data fallback. These constants are heuristic tuning values from product judgment, not measurements from real children; they should be treated as provisional until validated. A tap faster than that after the grid appears is classified as `MistakeType.impulsiveTap` by `AdaptiveGameState`: it is logged and visible, but it does not count as a true learning miss and does not cost a heart. Assisted mastery-discounted attempts are the exception to the impulse shortcut: rescue/revealed wrong answers are persisted as `.confusion` even if fast, remain discounted from mastery via `AttemptContext`, and still cost a heart / feed `LiveDifficulty` like a real miss. This is intentional: once the child is in a helper path, repeated wrong taps are treated as struggle, not accidental exploration.

Hearts pace one sitting; daily-goal persistence is defined in [Daily goal, Winner button, and progress strip](#daily-goal-winner-button-and-progress-strip).

### Attempt contexts & assisted discount

`RoundEvent.AttemptContext` explains whether a tap was independent practice or happened inside a helper path:

| Context | Source | Counts for mastery? | Wrong-answer routing |
|---|---|---|---|
| `.independent` | Ordinary round | Yes | `recordConfusion` / heart loss |
| `.immediateRescue` | First easy retry after a miss | No | `recordConfusion`, heart loss, affects `LiveDifficulty` / rescue flow |
| `.delayedRescue` | Mid-difficulty retry 2–3 rounds later | No, but may count toward a separate recovery diagnostic | `recordConfusion`, heart loss |
| `.revealed` | Second-miss reveal/highlight path | No | `recordConfusion`, heart loss, affects `LiveDifficulty` / rescue flow |
| `.extraPractice` | Parent-directed practice | Yes | Normal answer semantics |

`AttemptContext.isAssistedForMastery` is true for `.immediateRescue`, `.delayedRescue`, and `.revealed`. Those attempts still create a `RoundEvent` and update exposure/replay/diagnostic fields, but they do not append fresh `recentResults` or increment `targetAttempts`; the original independent miss already recorded the mastery evidence. If a delayed rescue is also revealed, `.revealed` wins because the highlight made the attempt assisted.

`RoundEvent.wasDiscounted` is true whenever learning stats were discounted, whether the reason was an impulsive tap or assisted practice. Parent explanations distinguish those cases: impulse copy says it was an impulsive tap; assisted copy says the child was helped after a miss and the attempt was not counted as independent practice.

Weekly assessment evidence uses an even narrower gate than the visible daily bar: the attempt must be a `.weeklyAssessment` target round from adaptive daily play, `AttemptContext == .independent`, and not discounted for impulse. That means the review/test progress strip can advance on helper-path or filler rounds, but `WeeklyAssessmentLetterResult.independentAttempts` advances only on unassisted recognition during true audit rounds.

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

The contract is documented inline on `ProfileManager.previewSessionPlan` and `AdaptiveGameState.commitSessionStartIfNeeded`. There is no public `startSessionIfNeeded` API; if an internal helper with that name exists, it must delegate to the preview/commit split.

| Concern | Behavior across same-day sessions |
|---|---|
| Target attempts | **Count, every session** (`recordAnswer` is session-agnostic) |
| Distractor exposures | **Count, every session** |
| Cameo exposures | **Count only up to the daily cameo cap** (`cameoExposuresToday`; same-day replay does not reset it) |
| Focus graduation | **Can happen, any session** |
| Reading unlock | **Can be recorded mid-session**, but onboarding/calibration starts no earlier than the next eligible calendar day |
| Daily spotlight / new focus unit | **At most one formal introduction per calendar day** (graduation also consumes the day's quota); spotlight introduction does not wipe an unrelated durable focus |
| Daily goal count | **Persists across same-day sessions** through `dailyPracticeDay` / `dailyPracticeAttempts`; only adaptive-daily target rounds advance it |
| Weekly assessment | **Persists across same-day review/test sessions** through `activeWeeklyAssessment`; a naturally completed assessment remains active until the next local day, while a parent-skipped assessment is archived immediately and clears the way for a same-day introduction session |
| Day streak | **Unchanged** on same-day re-entry |
| `focusActiveDays` | **Unchanged** — `Set<LocalDay>` insertion is idempotent |
| Stamps | **Session-local** — fresh card per `GameView` lifetime |
| Parent dashboard | **Updates live** as rounds happen |

Net effect: a child can play 1 / 3 / 10 sessions on a single day, keep accruing real attempts, may graduate the active focus, but won't inflate the day streak, won't earn extra "active days" on the scaffolding ladder, won't be served a second formal spotlight/focus introduction beyond the day's quota, and won't get unlimited cameo letters through repeated same-day sessions.

### Adaptive struggle response

Mistakes no longer end adaptive daily or weekly review/test sessions by themselves. The child keeps playing until they tap Winner, leave with Home, or lose all hearts. Older checkpoints that contain the legacy `tiredSignal` value are ignored on restore when hearts remain, so a stale saved session cannot immediately jump to the summary screen.

Struggle still adapts the next rounds. The session difficulty governor trips when the child gets 3 of the last 4 wrong, drops to 2 hearts or fewer, or shows low focus accuracy after the session is underway. While eased, the app avoids confusing distractors, halves focus-target pressure, downshifts option count by one band, prefers known-letter distractors, and drains rescue retries sooner. Two consecutive correct answers restore normal difficulty.

### Adaptive signals & feedback loops

The app records both aggregate learning stats and a local rolling round narrative.

`LetterStat` and reading `UnitProgressStat` track:

- `targetAttempts`, `targetCorrect`, `distractorExposures`, `lastSeenAt`, `lastTestedAt`
- `confusedWith` for real confusions and `impulsiveSelections` for instant taps
- `promptReplayCount`, `recentResponseTimes`, `medianResponseTime`, `responseTimeBucket`. Response-time recording uses an **asymmetric speed rule** — see [Asymmetric speed rule](#asymmetric-speed-rule) below.
- `wasKnownBefore` and `demotedAt` for recently slipped letters
- `reviewPriority` for stale/weak review ordering. `LetterStat` uses `0.6*weakness + 0.4*staleness`; dormant reading `UnitProgressStat` currently uses `0.7*weakness + 0.3*staleness`. Neither uses a slowness term.
- `EvidenceStrength` (`notEnoughData`, `emerging`, `solid`, `strong`) so the parent dashboard does not overtrust 1/1 = 100%

#### Asymmetric speed rule

A 3-year-old's response time is asymmetric evidence: a fast correct tap (< 1.5 s) is strong proof of recognition, but a slow tap could just as easily be a distraction event (kid looked away, parent talked nearby, set the phone down) as actual slow recall. We treat it that way:

- `recordTargetAttempt` drops any response time at or above `LetterStat.distractionResponseCutoff` (5.0 s) from the rolling response-time window. The accuracy signal still updates — the answer they eventually gave still counts toward `recentResults`, `targetAttempts`, and `targetCorrect` — but the time itself is treated as noise and never enters the median.
- `certaintyScore` is now pure Wilson 95% lower bound. A slow correct answer never demotes certainty below an identical-accuracy fast answer. This brings `LetterStat` in line with `UnitProgressStat`, which always computed pure Wilson.
- `confidenceScore` (game-side strength ordering and certainty tiebreaker) is pure recent/lifetime accuracy blend, no speed multiplier.
- `reviewPriority` no longer includes the slowness term (was 0.2 weight).
- Speed only ever earns a *positive* upgrade via `isFluentKnown` (strong-known plus ≥ 4 samples with fast median). That tier still gates the hardest distractor roles, mixed-case work, and visual-only traps — the places where genuinely automatic recognition matters.

The net effect: a distractible child who knows their letters is no longer silently penalized for the natural attention drift of their age, and the parent-facing "Confidently known" headline no longer fluctuates because of toddler latency noise. The previous design discovered the problem the hard way: a child at 91% lifetime accuracy across 779 attempts showed only 11/41 letters as confidently known, primarily because slow-but-correct answers were being treated as evidence-against rather than evidence-for.

`WeeklyLetterAssessment` is a separate persisted diagnostic snapshot for the Sunday adaptive review/test. It deliberately does not try to infer retention later from aggregate `LetterStat`, because aggregate stats mix calibration, ordinary drill, rescue, cameos, and historical attempts. The assessment stores:

- `scheduledFor` — the Sunday date the test was due.
- `startedOn` — the local day the child actually started it, which may be Sunday or the next played day.
- `cohortLetters` — the frozen ordered audit set.
- `strategy`, `assessmentRoundTarget`, `dailyGoalTarget`, `hardRoundCap` — legacy-vs-adaptive shape and frozen progress/cap numbers.
- `results` — one `WeeklyAssessmentLetterResult` per audit letter, each with bucket, planned attempts, extension allowance, independent attempts, independent correct count, and response-time samples.
- `completedOn` — set when the adaptive audit resolves, when the independent-evidence hard cap is reached after every planned letter has at least one independent attempt, or when a parent explicitly skips the unfinished test and archives the partial result.

The outcome helper reports `.pending`, `.retained`, `.watch`, `.observed`, or `.needsReview` according to the frozen bucket. Legacy decoded assessments default to the previous 4-attempt, 3-correct rule, so in-flight old tests remain readable and finish under their original contract.

`RoundEvent` keeps the last 200 local-only events per profile. Each event stores target, displayed options, selected answer, correctness, response time, phase, `RoundIntent`, optional `unitKind`, optional `activityKind`, mistake type, replay count, discount status, optional `AttemptContext`, optional `cameoLetter`, `includedFocusAsDistractor`, optional `RoundPlanReason`, hearts after the answer, `LiveDifficulty`, and rescue metadata. There is deliberately no `RoundIntent.cameoExposure`: intent remains the primary pedagogical purpose, while cameo and focus-as-distractor are orthogonal flags so a single round can carry both signals.

`RoundIntent.weeklyAssessment` marks adaptive audit evidence rounds. `RoundPlanReason` is the machine-readable debug payload for generated rounds: primary goal, target source, distractor policy, and expected difficulty. It is not parent copy; it exists so tests and future simulation tooling can assert why the adaptive engine made a round. Weekly assessment rounds use `RoundPrimaryGoal.weeklyAssessment`; audit targets use `RoundTargetSource.weeklyAssessmentCohort`.

Parent rows derive plural `parentExplanations` from that data in priority order: discount/impulse explanations first, then cameo/focus exposure notes, then fallback round-purpose notes such as contrast-pair, stale-review, or weekly-assessment evidence. That order lets a single round honestly say both "helped after a miss; not counted as independent practice" and "M appeared as a preview", while keeping parent-trust-critical discount copy first. Legacy events with `intent == .focusDistractorExposure` still produce the focus-distractor note even when the newer boolean field is absent.

For letter sessions, `FocusTeachingMode` is the game-side strategy switch for durable focus/remediation:

- `scaffolded` — early focus days, max easy-elimination help.
- `normal` — standard scaffolding fade.
- `remediation` — stuck focus (`focusActiveDays >= 5` and recent accuracy < 50%): max scaffolding (`3`, deliberately not `0`), lower focus-target pressure, and pre-seeded rescue retries. Clears when recent accuracy reaches 60%. If the same focus reaches `focusActiveDays >= 8` and is still below 50%, the focus is paused in `pausedFocusLetters`, the daily new-focus quota is consumed, and the picker moves to easier review/prerequisites on a later session.
- `contrast` — explicit confused-pair discrimination round.
- `maintenance` — expert no-focus mixed review.

Paused focus letters are skipped for 7 local days via `pausedFocusLetterDays`, or until a parent reset/override reopens that letter. After the cooldown, the letter can re-enter the picker if its prerequisites and recent confusion signals make it a safe candidate again.

Repetition is intentionally tuned down compared with the older focus-heavy loop. Focus-target chance is lower in scaffolded/normal modes, recent target letters are remembered so the same symbol is less likely to appear immediately again, and ordinary rescue retries are spaced by at least one round when possible. Daily spotlight adds visible variety, while the Sunday review/test gives a structured retention checkpoint without clearing durable remediation pressure for letters that genuinely need it.

Audio feedback also participates in the model. Replaying the prompt increments `promptReplayCount`. Tap replays the current target prompt at normal speed. On weekly review/test days, a two-second long-press on the replay button opens the parent gate so a parent can skip/end the active weekly test early (same archive semantics as **Skip current weekly test** in the dashboard). `AudioService.playLetterSlow(..., rate: 0.7)` exists for future tuning but is not wired in the current UI. On a second miss of the same letter in one session, the correct tile enters a reveal state, pulses, and replays the target prompt before the next round.

---

## Parent controls

### Case practice

The settings screen labels lowercase behavior as **Case practice**. The default option is **Automatic at high levels**: the game stays uppercase-first for early learners, then high instructional bands can mix lowercase automatically. This avoids a misleading "off" toggle now that case mixing is part of the level progression.

Other options (`Lowercase after uppercase`, `Mixed case after both`) are still persisted for compatibility and future tuning, but the high-level automatic path is explicit in the UI copy.

### Parent gate

`ParentGateView` requires a parent gesture before any destructive or configuration action. The default is a swipe-up drag; settings can switch the gate to an accessible hold-two-buttons method. It guards:

- Creating new profiles
- Opening the parent dashboard (hold a profile card → context menu → **View results**)
- Editing a profile (hold a profile card → context menu → **Edit profile**)
- Resetting / deleting profiles
- Skipping an unfinished weekly review/test (dashboard ellipsis menu, or a two-second long-press on the in-game replay button during a weekly test session)
- Audio settings

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

Overrides are set/cleared from the per-letter context menu in the dashboard. Setting any override clears that letter from the paused-focus cooldown. If a parent marks the **current** focus as known, `ProfileManager.setLetterOverride(...)` also clears the focus and matching `lastFocusSelection` so the next session can pick a fresh letter without pretending the override was earned mastery.

### Granular resets

Five reset operations on `ProfileManager`, smallest blast radius first. Each is documented in code with its exact preserved/cleared field set:

| Operation | Wipes | Preserves |
|---|---|---|
| `resetCalibrationOnly` | `hasCompletedCalibration` flag | All letter/syllable/word stats, focus, streak, trophies |
| `resetCurrentFocus` | `currentFocusLetter`, `currentSyllableFocus`, `currentWordFocus`, `focusStartedDay`, `focusPracticedDays`, `lastFocusSelection` | Letter/syllable/word stats, `lastNewLetterDay`, streak |
| `resetLetterStats(letter:)` | One letter's `LetterStat` (counters, timestamps, override); removes it from `everMasteredLetters`, `introducedLetters`, and paused-focus cooldown state; clears focus if it **was** the focus; clears `lastFocusSelection` if it described that letter | Other letters, streak, calibration, lifetime trophy fields |
| `resetStreak` | `dailyStreakCount`, `lastSessionDay` | `bestDailyStreak`, all learning stats, focus |
| `resetAllProgress` | All learning history across letters/slabiky/words, calibration, unlock flags, focus, weekly assessment state/history, streak, mastery sets, introduced sets, paused-focus state, focus-selection reason, and raw round events | Avatar, name, language; `bestDailyStreak`, `highestAlphabetLevelEverReached`, `celebratedAlphabetLevels` (lifetime trophies); the previous `lastFrozenLetterOptionsPerRound` value is not currently cleared |

Across **all** reset variants, the trophy trio (`bestDailyStreak`, `highestAlphabetLevelEverReached`, `celebratedAlphabetLevels`) is preserved unless explicitly named — a child shouldn't be re-shown a level-up animation they've already earned.

UI surfacing:

- Per-letter reset → letter row context menu in the dashboard.
- Current-focus reset → dashboard overflow menu (`Pick a new focus letter`). The action also clears syllable/word focus in `ProfileManager`, but the current UI only shows it while a **letter** focus is active.
- Calibration & streak resets → dashboard overflow menu (`Re-run calibration`, `Reset day streak`).
- Full reset → `EditProfileView`'s "Reset progress" button.
- `readingPracticePaused` is persisted on `Profile` for the dormant reading layer but is **not** surfaced as a toggle anywhere in the current shipping UI. If/when the reading layer reactivates, an `EditProfileView` toggle would be the intended home.

---

## Architecture & file map

```
Pismenka/
├── PismenkaApp.swift              `PismenkaApp` entry, `PismenkaAppDelegate` (Firebase bootstrap), and `ContentView` four-screen state machine with checkpoint resume
├── Models/
│   ├── Profile.swift              Per-child profile (letter/syllable/word stats, weekly assessments, focus, streaks, trophies)
│   ├── ProfileLearningSnapshot.swift  Single source of truth for derived learning state
│   ├── LearningUnit.swift         UnitKind, FocusTarget, LearningActivityKind, LearningRound
│   ├── LetterStat.swift           Per-letter mastery + LetterOverride + LetterKnowledgeState
│   ├── UnitProgressStat.swift     Shared syllable/word mastery aggregate (dormant in current release)
│   ├── LetterSymbol.swift         Typed API-edge wrapper for base/form/language
│   ├── FocusSelectionReason.swift Persisted "why this focus?" explanation
│   ├── RoundEvent.swift           Local rolling round log + RoundIntent/MistakeType/LiveDifficulty/RoundPlanReason
│   ├── LetterDifficulty.swift     introductionOrder, diacriticBase, ConfusionPolicy, confusing pairs
│   ├── SyllableCurriculum.swift   Czech CV slabika DAG + syllable distractors (dormant)
│   ├── WordCurriculum.swift       Czech seed words + playable word-pool gates (dormant)
│   ├── CurriculumAudioAvailability.swift  Model-layer protocol for audio-backed curriculum gating
│   ├── SkillLevel.swift           AlphabetLevel + ReadingStage (reading stages dormant), Comparable, trophy support
│   ├── LocalDay.swift             Calendar-day value type (year/month/day, daysSince, today(), nextSunday)
│   ├── GameState.swift            AdaptiveGameState — phases, typed rounds, daily goals, weekly assessment targeting, spotlight drill, hearts, stamps, distractors, position fairness
│   ├── AppSettings.swift          Audio, comfort, reminders, case-practice, parent-gate, personalized-Czech-letters settings
│   └── SessionCheckpoint.swift    Versioned exact-resume checkpoints
├── Services/
│   ├── ProfileManager.swift       Profile CRUD; session lifecycle; Sunday review/test planner; weekly assessment scoring; recordAnswer; overrides; granular resets. Forces `primaryLayer = .letters` and clears reading-unlock fields on every commit.
│   ├── AudioService.swift         Bundled letter audio playback, SFX, missing-asset validation, optional Čermák personalized Czech letter prompts. `requiredCurriculumVoiceAssets(for:)` currently returns `[]`, so syllable/word validation is disabled in the current release.
│   ├── HapticService.swift        Haptic feedback wrapper
│   ├── SessionCheckpointStore.swift  Local resume-checkpoint persistence
│   ├── NotificationService.swift  Parent opt-in local reminder (7:00 AM local time)
│   ├── ProfileExportService.swift Versioned JSON backup import/export
│   └── FirebaseBackupService.swift Google sign-in + Firestore recovery mirror
├── Resources/
│   └── RoutingCoverage.geojson    Marketing/availability map; not consumed by app gameplay
├── Views/
│   ├── Profile/
│   │   ├── ProfileSelectView.swift
│   │   ├── ParentGateView.swift   Parent gate: swipe-up or accessible hold-buttons mode
│   │   ├── CreateProfileView.swift
│   │   └── EditProfileView.swift  Avatar + name editing, Reset progress, Delete profile (parent-gated). No reading-practice toggle in the current shipping UI.
│   ├── Game/
│   │   ├── CalibrationView.swift  Adaptive 10–20 round front-loaded calibration
│   │   ├── GameView.swift         Adaptive game session
│   │   └── EasyModeGrid.swift     Defines `LetterGrid` + `LetterButton`; renders the option tiles
│   ├── Summary/
│   │   └── SummaryView.swift      Defines `SessionEndView` (file kept named for project stability)
│   ├── Settings/
│   │   └── SettingsView.swift     Music + voice/SFX toggles, Personalized letters (Čermák), Reduce motion, Confetti, Parent gate, Case practice, Daily reminder, Audio check, Export/Import backup, Google recovery, Copy diagnostic summary. Also defines `AudioCheckView`, which exposes only the first four language letters as `Replay "Find X"` plus the replayable game SFX clips (`Correct`, `Wrong`, `Streak 5`, `Streak 10`, `Click`).
│   ├── Parent/
│   │   └── ParentDashboardView.swift  Three-tier parent dashboard: Tier 1 (header/recommendation/needs-attention/focus/progress-glance), Tier 2 (weekly test summary, sortable+filterable letters list, reading progress — the reading-progress section is dormant), Tier 3 (collapsible diagnostics for retention/test rounds/confusions/raw history). Glossary alert + ellipsis menu for overrides, granular resets, weekly-test skip.
│   └── Components/
│       ├── ConfettiView.swift
│       ├── DesignSystem.swift     Brand colors, typography, button styles, `BrandBackground`
│       └── ShareSheet.swift
├── Assets.xcassets/
├── Sounds/                        See "Required assets → Audio" for the full layout
└── Info.plist
```

Three file-naming quirks worth knowing about (kept this way to avoid churning the Xcode project file):

- `EasyModeGrid.swift` defines `LetterGrid`, not an `EasyModeGrid` type.
- `SummaryView.swift` defines `SessionEndView`, not a `SummaryView` type.
- `Settings/SettingsView.swift` also contains `AudioCheckView`, `PersonalizedLettersCodeSheet`, and the shared `BrandPrimaryButtonStyle` / `BrandSecondaryButtonStyle` — they were intentionally kept in the same file to colocate the parent-area UI.

---

## Data storage

Progress is saved locally first and the app does not need network access for gameplay, learning, calibration, dashboards, audio, or checkpoints. `ProfileManager` persists to `UserDefaults` under the key **`pismenka_profiles_v2`**, with **`pismenka_profiles_v2_last_good`** and **`pismenka_profiles_v2_recovery`** used for last-readable backup and corrupt-payload preservation. Local saves are flushed on session-end and app lifecycle transitions such as `applicationWillResignActive`.

Firebase is optional parent-controlled backup only. If enabled, local profiles are mirrored to Firebase for Google-account recovery; if disabled or offline, the learning experience is unchanged.

`FirebaseBackupService` signs the parent in with Google via Firebase Auth and writes a compact backup document to Firestore at **`users/{uid}/backups/current`**. The document stores metadata (`schemaVersion`, `savedAt`, `appVersion`, `payloadBytes`, `payloadEncoding`) plus a binary `payload` containing a JSON `CloudBackupEnvelope`, compressed with LZFSE when that is smaller. Payloads larger than about **900 KB** are rejected before upload. Profile and settings changes schedule a debounced auto-backup (**2 s** after the last local mutation) while signed in; **Sync now** cancels any pending debounced write, flushes local saves, forces an immediate upload, and waits for Firestore to acknowledge pending writes before reporting success. On sign-in, launch, and explicit **Restore**, the service automatically merges profiles by `Profile.id`, keeping the newer `modifiedAt` for matching profiles and adding new profiles up to the four-profile limit. The settings **Google recovery** row exposes **Sign in with Google**, **Sync now**, **Restore**, and **Sign out** when authenticated. App settings are restored from the newest settings snapshot. Session checkpoints stay local-only because they are short-lived resume state, not long-term learning progress.

Each `Profile` carries:

| Field | Type | Purpose |
|---|---|---|
| `id`, `name`, `avatarId`, `language` | identity | Profile identity & locale |
| `modifiedAt` | `Date` | Last profile mutation; used to merge automatic Firebase recovery snapshots |
| `letterStats` | `[String: LetterStat]` | Per-letter mastery (recent results, lifetime totals, exposures, timestamps, override) |
| `syllableStats`, `wordStats` | `[String: UnitProgressStat]` | Per-syllable and per-word mastery |
| `everMasteredLetters` | `Set<String>` | Lifetime mastery — drives `alphabetLevel`; deduplicates re-graduations |
| `everMasteredSyllables`, `everMasteredWords` | `Set<String>` | Lifetime reading mastery — drives `ReadingStage` |
| `introducedLetters` | `Set<String>` | Letters intentionally introduced as focus/target; accidental fallback distractors do not enter this set |
| `cameoExposureDay`, `cameoExposuresToday` | `LocalDay?`, `Int` | Per-local-day budget for intentional cameo distractor exposures |
| `dailyPracticeDay`, `dailyPracticeAttempts` | `LocalDay?`, `Int` | Visible daily progress counter; backs `dailyGoalStartCount` and persists 25/adaptive progress across same-day sessions |
| `dailyPracticeWinnerClaimedDay`, `dailyPracticeWinnerClaimedMilestone` | `LocalDay?`, `Int` | Same-day Winner receipt; hides the Winner button until another full goal chunk is completed |
| `learningCycleStartDay`, `weeklyIntroducedLetters` | `LocalDay?`, `Set<String>` | Sunday-anchored letter cycle state; daily spotlight letters accumulate until the due Sunday-or-next-played review/test |
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
| `hasCompletedCalibration` | `Bool` | Routes to letter calibration on first launch |
| `hasCompletedSyllableOnboarding`, `hasCompletedSyllableCalibration`, `hasCompletedWordOnboarding`, `hasCompletedWordCalibration` | `Bool` | Reading-layer intro/calibration receipts |
| `parentNote` | `String?` | Free-form parent note attached to the profile. Informational only; never feeds the adaptive model. (`LetterStat` has its own per-letter `parentNote` with the same contract.) |

`Profile`, `LetterStat`, `UnitProgressStat`, `WeeklyLetterAssessment`, `RoundEvent`, `SessionPlan`, and checkpoint snapshots implement tolerant `Codable` paths where needed so older payloads or missing new fields decode cleanly (e.g., legacy `Date` fields → `LocalDay`, `lifetimeAttempts` → `targetAttempts`, missing `RoundEvent` cameo/focus fields, missing daily-goal/session-plan fields such as `introducedFocusTarget`, and old `GameEngineSnapshot` payloads without `instructionalBand`).

Hardening migrations are intentionally additive; no on-disk schema bump is required for these fields:

- `LetterStat` / `UnitProgressStat` evidence-tier additions are computed properties, so no stored profile field or schema bump is required.
- `AttemptContext`, `cameoLetter`, `includedFocusAsDistractor`, and `planReason` are optional/default-valued `RoundEvent` additions. Missing `attemptContext` remains stored as `nil`, and consumers semantically default it to independent practice with `attemptContext ?? .independent`; missing cameo/focus fields read as no cameo / no focus-distractor flag.
- `Profile.dailyPracticeDay`, `dailyPracticeAttempts`, `learningCycleStartDay`, and `weeklyIntroducedLetters` default to nil/zero/empty on old profiles. They start participating the next time a daily plan is committed.
- `Profile.activeWeeklyAssessment` defaults to nil and `recentWeeklyAssessments` defaults to empty on old profiles. New review/test assessment history begins with the first committed Sunday-or-next-played review/test after this code runs; old aggregate `LetterStat` history is not backfilled into fake retained/watch/review verdicts.
- `SessionPlan.dailyGoalTarget`, `dailyGoalStartCount`, `dailyPracticeKind`, `weeklyReviewLetters`, and `dailySpotlightLetter` all have decode defaults so older checkpoints or tests that lack the new fields still load. Older plans default to a 25-round introduction day with zero starting progress and no spotlight.
- `readingPracticePaused` reads legacy `postExpertPracticePaused` payloads; new saves write the broader reading-practice name.
- `pausedFocusLetters` defaults to empty on older profiles, and legacy paused letters get a migration-time `pausedFocusLetterDays` value for the 7-day cooldown.
- `lastFrozenLetterOptionsPerRound` defaults to nil on older profiles; the first new `AdaptiveGameState` session records a fresh frozen 4/6/8 grid size for future hysteresis.
- `alphabetLevel`, `readingStage`, and `instructionalBand` are computed inside `Profile.snapshot`; no stored `Profile` field and no `displayLevel` alias exist. Legacy `highestLevelEverReached` / `celebratedLevels` payloads decode into the alphabet trophy fields, with old reading-level values folded back to `.expert`.
- `GameEngineSnapshot.instructionalBand`, `letterOptionsPerRound`, and `sessionPlayableWords` are persisted only for checkpoint resume consistency. Older checkpoints without `instructionalBand` decode; restore falls back to the live profile snapshot's band, or discards/replans the checkpoint if the profile snapshot is unavailable. Older checkpoints without `letterOptionsPerRound` fall back to the live profile's current grid gate. Older checkpoints without `sessionPlayableWords` decode and recompute the pool from current audio/profile state.
- Tightened `wordsShouldUnlock` can delay a future word-layer unlock when audio or playable distractors are missing, but profiles that already have `wordsUnlockedAt` keep it because the predicate is consulted only before unlock.

Letters are stored as flat `String` storage keys. `LetterSymbol` is the typed API-edge wrapper (`base`, `form`, `language`) used to keep lowercase and per-language expansion honest without making JSON dictionary keys complicated. Uppercase legacy letters keep their bare key (`"A"`, `"Č"`), so existing stored profiles decode intact.

Typed round/event keys use `FocusTarget.storageKey` prefixes (`letter:A`, `syllable:MA`, `word:MÁMA`) wherever a mixed learning-unit namespace is needed.

Schema versions:

| Payload | Current schema |
|---|---:|
| UserDefaults profiles | `pismenka_profiles_v2` |
| Local JSON export | `ProfileExportEnvelope.currentSchemaVersion = 2` |
| Firebase backup | `CloudBackupEnvelope.currentSchemaVersion = 2` |
| Session checkpoint | `SessionCheckpointEnvelope.currentSchemaVersion = 2`; stored locally under `pismenka_session_checkpoint_v1` |

---

## Required assets

### App icon

1024×1024 PNG at `Assets.xcassets/AppIcon.appiconset/AppIcon.png`. `Contents.json` references this file, so a fresh workspace must include it before archiving. The current repo snapshot bundles a working PNG at that path; replace it with your own artwork before shipping.

### Audio

The live required audio surface is **letter prompts plus game SFX**. The reading layer is dormant, so syllable / blend / word recordings are not required, validated, reported in the parent audio check, or reachable in normal gameplay. The Xcode project includes `Pismenka/Sounds/` as a folder resource, so everything currently in that folder is bundled; only the live surface below is required by `AudioService.missingAssetNames(...)`.

Live required files are organized into subdirectories that `AudioService.resolveBundledAudioURL` resolves in order:

```
Pismenka/Sounds/
├── Letters/                         # default English + Czech letter prompts
│   ├── en_a.m4a … en_z.m4a
│   └── cz_a.m4a … cz_z.m4a + every Czech diacritic in GameLanguage.czech.letters
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

`AudioService` validates SFX and all letters for English and Czech on app launch in `DEBUG` builds, and whenever the parent opens the audio-check screen. Letter prompts replay the letter audio directly (`playFindPrompt` is a thin alias around `playLetter`), lowercase storage keys reuse the uppercase audio file (`Q|lower` looks for `en_q.m4a`), and letter prompts fall back to `AVSpeechSynthesizer` if an asset is missing. Missing files are shown to parents in the audio-check sheet, and playback failures fail gracefully rather than crashing.

List or verify the expected bundled letter/SFX set without regenerating anything:

```bash
python3 generate_audio_assets.py --dry-run
```

Personalized Czech letter prompts are opt-in. The settings screen's **Personalized letters** row triggers `PersonalizedLettersCodeSheet`, which unlocks with the 4-digit family code **`2436`** and toggles `AppSettings.personalizedCzechLettersEnabled`. When enabled, the asset resolver searches `Sounds/PersonalizedLetters/Cermak/` before `Sounds/Letters/`, so any Čermák-recorded Czech letter overrides the default voice. Letters the family has not yet recorded simply fall back to the default `Sounds/Letters/cz_*.m4a` clip, so personalization is additive rather than destructive.

Visual-only distractors (`1`, `rn`) do not need prompt audio because they are never target letters.

#### Recording voice

The shipped default letter recordings use **Google Cloud Text-to-Speech Chirp 3 HD**:

- Czech: `cs-CZ-Chirp3-HD-Achernar`.
- American English: `en-US-Chirp3-HD-Aoede`.

Regenerate the reviewed default letter sets with `gcloud` authenticated and the Cloud Text-to-Speech API enabled:

```bash
python3 generate_audio_assets.py --provider google --only-czech-letters --force --skip-sfx
python3 generate_audio_assets.py --provider google --only-english-letters --force --skip-sfx
```

`generate_audio_assets.py` uses the active `gcloud` project as the quota project, or `GOOGLE_OAUTH_ACCESS_TOKEN` / `GOOGLE_CLOUD_PROJECT` when those environment variables are set. Override the default voices with `GOOGLE_CZ_VOICE` or `GOOGLE_EN_VOICE`. The script's default `--provider` is `say` (macOS Samantha/Zuzana); the shipped default letter sets were generated with `--provider google` and the Chirp 3 HD voices above. The Google provider also carries the reviewed Czech pronunciation overrides for the cases Google otherwise expands awkwardly: standalone long vowels, `ě`, `x`, `ý`, and `z`.

Prompts keep pronunciation-friendly punctuation: Czech letter prompts use a comma pause such as `Bé, jako banán.`. The dormant reading-layer prompts are designed to use comma-separated components (`m, á, má` for blends, `má, ma` for segmented words) and natural lowercase for fluent reads (`máma`).

When the reading layer reactivates, syllable/word recordings will be required `.m4a` files for every seeded curriculum unit — slabiky use `cz_syl_<key>.m4a` and `cz_blend_<key>.m4a`, words use `cz_word_<key>.m4a` and `cz_word_<key>_slabikované.m4a` — and the child-facing prompts will not fall back to system speech because Czech vowel length and prosody are part of the lesson. The curriculum gates in `SyllableCurriculum`, `WordCurriculum`, and `wordsShouldUnlock` already consult `CurriculumAudioAvailability`, so a missing recording will keep that unit out of onboarding, calibration, focus selection, and word prerequisites, and gameplay will replan around it.

The current `Pismenka/Sounds/` snapshot contains **only** the live letter-and-SFX surface (115 git-tracked audio files):

- Six gameplay SFX clips (`sfx_correct.mp3`, `sfx_wrong.mp3`, `sfx_streak_5.mp3`, `sfx_streak_10.mp3`, `sfx_click.mp3`, `sfx_applause.mp3`).
- Daily-Winner celebration voice clip: `sfx_wow_en.m4a` ("Wow!"), played for every profile language.
- English base letters `en_a.m4a` … `en_z.m4a` (26 files) in `Sounds/Letters/`.
- Czech base letters `cz_a.m4a` … `cz_z.m4a` plus every diacritic letter in `GameLanguage.czech.letters` (`cz_á`, `cz_č`, `cz_ď`, `cz_ě`, `cz_é`, `cz_í`, `cz_ň`, `cz_ó`, `cz_ř`, `cz_š`, `cz_ť`, `cz_ú`, `cz_ů`, `cz_ý`, `cz_ž`) — 41 files total in `Sounds/Letters/`.
- Optional Čermák personalized Czech letter pack in `Sounds/PersonalizedLetters/Cermak/` (41 files), used only when the parent unlocks the **Personalized letters** setting. The current pack mirrors the full Czech alphabet.
- **Not bundled today:** Czech reading-layer clips (`cz_syl_*`, `cz_blend_*`, `cz_word_*`, segmented `cz_word_*_slabikované`), legacy decomposed letter filenames, or a `Sounds/Blends/` subdirectory. Older generations of those files may still exist under repo backup folders outside the app target; they are intentionally omitted from the shipped bundle while the reading layer stays dormant.

#### Daily-Winner celebration audio

The Winner moment plays a two-clip sequence in `AudioService.playWinnerCelebration(language:)`: `sfx_wow_en.m4a` first, then `sfx_applause.mp3` starting 0.55 s later so the crowd reaction overlaps the tail of the spoken exclamation the way a real audience would. The same English "Wow!" plays for every profile language — the exclamation reads as universally celebratory and avoids the awkward Czech-tail overlap a longer per-language clip produced. The `language:` parameter is preserved on the API in case future per-language variants are reintroduced.

- `sfx_wow_en.m4a` is generated via ElevenLabs (`eleven_multilingual_v2`) using `ELEVENLABS_EN_VOICE_ID` or the script's ElevenLabs English default. The celebration clip overrides the default ElevenLabs voice settings (lower `stability`, higher `style`) via `ELEVENLABS_VOICE_SETTINGS_OVERRIDES` in `generate_audio_assets.py` so the exclamation has real energy. Regenerate with `python3 generate_audio_assets.py --provider elevenlabs --only-files <(echo 'sfx_wow_en.m4a') --skip-sfx --force`.
- `sfx_applause.mp3` was sourced once from Wikimedia Commons file `Clapping_hurray_(cropped).oga` (~9.8 s, public domain — released by author Zack and friends, uploaded by Starlite), trimmed to ~3.5 s, fade-in/out applied, normalized to -14 LUFS, and re-encoded to 128 kbps mono mp3. The bundled clip is committed as a static asset; no re-fetch script is checked into this repo today, so any future regeneration is a manual ffmpeg pass against an equivalent public-domain source.

---

## Building

1. Create or reuse a Firebase project.
2. Add an iOS app in Firebase with the bundle ID currently configured in the app target: `CY-C7DBCED6-A931-11E9-A784-3F0DCDF3F5B5.com.electratea`.
3. Add `GoogleService-Info.plist` at the project root so the existing Xcode project file can bundle it in the `Pismenka` app target. A working plist is committed in this repo snapshot — replace it with the one downloaded from your own Firebase project before shipping. `FirebaseBootstrap.configureIfPossible()` no-ops when the plist is missing, so the app/tests still build, but the cloud backup path requires it.
4. Enable Firebase Authentication → Google provider.
5. Create Cloud Firestore in production mode and apply rules equivalent to the snippet below. This repo does **not** currently include `firebase.json`, `firestore.rules`, or `.firebaserc`; create/link those files before using `firebase deploy --only firestore:rules`, or paste the rules manually in the Firebase console.
6. In Xcode, ensure the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` matches the URL scheme in `Pismenka/Info.plist`. The checked-in scheme is `com.googleusercontent.apps.46536499967-hfc1pbvdbepkk0tjcme9k2hrb3v6ol1u`.
7. Verify the app icon and all required audio files are present.
8. Select your development team.
9. Build and run on iOS 17+ device or simulator.

### Development verification cadence

Adaptive-engine changes should be batched before expensive Xcode runs. Use `ReadLints` / language-server diagnostics while editing, then run one full app build of the `Pismenka` scheme and one `PismenkaTests` suite run after the related phases are implemented. If a new Swift file is added, ensure the Xcode project target membership is updated before that final build.

The model tests intentionally cover the hardening invariants, including Firebase plist bundling and URL-scheme alignment, planner-vs-engine warm-up across known-letter counts, predictable 25/adaptive daily goal completion, progress accumulation across same-day sessions, daily counter scoping to adaptive-daily target rounds, daily spotlight preservation of in-flight durable focus, evidence-derived spotlight scaffolding assumptions, Sunday-or-next-played review/test scheduling, empty-test fallback without cycle reset, safe confusable weekly skips, adaptive review/test targets, frozen weekly assessment audits, quota-first weekly assessment target selection, independent-only assessment scoring, retained/watch/review outcomes, 40-question weekly caps, unfinished weekly progress continuing across days, parent-skipped weekly tests archiving partial results, reading-layer daily goals without letter-week assumptions, hearts ending a sitting without resetting daily progress, wrong answers not ending adaptive daily/test sessions while hearts remain, known/strong-known option-count thresholds, frozen and restored letter option counts, reading-layer no-warm-up, full-alphabet Czech syllable unlock plus starter-subset no-unlock, syllable/word 4-option rounds, scheduled blending/building metadata, same-day focus quotas, assisted correct/wrong discount behavior including delayed rescue, assisted wrong heart loss, fluent-known evidence, visual-only distractors, cameo accounting and name-letter cameo priority, audio-filtered syllable/word unlock/playable pools, word-round options from the session playable pool, restored checkpoint playable pools, diacritic prerequisites, parent override boundaries, English Expert staying in letter maintenance, `instructionalBand <= alphabetLevel`, parent-explanation priority for assisted and impulsive discounts, cameo plus focus-distractor coexistence, simulation-style adaptive trajectory invariants, and tolerant checkpoint / legacy round-event / session-plan decode.

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

- **Exact resume** — `ContentView` restores an in-progress calibration or adaptive game from `SessionCheckpointStore` on launch; checkpoints clear on normal session end, home, or profile switch.
- **Portrait lock** — the app only runs in portrait orientation.
- **Third-party cloud** — Firebase Auth + Firestore and Google Sign-In provide recovery without Apple iCloud entitlements. Firebase Analytics / Crashlytics are not integrated.
- **iOS 17.0+.** The project sets `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; no minimum Xcode version is encoded in the project file.
- **Hardening trade-offs.** Conservative gates can make the app feel one session behind sudden improvement, but they avoid promoting unsupported distractors, unplayable reading units, or assisted attempts into mastery evidence.
- **Deferred follow-ups.** Longitudinal retention decay beyond the weekly assessment snapshot, richer rhyme/first-sound/clap-syllables mini-games, parent voice packs/name recording, optional tracing UI, micro-phrases, font policy, and physically blocking input for the first 300-400 ms after options appear are intentionally outside the current hardening contract.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](../LICENSE) (`AGPL-3.0-only`).

Code may be used, studied, modified, and shared under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
