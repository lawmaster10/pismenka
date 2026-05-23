//
//  ProfileLearningSnapshot.swift
//  Pismenka
//
//  Single source of truth for "where is this child in their learning?". Every
//  consumer that previously asked the `Profile` directly for learning state
//  (warm-up target selection, focus selection, level math, parent dashboard,
//  end-screen counts, profile card progress) reads from `Profile.snapshot`
//  instead. That way subtle UI/game mismatches — "the dashboard says A is
//  mastered but the game keeps drilling it" — become structurally
//  impossible: there is one place that resolves the rules.
//
//  Phase 0 ships this with `Set<String>` letter sets matching the current
//  storage shape (uppercase base-letter keys). Phase 0b will swap the field
//  types to `Set<LetterSymbol>` once the typed wrapper lands; the field
//  *names* and resolution rules below are stable across that change.
//

import Foundation

/// Resolved learning state for a single profile at a single moment.
///
/// All fields are derived from the profile's persisted state. The snapshot is
/// a value type with no logic — it's literally the answer to "what does this
/// child know right now?" pre-computed once so every reader gets the same
/// answer.
///
/// ### `currentlyMastered` vs `everMastered`
///
/// Two distinct mastery sets, intentionally:
///
/// * **`currentlyMasteredLetters`** — letters whose `LetterStat`
///   currently satisfies the strict focus-graduation rule (≥ 7/8 over the
///   last 8 target attempts). This is the *live* signal — if a previously
///   mastered letter slips out of the recent-results window, it leaves this
///   set. Used for the parent-dashboard "Mastered" category and the
///   `LetterKnowledgeState.mastered` resolver.
/// * **`everMasteredLetters`** — the lifetime mastery set for normal play.
///   Once a letter enters, it stays unless progress is explicitly reset.
///   Drives `alphabetLevel` and the end-screen "letters mastered" count.
///   `highestAlphabetLevelEver` remains the preserved trophy.
///
/// `recentlySlipped` (populated in Phase 1a) bridges the two: letters in
/// `everMasteredLetters` that aren't in `knownLetters` *right now* and
/// have a `LetterStat.demotedAt` timestamp. The dashboard surfaces these
/// gently as "Recently slipped" without demoting the trophy count.
///
/// ### `nextFocusCandidate`
///
/// Populated from the same prerequisite-aware picker used by runtime focus
/// assignment, so parent-dashboard previews and session planning agree on
/// the next teaching target.
struct ProfileLearningSnapshot: Equatable {
    /// Letters the game should treat as "known" for review/distractor
    /// purposes right now. Mirrors `Profile.knownLetters` — respects parent
    /// overrides and the focus-exception rule.
    let knownLetters: Set<String>

    /// Stronger evidence tier used for hard distractor roles. Parent overrides
    /// do not auto-promote into this set; a marked-known letter still needs
    /// underlying `LetterStat.isStrongKnown` evidence, and a reset letter is
    /// excluded even if history was strong.
    let strongKnownLetters: Set<String>

    /// Strong-known plus quick, stable response time. Used for the hardest
    /// distractor roles where automatic recognition matters.
    let fluentKnownLetters: Set<String>

    /// Parent-marked known letters that still lack strong data. The game can
    /// use these cautiously without treating them as proof.
    let parentMarkedKnownButUnverified: Set<String>

    /// Letters whose stat *currently* satisfies the strict focus-graduation
    /// rule. Live signal; can shrink if recent results slip. Use this for
    /// "Mastered" labels.
    let currentlyMasteredLetters: Set<String>

    /// Lifetime mastery set for normal play: once mastered, counted here until
    /// progress is explicitly reset. Use this for level math and end-screen
    /// counts.
    let everMasteredLetters: Set<String>

    let knownSyllables: Set<String>
    let currentlyMasteredSyllables: Set<String>
    let everMasteredSyllables: Set<String>
    let knownWords: Set<String>
    let currentlyMasteredWords: Set<String>
    let everMasteredWords: Set<String>

    /// Letters with at least one target attempt where the child isn't yet
    /// `isKnown`. The "still working on it" pool.
    let learningLetters: Set<String>

    /// Letters the child has never encountered in any way (not as a target,
    /// not as a distractor). Computed against the active language's full
    /// alphabet so unseen counts are honest.
    let unseenLetters: Set<String>
    let unseenSyllables: Set<String>
    let unseenWords: Set<String>

    /// Letters that were ever mastered but have since dropped out of
    /// `knownLetters` (auto-demotion path). Populated in Phase 1a once
    /// `LetterStat.wasKnownBefore` / `demotedAt` exist; in Phase 0 this is
    /// always empty so consumers can rely on the field being present.
    let recentlySlipped: Set<String>

    /// Live alphabet level based on `everMasteredLetters.count`.
    let alphabetLevel: AlphabetLevel

    /// Live Czech reading stage based on reading unlock plus syllable/word mastery.
    let readingStage: ReadingStage

    /// Difficulty band the engine should use for this session. Unlike
    /// `alphabetLevel`, this can drop when recently-mastered units slip.
    let instructionalBand: AlphabetLevel

    /// Persisted highest-ever alphabet level.
    /// Never re-derived from current stats — that would let demotion lose the
    /// trophy.
    let highestAlphabetLevelEver: AlphabetLevel

    /// The letter that's actively being drilled, if any.
    let currentFocus: String?
    let currentFocusTarget: FocusTarget?

    /// What the picker would choose for the next focus letter if asked right
    /// now. Phase 0: static introduction-order walk. Phase 3c: prerequisite-
    /// aware. Same property, upgraded implementation.
    let nextFocusCandidate: String?
    let nextFocusTarget: FocusTarget?

    /// Known letters sorted by descending Wilson-95% certainty (pure
    /// accuracy evidence; no response-time discount). Stays as the parent
    /// dashboard's "how sure are we?" sort key and as the easy-distractor
    /// pool order — both of those care about *strength*, not "what should
    /// we drill next?". See `LetterStat`'s asymmetric speed rule for why
    /// slow correct answers no longer demote this ordering.
    let lettersByConfidence: [String]

    /// Known letters sorted by descending `LetterStat.reviewPriority`
    /// (`0.6*weakness + 0.4*staleness`). Drives warm-up target selection:
    /// a child who's reviewing the same set every day should *not* always
    /// see their strongest letter first — they should see the one they
    /// most recently missed or hadn't been tested on in a while.
    /// Confidence-only ordering hides that signal.
    ///
    /// Slowness used to be a third 0.2 term but was removed: for a
    /// distractible 3-year-old "slow on this letter" is mostly distraction
    /// noise rather than weakness, and pushing a known-but-slow letter up
    /// the queue crowded out actually-weak letters.
    ///
    /// Tied or all-zero priorities (brand-new known letters with no recent
    /// activity yet) fall back to descending confidence for a deterministic
    /// order.
    let lettersByReviewPriority: [String]

    /// Total letter count for the active language; useful when consumers want
    /// to compute "X out of N" without re-resolving the language alphabet.
    let totalLettersInLanguage: Int
}

/// Parent-facing answer to "what does my child know?".
///
/// This deliberately avoids the lifetime trophy count (`everMasteredLetters`)
/// as the headline. Parents need a current confidence read: secure evidence,
/// likely-but-light evidence, letters needing practice, and letters not yet
/// introduced.
///
/// `recentlySlippedLetters` is surfaced as a separate field for callers that
/// want to highlight the "had it, wobbly now" cohort explicitly. The headline
/// counts already fold these into `likelyKnownLetters` so the **needs
/// practice** bucket only contains letters that have never cleared the
/// strict bar — a previously-mastered letter that's slipping is not the
/// same problem as a letter the child has never reliably known, and merging
/// them under one alarming label muddied the dashboard.
struct ParentLetterKnowledgeSummary: Equatable {
    let confidentlyKnownLetters: Set<String>
    let likelyKnownLetters: Set<String>
    let needsPracticeLetters: Set<String>
    let notIntroducedLetters: Set<String>
    let recentlySlippedLetters: Set<String>
    let totalLetters: Int

    var confidentlyKnownCount: Int { confidentlyKnownLetters.count }
    var likelyKnownCount: Int { likelyKnownLetters.count }
    var needsPracticeCount: Int { needsPracticeLetters.count }
    var notIntroducedCount: Int { notIntroducedLetters.count }
    var recentlySlippedCount: Int { recentlySlippedLetters.count }
}

extension ProfileLearningSnapshot {
    /// Resolve the 4-bucket parent summary.
    ///
    /// Three rules drive what counts as **confidently known**, and a letter
    /// qualifies if *any* of them holds (always intersected with
    /// `knownLetters`, so a currently-failing letter never claims confidence):
    ///
    /// 1. `isStrongKnown` — Wilson 95% lower bound ≥ 0.6 on lifetime
    ///    accuracy. (Speed no longer demotes this; see `LetterStat`.)
    /// 2. `isFocusGraduated` (currentlyMastered) — ≥ 7/8 of the last 8
    ///    target attempts correct.
    /// 3. **Ever-mastered AND currently still passing the loose check.**
    ///    This is the parent-intuitive path: a letter that once cleared
    ///    the strict graduation bar and still answers reliably right now
    ///    is a confident known, even if its recent window happens not to
    ///    contain a fresh 8-attempt block. Without this rule, the
    ///    headline count fluctuated as focus rotated away from older
    ///    letters; the lifetime trophy stopped translating into the
    ///    parent-facing count.
    ///
    /// **Recently slipped** letters (ever-mastered but currently failing
    /// the loose check) are folded into `likelyKnownLetters` rather than
    /// `needsPracticeLetters`. They are also returned separately for any
    /// caller that wants to label them distinctly (the dashboard's
    /// "Needs attention" rows already do this). The reasoning: a letter
    /// the child mastered last week and missed once in the last five
    /// taps is not the same pedagogical situation as a letter they've
    /// never reliably known. Lumping both under "needs practice"
    /// over-reported the latter.
    func parentLetterKnowledgeSummary(alphabetLetters: Set<String>) -> ParentLetterKnowledgeSummary {
        let knownAlphabet = knownLetters.intersection(alphabetLetters)
        let everMasteredInAlphabet = everMasteredLetters.intersection(alphabetLetters)
        let recentlySlippedInAlphabet = recentlySlipped.intersection(alphabetLetters)

        let confidentlyKnown = strongKnownLetters
            .union(currentlyMasteredLetters)
            .union(everMasteredInAlphabet)
            .intersection(knownAlphabet)

        let likelyKnown = knownAlphabet
            .subtracting(confidentlyKnown)
            .union(recentlySlippedInAlphabet)

        let notIntroduced = unseenLetters.intersection(alphabetLetters)

        let needsPractice = alphabetLetters
            .subtracting(confidentlyKnown)
            .subtracting(likelyKnown)
            .subtracting(notIntroduced)

        return ParentLetterKnowledgeSummary(
            confidentlyKnownLetters: confidentlyKnown,
            likelyKnownLetters: likelyKnown,
            needsPracticeLetters: needsPractice,
            notIntroducedLetters: notIntroduced,
            recentlySlippedLetters: recentlySlippedInAlphabet,
            totalLetters: alphabetLetters.count
        )
    }
}
