//
//  LearningUnit.swift
//  Pismenka
//
//  Typed identifiers for the post-letter curriculum. Storage keys are
//  deliberately prefixed so a letter, syllable, and word can never collide.
//

import Foundation

enum UnitKind: String, Codable, CaseIterable, Equatable {
    case letter
    case syllable
    case word
    case number
}

enum LearningActivityKind: String, Codable, CaseIterable, Equatable {
    case letterRecognition
    case numberRecognition
    case syllableCalibration
    case syllableRecognition
    case syllableBlending
    case syllableSegmenting
    case wordReading
    case wordBuilding
}

enum LearningLayer: String, Codable, Equatable {
    case letters
    case numbers
    case syllables
    case words
}

protocol LearningUnit {
    var key: String { get }
    var kind: UnitKind { get }
    var prerequisites: [String] { get }
}

enum FocusTarget: Hashable, Codable, Identifiable {
    case letter(String)
    case syllable(String)
    case word(String)
    case number(String)

    var id: String { storageKey }

    var kind: UnitKind {
        switch self {
        case .letter: return .letter
        case .syllable: return .syllable
        case .word: return .word
        case .number: return .number
        }
    }

    var rawKey: String {
        switch self {
        case .letter(let key), .syllable(let key), .word(let key), .number(let key):
            return key
        }
    }

    var storageKey: String {
        switch self {
        case .letter(let key): return "letter:\(key)"
        case .syllable(let key): return "syllable:\(key)"
        case .word(let key): return "word:\(key)"
        case .number(let key): return "number:\(key)"
        }
    }

    var displayText: String {
        switch self {
        case .letter(let key):
            if key.hasSuffix("|lower") {
                return String(key.dropLast("|lower".count)).lowercased()
            }
            return key
        case .syllable(let key), .word(let key), .number(let key):
            return key
        }
    }

    init(kind: UnitKind, key: String) {
        switch kind {
        case .letter: self = .letter(key)
        case .syllable: self = .syllable(key)
        case .word: self = .word(key)
        case .number: self = .number(key)
        }
    }

    init?(storageKey: String) {
        if storageKey.hasPrefix("letter:") {
            self = .letter(String(storageKey.dropFirst("letter:".count)))
        } else if storageKey.hasPrefix("syllable:") {
            self = .syllable(String(storageKey.dropFirst("syllable:".count)))
        } else if storageKey.hasPrefix("word:") {
            self = .word(String(storageKey.dropFirst("word:".count)))
        } else if storageKey.hasPrefix("number:") {
            self = .number(String(storageKey.dropFirst("number:".count)))
        } else if storageKey.count == 1 || storageKey.hasSuffix("|lower") {
            // Bare single-character keys are letters only — never treat bare
            // digits as numbers (use number:5).
            self = .letter(storageKey)
        } else {
            return nil
        }
    }
}

struct LearningRound: Codable, Equatable {
    var target: FocusTarget
    var options: [FocusTarget]
    var activityKind: LearningActivityKind
    var segments: [FocusTarget]
    var expectedSequence: [FocusTarget]
    var selectedSequence: [FocusTarget]

    init(
        target: FocusTarget,
        options: [FocusTarget],
        activityKind: LearningActivityKind,
        segments: [FocusTarget] = [],
        expectedSequence: [FocusTarget] = [],
        selectedSequence: [FocusTarget] = []
    ) {
        self.target = target
        self.options = options
        self.activityKind = activityKind
        self.segments = segments
        self.expectedSequence = expectedSequence
        self.selectedSequence = selectedSequence
    }
}
