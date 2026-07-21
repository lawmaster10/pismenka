//
//  SyllableCurriculum.swift
//  Pismenka
//
//  First Czech syllable layer. It starts after the full alphabet is introduced
//  and mastered, then grows into long-vowel contrasts.
//

import Foundation

struct SyllableUnit: LearningUnit, Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let consonant: String
    let vowel: String
    let isLong: Bool
    let prerequisites: [String]

    var kind: UnitKind { .syllable }

    var baseVowel: String {
        vowel.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ")).uppercased()
    }

    var shortBaseKey: String {
        consonant + baseVowel
    }
}

enum SyllableCurriculum {
    static let starterConsonants = ["M", "L", "S", "P", "T"]
    static let shortVowels = ["A", "E", "I", "O", "U"]
    static let longVowelByShort = ["A": "Á", "E": "É", "I": "Í", "O": "Ó", "U": "Ú"]

    static func units(for language: GameLanguage) -> [SyllableUnit] {
        guard language.resolvedLanguage == .czech else { return [] }

        var units: [SyllableUnit] = []
        for consonant in starterConsonants {
            for vowel in shortVowels {
                let short = consonant + vowel
                units.append(SyllableUnit(
                    key: short,
                    consonant: consonant,
                    vowel: vowel,
                    isLong: false,
                    prerequisites: [consonant, vowel]
                ))
            }
        }

        for consonant in starterConsonants {
            for vowel in shortVowels {
                guard let long = longVowelByShort[vowel] else { continue }
                let key = consonant + long
                let short = consonant + vowel
                units.append(SyllableUnit(
                    key: key,
                    consonant: consonant,
                    vowel: long,
                    isLong: true,
                    prerequisites: [consonant, long, FocusTarget.syllable(short).storageKey]
                ))
            }
        }

        return units
    }

    static func unit(_ key: String, language: GameLanguage) -> SyllableUnit? {
        units(for: language).first { $0.key == key }
    }

    static func allKeys(for language: GameLanguage) -> [String] {
        units(for: language).map(\.key)
    }

    static func isCurriculumSyllable(_ key: String, language: GameLanguage) -> Bool {
        unit(key, language: language) != nil
    }

    static func prerequisitesMet(for key: String, profile: Profile) -> Bool {
        guard let unit = unit(key, language: profile.language) else { return false }
        for prerequisite in unit.prerequisites {
            if let target = FocusTarget(storageKey: prerequisite) {
                switch target {
                case .letter(let letter):
                    guard profile.everMasteredLetters.contains(letter) else { return false }
                case .number(let number):
                    guard profile.everMasteredNumbers.contains(number) else { return false }
                case .syllable(let syllable):
                    guard profile.knownSyllables.contains(syllable) else { return false }
                case .word(let word):
                    guard profile.knownWords.contains(word) else { return false }
                }
            } else if !profile.everMasteredLetters.contains(prerequisite) {
                return false
            }
        }
        return true
    }

    static func nextFocus(profile: Profile) -> String? {
        units(for: profile.language).first { unit in
            !profile.everMasteredSyllables.contains(unit.key)
            && !profile.knownSyllables.contains(unit.key)
            && prerequisitesMet(for: unit.key, profile: profile)
        }?.key
    }

    enum DistractorDimension: Hashable {
        case consonant
        case vowel
        case length
        case mixed
    }

    enum DistractorStage {
        case onboardingCalibration
        case focusDay1
        case focusDay2
        case focusDay3Plus
        case reviewMaintenance
        case rescueEased
    }

    static func calibrationTargets(profile: Profile) -> [String] {
        units(for: profile.language)
            .filter { !$0.isLong && prerequisitesMet(for: $0.key, profile: profile) }
            .map(\.key)
    }

    static func distractors(
        for target: String,
        profile: Profile,
        count: Int,
        dimension: DistractorDimension = .mixed
    ) -> [String] {
        guard let unit = unit(target, language: profile.language) else { return [] }
        let available = allKeys(for: profile.language).filter { key in
            key != target && prerequisitesMet(for: key, profile: profile)
        }

        func matches(_ key: String) -> Bool {
            guard let other = self.unit(key, language: profile.language) else { return false }
            switch dimension {
            case .consonant:
                return other.vowel == unit.vowel && other.consonant != unit.consonant
            case .vowel:
                return other.consonant == unit.consonant && other.vowel != unit.vowel && other.isLong == unit.isLong
            case .length:
                return other.consonant == unit.consonant
                    && other.vowel.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ"))
                        == unit.vowel.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ"))
                    && other.isLong != unit.isLong
            case .mixed:
                return true
            }
        }

        let primary = available.filter(matches)
        let fallback = available.filter { !primary.contains($0) }
        return Array((primary + fallback).prefix(count))
    }

    static func distractors(
        for target: String,
        profile: Profile,
        count: Int,
        stage: DistractorStage
    ) -> [String] {
        guard count > 0,
              let targetUnit = unit(target, language: profile.language) else {
            return []
        }

        let availableUnits = units(for: profile.language).filter { candidate in
            candidate.key != target
                && prerequisitesMet(for: candidate.key, profile: profile)
        }

        func consonantContrasts() -> [String] {
            availableUnits
                .filter { !$0.isLong && !targetUnit.isLong && $0.vowel == targetUnit.vowel && $0.consonant != targetUnit.consonant }
                .map(\.key)
        }

        func shortVowelContrasts() -> [String] {
            availableUnits
                .filter { !$0.isLong && !targetUnit.isLong && $0.consonant == targetUnit.consonant && $0.vowel != targetUnit.vowel }
                .map(\.key)
        }

        func lengthContrasts() -> [String] {
            availableUnits
                .filter {
                    $0.consonant == targetUnit.consonant
                        && $0.baseVowel == targetUnit.baseVowel
                        && $0.isLong != targetUnit.isLong
                        && hasBeenHeard($0.key, profile: profile)
                        && hasBeenHeard(targetUnit.key, profile: profile)
                }
                .map(\.key)
        }

        func fallbackShortCV(excluding selected: [String]) -> [String] {
            availableUnits
                .map(\.key)
                .filter { $0 != target && !selected.contains($0) }
        }

        func takeUnique(_ groups: [[String]], reserveLengthContrast: Bool = false) -> [String] {
            var selected: [String] = []
            if reserveLengthContrast, let length = lengthContrasts().first {
                selected.append(length)
            }
            for group in groups {
                for key in group where selected.count < count && !selected.contains(key) {
                    selected.append(key)
                }
            }
            for key in fallbackShortCV(excluding: selected) where selected.count < count {
                selected.append(key)
            }
            return selected
        }

        switch stage {
        case .onboardingCalibration, .focusDay1, .rescueEased:
            return takeUnique([consonantContrasts()])
        case .focusDay2:
            return takeUnique([consonantContrasts(), shortVowelContrasts()])
        case .focusDay3Plus:
            return takeUnique([consonantContrasts(), shortVowelContrasts()], reserveLengthContrast: true)
        case .reviewMaintenance:
            let preferred = weakestContrastDimension(for: target, profile: profile)
            switch preferred {
            case .length:
                return takeUnique([lengthContrasts(), consonantContrasts(), shortVowelContrasts()])
            case .vowel:
                return takeUnique([shortVowelContrasts(), consonantContrasts(), lengthContrasts()])
            case .consonant:
                return takeUnique([consonantContrasts(), shortVowelContrasts(), lengthContrasts()])
            case .mixed:
                return takeUnique([lengthContrasts(), consonantContrasts(), shortVowelContrasts()])
            }
        }
    }

    private static func hasBeenHeard(_ key: String, profile: Profile) -> Bool {
        profile.introducedSyllables.contains(key)
            || (profile.syllableStats[key]?.targetAttempts ?? 0) > 0
    }

    private static func weakestContrastDimension(for target: String, profile: Profile) -> DistractorDimension {
        guard let targetUnit = unit(target, language: profile.language),
              let stat = profile.syllableStats[target],
              !stat.confusedWith.isEmpty else {
            return .mixed
        }

        var scores: [DistractorDimension: Int] = [.consonant: 0, .vowel: 0, .length: 0]
        for (wrongKey, count) in stat.confusedWith {
            guard let wrong = unit(FocusTarget(storageKey: wrongKey)?.rawKey ?? wrongKey, language: profile.language) else {
                continue
            }
            if wrong.consonant == targetUnit.consonant,
               wrong.baseVowel == targetUnit.baseVowel,
               wrong.isLong != targetUnit.isLong {
                scores[.length, default: 0] += count
            } else if wrong.consonant == targetUnit.consonant,
                      wrong.vowel != targetUnit.vowel {
                scores[.vowel, default: 0] += count
            } else if wrong.vowel == targetUnit.vowel,
                      wrong.consonant != targetUnit.consonant {
                scores[.consonant, default: 0] += count
            }
        }

        return scores.max { lhs, rhs in lhs.value < rhs.value }?.key ?? .mixed
    }
}
