# Písmenka

Písmenka is an adaptive early-learning game for toddlers with two modes: **Letters** and **Numbers**. Each child profile learns in English or Czech, hears a bundled prompt, and picks the matching letter or number from a playful grid.

Gameplay and learning are offline. Optional Apple/Google Firebase backup is parent-enabled only.

## Current Scope

- English and Czech letter recognition, plus a numbers mode (0–100 recognition) as a peer learning layer
- First-launch language choice (Czech by default) with spoken previews, then optional Apple/Google backup
- One-time per-profile calibration (letters and numbers each have their own)
- Adaptive 25-answer sessions with a visible Winner goal, in both modes
- Retention progress check after every six completed 25-answer sessions, per mode
- A shared day streak across modes, with independent per-mode progress
- Parent dashboards for both modes, profile editing, per-letter overrides, and progress reset controls
- Bundled letter and number audio, game SFX, and optional personalized Czech letter prompts

Syllable and word-reading models remain in the codebase as dormant scaffolding. They are not scheduled, unlocked, shown, or shipped as audio in this release.

## Docs

For the learning model, session planner, asset inventory, file map, build notes, and App Store release flow, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Building

Open `Pismenka.xcodeproj` in Xcode 16+ and run the `Pismenka` scheme on iOS 17+. Optional cloud backup needs a local `GoogleService-Info.plist` (gitignored); the app runs for letter play without it.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).

You may use, study, modify, and share the code under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Please preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
