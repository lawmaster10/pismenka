//
//  WordCurriculum.swift
//  Pismenka
//
//  Seed words for the first Czech word-reading layer. Each word is stored
//  together with its syllable decomposition for arcs and building rounds.
//

import Foundation

struct WordUnit: LearningUnit, Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let syllables: [String]

    var kind: UnitKind { .word }
    var prerequisites: [String] {
        syllables.map { FocusTarget.syllable($0).storageKey }
    }
}

enum WordCurriculum {
    static let czechWords: [WordUnit] = [
        WordUnit(key: "MÁMA", syllables: ["MÁ", "MA"]),
        WordUnit(key: "TÁTA", syllables: ["TÁ", "TA"]),
        WordUnit(key: "PUSA", syllables: ["PU", "SA"]),
        WordUnit(key: "MÍSA", syllables: ["MÍ", "SA"]),
        WordUnit(key: "SÍLA", syllables: ["SÍ", "LA"]),
        WordUnit(key: "LASO", syllables: ["LA", "SO"]),
        WordUnit(key: "LUPA", syllables: ["LU", "PA"]),
        WordUnit(key: "PILA", syllables: ["PI", "LA"]),
        WordUnit(key: "PATA", syllables: ["PA", "TA"]),
        WordUnit(key: "MÁTA", syllables: ["MÁ", "TA"]),
        WordUnit(key: "SÍTO", syllables: ["SÍ", "TO"]),
        WordUnit(key: "LÉTO", syllables: ["LÉ", "TO"]),
        WordUnit(key: "TETA", syllables: ["TE", "TA"]),
        WordUnit(key: "POLE", syllables: ["PO", "LE"]),
        WordUnit(key: "MÁLO", syllables: ["MÁ", "LO"])
    ]

    static func units(for language: GameLanguage) -> [WordUnit] {
        language.resolvedLanguage == .czech ? czechWords : []
    }

    static func unit(_ key: String, language: GameLanguage) -> WordUnit? {
        units(for: language).first { $0.key == key }
    }

    static func allKeys(for language: GameLanguage) -> [String] {
        units(for: language).map(\.key)
    }

    static func prerequisitesMet(for key: String, profile: Profile) -> Bool {
        guard let unit = unit(key, language: profile.language) else { return false }
        return unit.syllables.allSatisfy { profile.knownSyllables.contains($0) }
    }

    static func playableWords(for profile: Profile, audio: CurriculumAudioAvailability) -> [WordUnit] {
        units(for: profile.language).filter { unit in
            prerequisitesMet(for: unit.key, profile: profile)
                && audio.hasWordAudio(unit.key, language: profile.language)
        }
    }

    static func wordsShouldUnlock(profile: Profile, audio: CurriculumAudioAvailability) -> Bool {
        let known = profile.knownSyllables
        guard known.count >= 8 else { return false }
        let consonantFamilies = Set(known.compactMap { syllable in
            SyllableCurriculum.unit(syllable, language: profile.language)?.consonant
        })
        guard consonantFamilies.count >= 2 else { return false }
        let pool = playableWords(for: profile, audio: audio)
        guard pool.count >= 4 else { return false }
        return pool.contains {
            hasEnoughDistractors(
                for: $0.key,
                from: pool,
                profile: profile,
                optionCount: 4
            )
        }
    }

    static func nextFocus(profile: Profile, candidates: [WordUnit]) -> String? {
        candidates.first { unit in
            !profile.everMasteredWords.contains(unit.key)
                && !profile.knownWords.contains(unit.key)
        }?.key
    }

    static func nextFocus(profile: Profile, audio: CurriculumAudioAvailability) -> String? {
        nextFocus(profile: profile, candidates: playableWords(for: profile, audio: audio))
    }

    static func nextFocus(profile: Profile) -> String? {
        nextFocus(
            profile: profile,
            candidates: units(for: profile.language).filter {
                prerequisitesMet(for: $0.key, profile: profile)
            }
        )
    }

    static func distractors(for target: String, profile: Profile, count: Int) -> [String] {
        distractors(
            for: target,
            candidates: units(for: profile.language).filter {
                prerequisitesMet(for: $0.key, profile: profile)
            },
            profile: profile,
            count: count
        )
    }

    static func distractors(
        for target: String,
        candidates: [WordUnit],
        profile: Profile,
        count: Int
    ) -> [String] {
        guard let unit = unit(target, language: profile.language) else { return [] }
        let available = candidates.filter { $0.key != target }
        let sameLength = available.filter { $0.syllables.count == unit.syllables.count }
        let fallback = available.filter { !sameLength.contains($0) }
        return Array((sameLength + fallback).map(\.key).prefix(count))
    }

    static func hasEnoughDistractors(
        for target: String,
        from playablePool: [WordUnit],
        profile: Profile,
        optionCount: Int
    ) -> Bool {
        distractors(
            for: target,
            candidates: playablePool,
            profile: profile,
            count: optionCount - 1
        ).count >= optionCount - 1
    }
}
