//
//  AppSettings.swift
//  Pismenka
//
//  App-wide settings
//

import Foundation
import SwiftUI

enum ParentGateMethod: String, Codable, CaseIterable, Identifiable {
    case swipe
    case holdButtons

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .swipe: return "Swipe up"
        case .holdButtons: return "Hold two buttons"
        }
    }
}

enum LowercaseMode: String, Codable, CaseIterable, Identifiable {
    case uppercaseOnly
    case afterUppercaseMastery
    case mixedAfterBothStable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uppercaseOnly: return "Automatic at high levels"
        case .afterUppercaseMastery: return "Lowercase after uppercase"
        case .mixedAfterBothStable: return "Mixed case after both"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .uppercaseOnly:
            return "Uppercase first; Advanced and Expert can still mix lowercase automatically."
        case .afterUppercaseMastery:
            return "Lowercase can start after uppercase mastery."
        case .mixedAfterBothStable:
            return "Mixed-case practice waits until both forms are stable."
        }
    }
}

struct AppSettingsSnapshot: Codable, Equatable {
    var musicEnabled: Bool
    var sfxEnabled: Bool
    var reduceMotionEnabled: Bool
    var confettiEnabled: Bool
    var personalizedCzechLettersEnabled: Bool
    var parentGateMethod: ParentGateMethod
    var remindersEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var lowercaseMode: LowercaseMode
    var modifiedAt: Date

    private enum CodingKeys: String, CodingKey {
        case musicEnabled
        case sfxEnabled
        case reduceMotionEnabled
        case confettiEnabled
        case personalizedCzechLettersEnabled
        case parentGateMethod
        case remindersEnabled
        case reminderHour
        case reminderMinute
        case lowercaseMode
        case modifiedAt
    }

    init(
        musicEnabled: Bool,
        sfxEnabled: Bool,
        reduceMotionEnabled: Bool,
        confettiEnabled: Bool,
        personalizedCzechLettersEnabled: Bool,
        parentGateMethod: ParentGateMethod,
        remindersEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        lowercaseMode: LowercaseMode,
        modifiedAt: Date
    ) {
        self.musicEnabled = musicEnabled
        self.sfxEnabled = sfxEnabled
        self.reduceMotionEnabled = reduceMotionEnabled
        self.confettiEnabled = confettiEnabled
        self.personalizedCzechLettersEnabled = personalizedCzechLettersEnabled
        self.parentGateMethod = parentGateMethod
        self.remindersEnabled = remindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.lowercaseMode = lowercaseMode
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        musicEnabled = try c.decode(Bool.self, forKey: .musicEnabled)
        sfxEnabled = try c.decode(Bool.self, forKey: .sfxEnabled)
        reduceMotionEnabled = try c.decode(Bool.self, forKey: .reduceMotionEnabled)
        confettiEnabled = try c.decode(Bool.self, forKey: .confettiEnabled)
        personalizedCzechLettersEnabled = try c.decodeIfPresent(Bool.self, forKey: .personalizedCzechLettersEnabled) ?? false
        parentGateMethod = try c.decode(ParentGateMethod.self, forKey: .parentGateMethod)
        remindersEnabled = try c.decode(Bool.self, forKey: .remindersEnabled)
        reminderHour = try c.decode(Int.self, forKey: .reminderHour)
        reminderMinute = try c.decode(Int.self, forKey: .reminderMinute)
        lowercaseMode = try c.decode(LowercaseMode.self, forKey: .lowercaseMode)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }
}

class AppSettings: ObservableObject {
    private enum Keys {
        static let musicEnabled = "musicEnabled"
        static let sfxEnabled = "sfxEnabled"
        static let reduceMotionEnabled = "reduceMotionEnabled"
        static let confettiEnabled = "confettiEnabled"
        static let personalizedCzechLettersEnabled = "personalizedCzechLettersEnabled"
        static let hasCompletedFirstLaunchOnboarding = "hasCompletedFirstLaunchOnboarding"
        static let defaultGameLanguage = "defaultGameLanguage"
        static let parentGateMethod = "parentGateMethod"
        static let remindersEnabled = "remindersEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let lowercaseMode = "lowercaseMode"
        static let modifiedAt = "settingsModifiedAt"
    }

    private let defaults: UserDefaults
    private var isApplyingSnapshot = false
    var onSettingsChanged: ((AppSettingsSnapshot) -> Void)?

    @Published var musicEnabled: Bool {
        didSet {
            defaults.set(musicEnabled, forKey: Keys.musicEnabled)
            touch()
        }
    }
    
    @Published var sfxEnabled: Bool {
        didSet {
            defaults.set(sfxEnabled, forKey: Keys.sfxEnabled)
            touch()
        }
    }

    @Published var reduceMotionEnabled: Bool {
        didSet {
            defaults.set(reduceMotionEnabled, forKey: Keys.reduceMotionEnabled)
            touch()
        }
    }

    @Published var confettiEnabled: Bool {
        didSet {
            defaults.set(confettiEnabled, forKey: Keys.confettiEnabled)
            touch()
        }
    }

    @Published var personalizedCzechLettersEnabled: Bool {
        didSet {
            defaults.set(personalizedCzechLettersEnabled, forKey: Keys.personalizedCzechLettersEnabled)
            touch()
        }
    }

    /// Device-local setup state. These values are intentionally not part of
    /// the cloud settings snapshot: onboarding must be completed on each new
    /// installation before a parent decides whether to restore a backup.
    @Published private(set) var hasCompletedFirstLaunchOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedFirstLaunchOnboarding, forKey: Keys.hasCompletedFirstLaunchOnboarding)
        }
    }

    /// The language preselected when a parent creates a new child profile.
    /// Individual profiles still persist their own learning language.
    @Published private(set) var defaultGameLanguage: GameLanguage {
        didSet {
            defaults.set(defaultGameLanguage.rawValue, forKey: Keys.defaultGameLanguage)
        }
    }

    @Published var parentGateMethod: ParentGateMethod {
        didSet {
            defaults.set(parentGateMethod.rawValue, forKey: Keys.parentGateMethod)
            touch()
        }
    }

    @Published var remindersEnabled: Bool {
        didSet {
            defaults.set(remindersEnabled, forKey: Keys.remindersEnabled)
            touch()
        }
    }

    @Published var reminderHour: Int {
        didSet {
            defaults.set(reminderHour, forKey: Keys.reminderHour)
            touch()
        }
    }

    @Published var reminderMinute: Int {
        didSet {
            defaults.set(reminderMinute, forKey: Keys.reminderMinute)
            touch()
        }
    }

    @Published var lowercaseMode: LowercaseMode {
        didSet {
            defaults.set(lowercaseMode.rawValue, forKey: Keys.lowercaseMode)
            touch()
        }
    }

    @Published private(set) var modifiedAt: Date
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Load from UserDefaults with defaults
        self.musicEnabled = defaults.object(forKey: Keys.musicEnabled) as? Bool ?? false
        self.sfxEnabled = defaults.object(forKey: Keys.sfxEnabled) as? Bool ?? true
        self.reduceMotionEnabled = defaults.object(forKey: Keys.reduceMotionEnabled) as? Bool ?? false
        self.confettiEnabled = defaults.object(forKey: Keys.confettiEnabled) as? Bool ?? true
        self.personalizedCzechLettersEnabled = defaults.object(forKey: Keys.personalizedCzechLettersEnabled) as? Bool ?? false
        self.hasCompletedFirstLaunchOnboarding = defaults.object(forKey: Keys.hasCompletedFirstLaunchOnboarding) as? Bool ?? false
        let defaultLanguageRaw = defaults.string(forKey: Keys.defaultGameLanguage) ?? GameLanguage.czech.rawValue
        self.defaultGameLanguage = GameLanguage(rawValue: defaultLanguageRaw)?.resolvedLanguage ?? .czech
        let gateRaw = defaults.string(forKey: Keys.parentGateMethod) ?? ParentGateMethod.swipe.rawValue
        self.parentGateMethod = ParentGateMethod(rawValue: gateRaw) ?? .swipe
        self.remindersEnabled = defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? false
        self.reminderHour = defaults.object(forKey: Keys.reminderHour) as? Int ?? 7
        self.reminderMinute = defaults.object(forKey: Keys.reminderMinute) as? Int ?? 0
        let lowercaseRaw = defaults.string(forKey: Keys.lowercaseMode) ?? LowercaseMode.uppercaseOnly.rawValue
        self.lowercaseMode = LowercaseMode(rawValue: lowercaseRaw) ?? .uppercaseOnly
        self.modifiedAt = defaults.object(forKey: Keys.modifiedAt) as? Date ?? .distantPast
    }

    func completeFirstLaunchOnboarding(language: GameLanguage) {
        defaultGameLanguage = language.resolvedLanguage
        hasCompletedFirstLaunchOnboarding = true
    }

    func snapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            musicEnabled: musicEnabled,
            sfxEnabled: sfxEnabled,
            reduceMotionEnabled: reduceMotionEnabled,
            confettiEnabled: confettiEnabled,
            personalizedCzechLettersEnabled: personalizedCzechLettersEnabled,
            parentGateMethod: parentGateMethod,
            remindersEnabled: remindersEnabled,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            lowercaseMode: lowercaseMode,
            modifiedAt: modifiedAt
        )
    }

    @discardableResult
    func apply(snapshot: AppSettingsSnapshot) -> Bool {
        guard snapshot.modifiedAt > modifiedAt else { return false }
        isApplyingSnapshot = true
        musicEnabled = snapshot.musicEnabled
        sfxEnabled = snapshot.sfxEnabled
        reduceMotionEnabled = snapshot.reduceMotionEnabled
        confettiEnabled = snapshot.confettiEnabled
        personalizedCzechLettersEnabled = snapshot.personalizedCzechLettersEnabled
        parentGateMethod = snapshot.parentGateMethod
        remindersEnabled = snapshot.remindersEnabled
        reminderHour = snapshot.reminderHour
        reminderMinute = snapshot.reminderMinute
        lowercaseMode = snapshot.lowercaseMode
        isApplyingSnapshot = false
        modifiedAt = snapshot.modifiedAt
        defaults.set(modifiedAt, forKey: Keys.modifiedAt)
        onSettingsChanged?(self.snapshot())
        return true
    }

    private func touch() {
        guard !isApplyingSnapshot else { return }
        modifiedAt = Date()
        defaults.set(modifiedAt, forKey: Keys.modifiedAt)
        onSettingsChanged?(snapshot())
    }
}
