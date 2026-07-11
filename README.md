# Písmenka

Písmenka is an adaptive pre-reading game for toddlers, currently focused 100% on letters. Each child profile learns in English or Czech, hears a bundled letter prompt, and picks the matching letter from a playful grid.

The app is intentionally offline for gameplay and learning. Google/Firebase support is only for optional parent-enabled backup.

## Current Scope

The shipped app currently includes:

- English and Czech letter recognition.
- First-launch language choice (Czech by default) with spoken previews, followed by an optional Apple/Google backup step.
- One-time per-profile calibration.
- Adaptive 25-answer letter sessions with a visible Winner goal earned by correct answers.
- A retention progress check after every **six completed 25-answer sessions** (adaptive **8–40** round goal; may finish sooner when cohort evidence resolves).
- Parent dashboard, profile editing, per-letter overrides, and progress reset controls.
- Bundled letter audio plus game sound effects.
- Optional personalized Czech letter prompts unlocked in settings with code `2436`.

Syllables (`slabiky`) and word-reading models remain in the codebase as dormant future-version scaffolding, but they are not scheduled, unlocked, shown in the UI, validated as required assets, or shipped as audio content right now.

For a deeper technical overview of the app architecture, learning model, and asset inventory, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## User Flow

```text
App launch
   +-- [first launch] -> FirstLaunchOnboardingView
   |                       +-- Czech / English spoken preview
   |                       +-- optional Apple / Google backup
   |                       +-- ProfileSelectView
   +-- [returning user] -> ProfileSelectView

ProfileSelectView
   +-- [gear + parent gate] -----------------> SettingsView
   |
   +-- [hold profile -> context menu]
   |      +-- [View results + parent gate] --> ParentDashboardView
   |      +-- [Edit profile + parent gate] --> EditProfileView
   |
   +-- [tap profile] -> CalibrationView? -> GameView -> SessionEndView
```

## Learning Model

Each profile stores independent letter progress in `LetterStat`. Calibration gives the app an initial confidence map, then completed practice updates target attempts, distractor exposures, recent accuracy, mastery, and a local FSRS-inspired memory state. That state tracks per-letter difficulty, stability, predicted retrievability, lapses, uncertainty, and the next due review. Assisted rescue/reveal rounds and impulsive taps are excluded from mastery and scheduling evidence.

Normal gameplay is letter-only:

- `ProfileManager.previewSessionPlan(profileId:)` always plans a letter session for normal gameplay.
- New daily spotlight letters are introduced without wiping an existing remediation focus.
- Warm-up uses known letters when the child has enough evidence.
- Drill rounds emphasize the current focus or daily spotlight.
- Review rounds prioritize remediation and due retention work, then uncertainty checks, with only a small audit pool of stable letters.
- Missed letters receive prompt relearning; stable letters gradually expand toward long review intervals.
- Expert profiles stay in mixed letter maintenance rather than moving into reading content.

### Daily goal and Winner

The progress strip fills toward a Winner milestone (**25** correct target rounds in an ordinary letter session). Only **correct** answers advance that bar, so a wrong tap earns no progress toward the Winner button. Progress persists across same-day sittings, and running out of hearts ends only the current sitting.

### Adaptive option grid

The number of answer choices adapts to demonstrated independent performance at each grid tier (4 / 6 / 8), with known-letter evidence kept as a safety check. Weak/new targets stay capped at 4 even after a larger grid is earned. When clear independent struggle appears, the live governor downshifts by **2 options per step** (up to two steps, e.g. 8 → 6 → 4); recovery requires at least **4 correct in 5 independent rounds** and restores one tier at a time.

### Retention progress check

The retention check remains letter-based, but it is not tied to a weekday or elapsed time. Every claimed **25-answer letter session** advances a persisted cycle counter. Partial sessions do not count; two separately completed same-day sessions do. After six completions, the child's next session becomes the progress check—even if reaching six took several weeks.

The progress check is the deliberate exception to the correct-only goal: it is a retention audit with a frozen **8–40** participation target, so **every** answered round counts toward the visible bar whether right or wrong. Independent retained/watch/review evidence still requires unassisted audit rounds. An unfinished check persists across days; completion or parent skip archives its evidence, resets the six-session counter, and begins a new practice cycle.

## Audio Assets

Bundled audio lives under `Pismenka/Sounds`:

```text
Pismenka/Sounds/
  Letters/                         # default English and Czech letter prompts
  PersonalizedLetters/Cermak/      # optional Czech personalized letter prompts
  sfx_*.mp3                        # game sound effects
  sfx_wow_en.m4a                   # Winner celebration voice clip
```

Only letter voice files are expected now:

- English: `Pismenka/Sounds/Letters/en_<letter>.m4a`
- Czech: `Pismenka/Sounds/Letters/cz_<letter>.m4a`
- Personalized Czech: `Pismenka/Sounds/PersonalizedLetters/Cermak/cz_<letter>.m4a`

Generate or check the current expected assets with:

```bash
python3 generate_audio_assets.py --dry-run
```

The current shipped default letter voices were generated with Google Cloud
Text-to-Speech Chirp 3 HD voices:

- Czech: `cs-CZ-Chirp3-HD-Achernar`
- American English: `en-US-Chirp3-HD-Aoede`

Regenerate the reviewed default letter sets with:

```bash
python3 generate_audio_assets.py --provider google --only-czech-letters --force --skip-sfx
python3 generate_audio_assets.py --provider google --only-english-letters --force --skip-sfx
```

Google generation uses the active `gcloud` login, or `GOOGLE_OAUTH_ACCESS_TOKEN`
if set. Override the defaults with `GOOGLE_CZ_VOICE` or `GOOGLE_EN_VOICE`.

## Important Files

- `Pismenka/PismenkaApp.swift` wires settings, profile state, and audio behavior.
- `Pismenka/Models/Profile.swift` stores per-child progress and durable learning state.
- `Pismenka/Models/AdaptiveLearningScheduler.swift` implements per-letter forgetting, due dates, confusion decay, and grid-performance evidence.
- `Pismenka/Services/ProfileManager.swift` plans sessions, persists progress, and handles resets.
- `Pismenka/Models/GameState.swift` builds rounds and records session-level outcomes.
- `Pismenka/Services/AudioService.swift` resolves bundled audio, validates required assets, and switches personalized Czech letter prompts on/off.
- `Pismenka/Views/Game/GameView.swift` presents the daily letter game; `Pismenka/Views/Summary/SummaryView.swift` defines `SessionEndView`.
- `Pismenka/Views/Parent/ParentDashboardView.swift` presents parent-visible progress.
- `generate_audio_assets.py` generates the current letter-only audio set.

## Building

Open `Pismenka.xcodeproj` in Xcode 16 or newer and run the `Pismenka` scheme on iOS 17+.

Optional Firebase backup needs `GoogleService-Info.plist` at the repo root (gitignored); the app still runs for local letter-only play without it.

Command-line build example:

```bash
xcodebuild -project Pismenka.xcodeproj -scheme Pismenka -destination 'generic/platform=iOS Simulator' build
```

## App Store CLI Releases

The repo is set up so App Store Connect API keys stay local: `AuthKey_*.p8` is gitignored. Do not commit API keys, Apple ID passwords, app-specific passwords, or generated JWTs.

For a CLI release:

1. In App Store Connect, create an API key under **Users and Access → Integrations → App Store Connect API** with the `App Manager` role.
2. Save the downloaded key at the repo root as `AuthKey_<KEY_ID>.p8`, and keep the `KEY_ID` plus `ISSUER_ID` in a password manager.
3. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Pismenka.xcodeproj/project.pbxproj`.
4. Run tests, archive, and upload:

```bash
xcodebuild test -project Pismenka.xcodeproj -scheme Pismenka -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' -derivedDataPath build/DerivedData
xcodebuild archive -project Pismenka.xcodeproj -scheme Pismenka -destination 'generic/platform=iOS' -archivePath build/Pismenka-<VERSION>-<BUILD>.xcarchive -derivedDataPath build/DerivedData -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/Pismenka-<VERSION>-<BUILD>.xcarchive -exportOptionsPlist build/AppStoreExportOptions.plist -exportPath build/AppStoreUpload-<VERSION>-<BUILD> -allowProvisioningUpdates
```

5. Use the App Store Connect API to create the version, attach the processed build, set `whatsNew`, set `usesIdfa: false`, create a review submission, add the version, and submit it. See `docs/ARCHITECTURE.md` for the exact API flow and payload shapes.

## Development Notes

The app may still contain dormant types for future syllable and word-reading work, including `SyllableCurriculum`, `WordCurriculum`, and `UnitProgressStat`. For the current release, those paths should stay unreachable from normal gameplay and should not require bundled audio.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).

You may use, study, modify, and share the code under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Please preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
