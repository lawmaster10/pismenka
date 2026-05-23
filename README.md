# Písmenka

Písmenka is an adaptive pre-reading game for toddlers, currently focused 100% on letters. Each child profile learns in English or Czech, hears a bundled letter prompt, and picks the matching letter from a playful grid.

The app is intentionally offline for gameplay and learning. Google/Firebase support is only for optional parent-enabled backup.

## Current Scope

The shipped app currently includes:

- English and Czech letter recognition.
- One-time per-profile calibration.
- Daily adaptive letter practice with a visible Winner goal.
- Sunday-or-next-played weekly letter review/test.
- Parent dashboard, profile editing, per-letter overrides, and progress reset controls.
- Bundled letter audio plus game sound effects.
- Optional personalized Czech letter prompts unlocked in settings with code `2436`.

Syllables (`slabiky`) and word-reading models remain in the codebase as dormant future-version scaffolding, but they are not scheduled, unlocked, shown in the UI, validated as required assets, or shipped as audio content right now.

For a deeper technical overview of the app architecture, learning model, and asset inventory, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## User Flow

```text
ProfileSelectView
   |
   +-- [gear + parent gate] -----------------> SettingsView
   |
   +-- [hold profile -> context menu]
   |      +-- [View results + parent gate] --> ParentDashboardView
   |      +-- [Edit profile + parent gate] --> EditProfileView
   |
   +-- [tap profile] -> CalibrationView? -> GameView -> SummaryView
```

## Learning Model

Each profile stores independent letter progress in `LetterStat`. Calibration gives the app an initial confidence map, then daily sessions continue to update target attempts, distractor exposures, recent accuracy, review priority, and mastery.

Daily play is letter-only:

- `ProfileManager.previewSessionPlan(profileId:)` always plans a letter session for normal gameplay.
- New daily spotlight letters are introduced without wiping an existing remediation focus.
- Warm-up uses known letters when the child has enough evidence.
- Drill rounds emphasize the current focus or daily spotlight.
- Review rounds pull from known, weak, stale, and weekly assessment letters.
- Expert profiles stay in mixed letter maintenance rather than moving into reading content.

Weekly review/test remains letter-based. The app schedules a Sunday review once there are enough letters in the weekly cohort, and if the child misses Sunday the pending review runs on the next played day.

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
- `Pismenka/Services/ProfileManager.swift` plans sessions, persists progress, and handles resets.
- `Pismenka/Models/GameState.swift` builds rounds and records session-level outcomes.
- `Pismenka/Services/AudioService.swift` resolves bundled audio, validates required assets, and switches personalized Czech letter prompts on/off.
- `Pismenka/Views/Game/GameView.swift` presents the daily letter game.
- `Pismenka/Views/Parent/ParentDashboardView.swift` presents parent-visible progress.
- `generate_audio_assets.py` generates the current letter-only audio set.

## Building

Open `Pismenka.xcodeproj` in Xcode 16 or newer and run the `Pismenka` scheme on iOS 17+.

Command-line build example:

```bash
xcodebuild -project Pismenka.xcodeproj -scheme Pismenka -destination 'generic/platform=iOS Simulator' build
```

## Development Notes

The app may still contain dormant types for future syllable and word-reading work, including `SyllableCurriculum`, `WordCurriculum`, and `UnitProgressStat`. For the current release, those paths should stay unreachable from normal gameplay and should not require bundled audio.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).

You may use, study, modify, and share the code under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Please preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
