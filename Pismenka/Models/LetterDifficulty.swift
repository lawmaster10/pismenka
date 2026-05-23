//
//  LetterDifficulty.swift
//  Pismenka
//
//  Pedagogical letter ordering, the generalized early-recognition set used to
//  seed first-run calibration, and a visually-confusing-pairs map shared by
//  the calibration view and the adaptive game's distractor picker.
//

import Foundation

enum LetterDifficulty {

    /// Generalized "letters most preschoolers recognize first" set, used to
    /// seed the very first calibration so a brand-new profile encounters
    /// letters that are likely to feel familiar. Drawn from preschool letter-
    /// recognition research (alphabet-song head A–E, plus visually distinctive
    /// O / X / M / S / T that consistently rank near the top of early-
    /// recognition studies). `isKnown` is still determined by real
    /// performance; nothing is synthetically pre-seeded.
    static let earlyRecognitionLetters: [String] = [
        "A", "B", "C", "O", "X", "M", "S", "T", "D", "E"
    ]

    /// Pedagogical / frequency order for picking the next focus letter.
    /// `earlyRecognitionLetters` appear *last* because calibration is expected
    /// to gather evidence on them first, so they shouldn't compete for "next
    /// focus" slots before that evidence exists. Czech adds diacritic letters
    /// at the end so `expert` is achievable but accents come last.
    static func introductionOrder(for language: GameLanguage) -> [String] {
        switch language.resolvedLanguage {
        case .english, .system:
            return [
                "P", "R", "N", "L", "I", "H", "K", "G",
                "F", "Y", "U", "W", "Z", "Q", "J", "V",
                // Early-recognition letters appear last (calibration gathers
                // evidence on them up front).
                "A", "B", "C", "O", "X", "M", "S", "T", "D", "E"
            ]
        case .czech:
            // Same English-letter order first (Czech alphabet contains all of A-Z),
            // then diacritic letters at the end so `expert` requires those too.
            return [
                "P", "R", "N", "L", "I", "H", "K", "G",
                "F", "Y", "U", "W", "Z", "Q", "J", "V",
                "A", "B", "C", "O", "X", "M", "S", "T", "D", "E",
                "Á", "Č", "Ď", "É", "Ě", "Í", "Ň", "Ó", "Ř", "Š",
                "Ť", "Ú", "Ů", "Ý", "Ž"
            ]
        }
    }

    static func introductionOrder(
        for language: GameLanguage,
        lowercaseMode: LowercaseMode,
        mastered: Set<String>
    ) -> [String] {
        let upper = introductionOrder(for: language)
        guard lowercaseMode != .uppercaseOnly else { return upper }
        let allUpperMastered = Set(language.letters).isSubset(of: mastered)
        guard allUpperMastered else { return upper }
        let lower = upper.map { LetterSymbol.lower($0, in: language).storageKey }
        return upper + lower
    }

    /// Pool used by `CalibrationView`: the generalized 10-letter early-
    /// recognition set, optionally extended with the first letter of the
    /// child's name (mapped from a Czech diacritic to its base if needed) so
    /// the very first session contains a personally meaningful letter. Returns
    /// 10 letters when the name letter is absent, already in the base set, or
    /// not eligible; otherwise 11 letters.
    static func calibrationPool(
        for language: GameLanguage,
        nameLetter: String? = nil
    ) -> [String] {
        var pool = earlyRecognitionLetters
        if let mapped = nameLetterForCalibration(nameLetter, language: language),
           !pool.contains(mapped) {
            pool.append(mapped)
        }
        return pool
    }

    /// Resolves a child's first-name letter to a calibration-eligible base
    /// letter. Maps Czech diacritics to their base (Š → S) so calibration
    /// stays within the pedagogical "base before diacritic" contract, and
    /// drops letters that aren't part of the active alphabet.
    static func nameLetterForCalibration(
        _ nameLetter: String?,
        language: GameLanguage
    ) -> String? {
        guard let nameLetter, !nameLetter.isEmpty else { return nil }
        let base = diacriticBase[nameLetter] ?? nameLetter
        guard language.letters.contains(base) else { return nil }
        guard isEligibleTarget(base, language: language) else { return nil }
        return base
    }

    /// Non-letter lookalikes that can appear only as advanced/expert
    /// distractors. They are intentionally excluded from introduction order,
    /// focus selection, and mastery progress.
    static let visualOnlyDistractors: Set<String> = ["1", "rn"]

    /// Directional non-letter distractors. These are not symmetric confusion
    /// edges because the keys can never be targets.
    static let visualOnlyDistractorsByTarget: [String: Set<String>] = {
        func lower(_ key: String) -> String {
            LetterSymbol.lower(key, in: .english).storageKey
        }

        return [
            "I": ["1"],
            "J": ["1"],
            "L": ["1"],
            lower("L"): ["1"],
            "M": ["rn"],
            lower("M"): ["rn"]
        ]
    }()

    /// Visually confusing pairs — used to avoid or intentionally practice
    /// distractors that are hard to distinguish from the target. This includes
    /// shape-similar pairs (B/D, M/W) and same-base letters whose small
    /// distinguishing mark is easy to overlook (C/Č, S/Š). This graph is
    /// symmetric by construction. Directional non-letter lookalikes live in
    /// `visualOnlyDistractorsByTarget`.
    static let visuallyConfusingPairs: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]

        func connect(_ a: String, _ b: String) {
            guard a != b else { return }
            map[a, default: []].insert(b)
            map[b, default: []].insert(a)
        }

        func connectGroup(_ keys: [String]) {
            for (index, key) in keys.enumerated() {
                for other in keys.dropFirst(index + 1) {
                    connect(key, other)
                }
            }
        }

        func lower(_ key: String) -> String {
            LetterSymbol.lower(key, in: .english).storageKey
        }

        // Mirror / rotation families.
        connectGroup(["B", "D", "P", "Q"])
        connectGroup([lower("B"), lower("D"), lower("P"), lower("Q")])
        connect("N", "U")
        connect(lower("N"), lower("U"))
        connect("M", "W")
        connect(lower("M"), lower("W"))
        connect("N", "M")
        connect(lower("N"), lower("M"))
        connect("N", "Z")
        connect(lower("N"), lower("Z"))
        connect("V", "W")
        connect(lower("V"), lower("W"))

        // Shape-similar lowercase families.
        connect(lower("M"), lower("N"))
        connect(lower("I"), lower("J"))
        connectGroup([lower("C"), lower("E"), lower("O")])
        connectGroup([lower("U"), lower("V"), lower("W")])
        connect(lower("F"), lower("T"))
        connect(lower("H"), lower("N"))

        // Near-identical glyphs in many rounded fonts.
        connectGroup(["I", "J", "L"])
        connect(lower("L"), "I")

        // Uppercase/lowercase scaled-shape pairs.
        for base in ["C", "O", "S", "X", "Z", "P", "K"] {
            connect(base, lower(base))
        }

        // Structural uppercase families.
        connect("E", "F")
        connectGroup(["P", "R", "B"])
        connect("I", "H")
        connectGroup(["C", "G", "O"])
        connectGroup(["O", "Q", "D"])

        // Czech diacritic contrasts. Connect each diacritic only to its base:
        // sibling marks such as É/Ě and Ú/Ů should not become mutual mastery
        // prerequisites in the focus picker.
        for (diacritic, base) in diacriticBase {
            connect(base, diacritic)
            connect(lower(base), lower(diacritic))
        }

        return map
    }()

    /// Czech diacritic variants and their base prerequisite. Diacritics are
    /// gated until their base letter has entered `everMasteredLetters`, so the
    /// child learns C before Č, E before É/Ě, and so on.
    static let diacriticBase: [String: String] = [
        "Č": "C", "Ď": "D", "É": "E", "Ě": "E",
        "Ň": "N", "Ř": "R", "Š": "S", "Ť": "T",
        "Ú": "U", "Ů": "U", "Ý": "Y", "Ž": "Z",
        "Á": "A", "Í": "I", "Ó": "O"
    ]

    /// Returns true if `a` and `b` are visually confusing in either direction.
    /// Used when picking the next focus letter so we don't introduce e.g. D
    /// right after B unless B is already strong.
    static func areVisuallyConfusing(_ a: String, _ b: String) -> Bool {
        if let set = visuallyConfusingPairs[a], set.contains(b) { return true }
        if let set = visuallyConfusingPairs[b], set.contains(a) { return true }
        return false
    }

    static func diacriticBaseKey(for key: String) -> String? {
        let upper = uppercaseBaseKey(for: key)
        guard let base = diacriticBase[upper] else { return nil }
        return isLowercaseKey(key) ? LetterSymbol.lower(base, in: .english).storageKey : base
    }

    static func visualOnlyDistractors(for target: String) -> Set<String> {
        visualOnlyDistractorsByTarget[target] ?? []
    }

    static func isVisualOnlyDistractor(_ key: String) -> Bool {
        visualOnlyDistractors.contains(key)
    }

    static func isEligibleTarget(_ key: String, language: GameLanguage) -> Bool {
        guard !isVisualOnlyDistractor(key) else { return false }
        let base = uppercaseBaseKey(for: key)
        return language.letters.contains(base)
    }

    static func isLowercaseKey(_ key: String) -> Bool {
        key.hasSuffix("|lower")
    }

    static func uppercaseBaseKey(for key: String) -> String {
        if key.hasSuffix("|lower") {
            return String(key.dropLast("|lower".count))
        }
        return key
    }

    static func lowercaseKey(for uppercaseKey: String, language: GameLanguage) -> String {
        LetterSymbol.lower(uppercaseBaseKey(for: uppercaseKey), in: language).storageKey
    }

    /// Phase 3c/3d prerequisite-aware focus picker. It prefers:
    ///
    /// 1. Stale introduced weaknesses that need re-teaching.
    /// 2. Introduction-order candidates whose visual prerequisites are ready,
    ///    whose distractor pool is big enough, and whose shape is not too
    ///    similar to currently weak letters.
    /// 3. A tagged fallback to the static introduction-order picker.
    ///
    /// A letter may have appeared earlier as a low-pressure cameo distractor;
    /// that glyph exposure is useful, but it is deliberately not a formal
    /// introduction and does not change this target-selection contract.
    ///
    /// Returns the selected storage key and a dashboard-friendly reason.
    static func nextFocusWithReason(
        language: GameLanguage,
        known: Set<String>,
        learning: Set<String>,
        mastered: Set<String>,
        introduced: Set<String>,
        letterStats: [String: LetterStat],
        lowercaseMode: LowercaseMode = .uppercaseOnly,
        blocked: Set<String> = []
    ) -> (key: String, reason: FocusSelectionReason.Reason)? {
        let order = introductionOrder(for: language, lowercaseMode: lowercaseMode, mastered: mastered)
        let alphabet = Set(order)
        let weakLetters = learning.filter { key in
            (letterStats[key]?.recentAccuracy(window: 5) ?? 1) < 0.5
        }

        let staleWeaknesses = introduced
            .intersection(alphabet)
            .subtracting(known)
            .subtracting(mastered)
            .subtracting(blocked)
            .filter { key in
                guard let stat = letterStats[key] else { return false }
                // Threshold is `>= 2` because first-run calibration deliberately
                // gives every pool letter exactly two target attempts; a clean
                // 0/2 there is strong enough signal to re-teach rather than
                // skip past in favor of an unrelated next-focus letter.
                return stat.targetAttempts >= 2 && stat.recentAccuracy(window: 5) < 0.5
            }
            .sorted { a, b in
                let pa = letterStats[a]?.reviewPriority ?? 0
                let pb = letterStats[b]?.reviewPriority ?? 0
                if pa != pb { return pa > pb }
                return a < b
            }
        if let stale = staleWeaknesses.first {
            return (stale, .staleWeakness)
        }

        func diacriticPrerequisiteMet(_ candidate: String) -> Bool {
            guard let base = diacriticBaseKey(for: candidate) else { return true }
            return mastered.contains(base)
        }

        func isDiacriticVariant(_ maybeVariant: String, of candidate: String) -> Bool {
            diacriticBaseKey(for: maybeVariant) == candidate
        }

        func isReady(_ candidate: String) -> Bool {
            guard isEligibleTarget(candidate, language: language) else { return false }
            guard diacriticPrerequisiteMet(candidate) else { return false }

            let confusables = visuallyConfusingPairs[candidate] ?? []
            let alphabetConfusables = confusables.intersection(alphabet)
            let prerequisiteConfusables = alphabetConfusables.filter { confusable in
                // C should not require future Č mastery, but Č still requires
                // C through `diacriticPrerequisiteMet`.
                !isDiacriticVariant(confusable, of: candidate)
            }
            let allPrereqsKnown = prerequisiteConfusables.allSatisfy { mastered.contains($0) }

            let poolSize = known.union(learning).subtracting([candidate]).count
            let poolOK = poolSize >= 4

            let notTooSimilar = !weakLetters.contains { weak in
                areVisuallyConfusing(weak, candidate)
            }

            return allPrereqsKnown && poolOK && notTooSimilar
        }

        for candidate in order {
            guard isEligibleTarget(candidate, language: language) else { continue }
            if blocked.contains(candidate) { continue }
            if known.contains(candidate) { continue }
            if mastered.contains(candidate) { continue }
            guard isReady(candidate) else { continue }
            if diacriticBase[candidate] != nil {
                return (candidate, .diacriticAfterBaseMastered)
            }
            return (candidate, .prerequisiteReady)
        }

        for fallback in order {
            guard isEligibleTarget(fallback, language: language) else { continue }
            if blocked.contains(fallback) { continue }
            if known.contains(fallback) { continue }
            if mastered.contains(fallback) { continue }
            guard diacriticPrerequisiteMet(fallback) else { continue }
            return (fallback, .fallbackNoReadyCandidate)
        }

        return nil
    }

    /// How aggressively visually-confusing letter pairs (B/D, M/W, O/Q, …)
    /// should be allowed as distractors against a given target. The right
    /// answer depends on where the child is in their learning arc:
    ///
    /// * **Calibration** and early focus drilling — `.avoid`. The child
    ///   barely knows the target shape; pairing it with a near-twin only
    ///   teaches them the wrong lesson ("they're the same letter").
    /// * **Mid focus drilling** (~day 3+) — `.allowFluentPairs`. The
    ///   child has held the target shape steady for a couple of days. We
    ///   can start letting confusable letters through, but only when BOTH
    ///   sides of the pair are reasonably known to the child, so the
    ///   discrimination is genuine practice rather than a guess.
    /// * **Later review** (no-focus / expert sessions on already-known
    ///   targets) — `.intentionallyPractice`. We actively prefer
    ///   confusable distractors so the child gets purpose-built
    ///   discrimination training on pairs like B/D and M/W.
    ///
    /// Mode `.intentionallyPractice` differs from `.allowFluentPairs`
    /// only in *ordering* (it prefers confusables when picking), not in
    /// *legality* (both modes accept the same set of distractors).
    enum ConfusionPolicy {
        /// Strict avoidance: never pick a visually-confusing distractor
        /// for the given target.
        case avoid
        /// Confusable distractors are allowed when BOTH the target and
        /// the candidate are already in the child's known set. Pairs
        /// where either side is still uncertain are still excluded.
        case allowFluentPairs
        /// Same legality as `.allowFluentPairs`, but actively
        /// prefers confusable letters within the pool — used to
        /// purpose-build B/D, M/W, O/Q discrimination drills in
        /// later-stage review.
        case intentionallyPractice
    }
}
