# Písmenka

Písmenka is an adaptive early-learning game for toddlers with two modes: **Letters** and **Numbers**. Each child profile learns in English or Czech, hears a bundled prompt, and picks the matching letter or number from a playful grid.

Gameplay and learning are offline. Optional Apple/Google Firebase backup is parent-enabled only.

## Current Scope

- Current release: **1.6 (build 1)**
- English and Czech letter recognition, plus a numbers mode (0–100 recognition) as a peer learning layer
- First-launch language choice (Czech by default) with spoken previews, then optional Apple/Google backup
- One-time per-profile calibration (letters and numbers each have their own)
- Adaptive 25-answer sessions with a visible Winner goal, in both modes
- Retention progress check after every six completed 25-answer sessions, per mode
- A shared day streak across modes, with independent per-mode progress
- Parent dashboards for both modes, profile editing, per-letter overrides, and progress reset controls
- Bundled letter and number audio, game SFX, and optional personalized Czech letter prompts

Syllable and word-reading models remain in the codebase as dormant scaffolding. They are not scheduled, unlocked, shown, or shipped as audio in this release.

## Letter and Number Target Fairness

Number sessions previously applied the daily target cap and recent-target checks only to the scheduler's narrow preferred pool. If one number was the sole remaining "needs work" candidate, that one-item pool appeared to have no alternative, so the fallback selected it repeatedly—even after its daily cap—and could place it on consecutive regular rounds. The Letters implementation had a final fallback across the wider introduced set; the Numbers port omitted that step.

The deeper audit also found that Letters still had weaker legacy behavior: its cap was 10, could fail open, fresh sessions did not restore target recency, and Extra Practice shared the ordinary daily ledger. Both ordinary 25-answer modes now enforce the same invariants at final assignment gates shared by warm-up, focus, review, contrast, and rescue paths:

- No letter or number can be targeted more than **5 times per local day** (20% of the visible goal).
- The target can never equal the immediately previous target. Governor-prioritized rescues retain an intervening round.
- The cap is fail-closed: an exhausted introduced pool ends the sitting instead of silently exceeding the limit.
- Same-day recency is restored from persisted round events and saved in checkpoints, preventing session-boundary and restore-boundary repeats.
- Extra Practice remains intentionally focused but no longer writes to the ordinary daily challenge's fairness ledger.
- Legacy over-limit counters are clamped on read and on their next write.

Symmetric regression coverage now includes focus drilling, mistakes plus rescue/governor behavior, fresh same-day sessions, checkpoint restoration, Extra Practice isolation, legacy values, and total legal-pool exhaustion for both Letters and Numbers.

## Docs

For the learning model, session planner, asset inventory, file map, build notes, and App Store release flow, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Building

Open `Pismenka.xcodeproj` in Xcode 16+ and run the `Pismenka` scheme on iOS 17+. Optional cloud backup needs a local `GoogleService-Info.plist` (gitignored); the app runs for letter play without it.

## License

Písmenka is open source under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).

You may use, study, modify, and share the code under the terms of the AGPL-3.0. The license requires modified versions that are distributed or offered over a network to provide their corresponding source code under the same license.

Please preserve attribution in forks and derivatives: "Písmenka was created by Lawmaster."
