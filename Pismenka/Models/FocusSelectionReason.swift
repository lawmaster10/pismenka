//
//  FocusSelectionReason.swift
//  Pismenka
//
//  Persisted provenance record describing *why* the most recently
//  introduced focus letter was selected. Phase 0d (#18 / addition B in
//  the plan): the parent dashboard can show "we picked Č because we
//  couldn't yet introduce it — its base C just graduated," which is
//  meaningfully different from "we just kept walking the introduction
//  order."
//
//  In Phase 0 the only writer is the static-introduction-order picker
//  in `ProfileManager.commitSessionStartIfNeeded`, so every value emitted is
//  `.nextInOrder`. Phase 3c (`p3-prereqfocus`) and 3d (`p3-diacritic`)
//  upgrade the picker to differentiate the other reasons; the field
//  shape stays identical so the dashboard surface (Phase 4b) can ship
//  against it now.
//

import Foundation

/// Why the current focus letter was chosen.
///
/// `selectedKey` is a `LetterSymbol.storageKey` (per the API-edge /
/// String-storage convention from Phase 0b — see `LetterSymbol`). `date`
/// captures the wall-clock moment the picker fired, primarily so the
/// dashboard can show "selected on Apr 26" alongside the reason.
struct FocusSelectionReason: Codable, Equatable {
    /// The picked letter, in `LetterSymbol.storageKey` form.
    let selectedKey: String
    /// When the pick happened. Used purely for dashboard display; no
    /// day-level logic depends on this so it's a `Date`, not a
    /// `LocalDay`.
    let date: Date
    /// What rule fired to produce this pick.
    let reason: Reason

    enum Reason: String, Codable, CaseIterable {
        /// Default Phase 0 reason: walked the static introduction order
        /// and picked the next not-yet-known, not-yet-mastered candidate
        /// that didn't visually conflict with a still-fresh mastery.
        case nextInOrder
        /// Phase 3c: picked a letter specifically because all of its
        /// visually-confusing prerequisites are mastered AND it has a
        /// big enough distractor pool to teach safely. Stronger
        /// pedagogical signal than `nextInOrder`.
        case prerequisiteReady
        /// Phase 3c: picked a letter the child already saw but never
        /// mastered, and whose accuracy has decayed. Re-teaching a
        /// previously-introduced weak letter beats inventing a brand-
        /// new one when stale weaknesses are piling up.
        case staleWeakness
        /// Phase 3d: picked a Czech diacritic variant whose base is now
        /// in `everMasteredLetters`. The dashboard can surface this as
        /// "now we'll teach Č because C is solid."
        case diacriticAfterBaseMastered
        /// Phase 3c: no candidate cleanly satisfied the upgraded picker
        /// rules, so we fell back to the next-in-order pick. Tracked
        /// separately so the dashboard can flag "we had to pick blind"
        /// situations for parental attention.
        case fallbackNoReadyCandidate
    }
}
