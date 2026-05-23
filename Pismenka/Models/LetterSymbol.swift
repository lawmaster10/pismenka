//
//  LetterSymbol.swift
//  Pismenka
//
//  Typed wrapper for "a letter the child sees on screen", carrying the form
//  (uppercase / lowercase) and language alongside the base glyph. Used at the
//  API edge — round events, focus selection reasons, the `Profile.snapshot`
//  letter sets in later phases — so callers don't lose track of "what kind
//  of A is this?" as the system grows beyond the current uppercase-only,
//  one-language-per-profile shape.
//
//  ## Why a wrapper, not the raw String?
//
//  Today every `LetterStat` key is just `"A"`, `"Č"`, etc. — a base glyph,
//  uppercase, in whatever language the owning profile speaks. That works as
//  long as those three things never come apart. The plan adds two paths
//  that would break that assumption (#11 lowercase, #13 per-language stat
//  separation), and the cleanest way to keep them honest is to make the
//  shape explicit at the type level *before* either path lands.
//
//  ## Storage key
//
//  Storage (`Profile.letterStats`, `Profile.everMasteredLetters`,
//  `Profile.currentFocusLetter`) stays keyed by `String` — see review note
//  R3, which calls out `LetterSymbol` as a JSON dictionary key as risky.
//  The bridge is `LetterSymbol.storageKey`: the canonical `String` that
//  identifies the symbol in storage.
//
//  Phase 0b ships `storageKey == base` for `form == .upper`, which is
//  byte-identical to today's bare-letter keys ("A", "Č", …). No migration
//  is needed — every persisted profile loads cleanly under the typed API.
//
//  Future expansions (lowercase, multi-language) would need to *reshape*
//  the storageKey, and at that point a one-shot migration in
//  `Profile.init(from:)` will rewrite legacy keys via
//  `LetterSymbol.upper($0, in: language).storageKey`. That migration hook
//  is already documented at the read site even though it's a no-op today.
//

import Foundation

/// Whether a `LetterSymbol` represents the uppercase or lowercase form of
/// its base glyph. Phase 0b only persists `.upper`; `.lower` is reserved
/// for the lowercase-expansion path (#11).
enum LetterForm: String, Codable, CaseIterable {
    case upper
    case lower
}

/// A letter the child can see on screen, complete with its form and the
/// language it belongs to. Hashable so it can be used in `Set<LetterSymbol>`
/// (e.g., the typed-wrapper variants of snapshot letter sets in later phases).
///
/// Equality and hashing key off all three fields: `A.upper.english` and
/// `A.upper.czech` are *different* symbols even though they share a glyph,
/// because Czech and English profiles teach them as part of distinct
/// alphabets and shouldn't collapse into one stat entry.
struct LetterSymbol: Hashable, Codable {
    /// The actual character, exactly as displayed (e.g., "A", "Č", "a"). For
    /// diacritic letters the base *glyph* lives here verbatim — the
    /// "underlying base letter" mapping (#12, e.g., "Č" → "C") lives in
    /// `LetterDifficulty.diacriticBase`, not on this type.
    let base: String

    /// Uppercase or lowercase. Phase 0b only ships `.upper`.
    let form: LetterForm

    /// Which language alphabet this symbol belongs to. Carried so future
    /// per-language stat separation (#13) doesn't need a profile lookup at
    /// every read site.
    let language: GameLanguage

    /// The canonical `String` that identifies this symbol in storage —
    /// keys into `Profile.letterStats`, members of
    /// `Profile.everMasteredLetters`, the value of
    /// `Profile.currentFocusLetter`, etc.
    ///
    /// Phase 0b: `.upper` symbols return `base` directly (matches today's
    /// keys). `.lower` symbols suffix `"|lower"` so the namespace stays
    /// disjoint when the lowercase path lands. Per-language separation
    /// would extend this further; the bare-string format is intentionally
    /// extensible.
    var storageKey: String {
        switch form {
        case .upper:
            // Identical to legacy bare-letter keys — preserves on-disk
            // compatibility without a migration step.
            return base
        case .lower:
            // Reserved namespace for the lowercase-expansion path (#11).
            return "\(base)|lower"
        }
    }

    var displayText: String {
        switch form {
        case .upper: return base
        case .lower: return base.lowercased()
        }
    }

    /// Convenience constructor for the most common case: uppercase letter
    /// in the profile's active language.
    static func upper(_ base: String, in language: GameLanguage) -> LetterSymbol {
        LetterSymbol(base: base, form: .upper, language: language)
    }

    static func lower(_ base: String, in language: GameLanguage) -> LetterSymbol {
        LetterSymbol(base: base, form: .lower, language: language)
    }

    /// Inverse of `storageKey`: rehydrate a symbol from its on-disk key.
    /// Returns `nil` for malformed inputs (empty / unrecognized form
    /// suffixes); Phase 0b only produces uppercase keys, so anything
    /// unsuffixed is treated as `.upper` in `fallbackLanguage`.
    static func decode(storageKey: String, fallbackLanguage: GameLanguage) -> LetterSymbol? {
        guard !storageKey.isEmpty else { return nil }
        if storageKey.hasSuffix("|lower") {
            let base = String(storageKey.dropLast("|lower".count))
            guard !base.isEmpty else { return nil }
            return LetterSymbol(base: base, form: .lower, language: fallbackLanguage)
        }
        return LetterSymbol(base: storageKey, form: .upper, language: fallbackLanguage)
    }
}
