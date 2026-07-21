//
//  PismenkaApp.swift
//  Pismenka
//
//  A profile-based adaptive letter learning game for toddlers (3-5).
//

import SwiftUI
import FirebaseCore
import UIKit

final class PismenkaAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configureIfPossible()
        return true
    }
}

@main
struct PismenkaApp: App {
    @UIApplicationDelegateAdaptor(PismenkaAppDelegate.self) private var appDelegate

    @StateObject private var profileManager = ProfileManager()
    @StateObject private var audioService = AudioService.shared
    @StateObject private var settings = AppSettings()
    @StateObject private var checkpointStore = SessionCheckpointStore()
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var firebaseBackupService = FirebaseBackupService()

    init() {
        Task { @MainActor in
            #if DEBUG
            AudioService.shared.validateAssets()
            #endif
            try? await Task.sleep(nanoseconds: 250_000_000)
            await AudioService.shared.preloadLazily()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileManager)
                .environmentObject(audioService)
                .environmentObject(settings)
                .environmentObject(checkpointStore)
                .environmentObject(notificationService)
                .environmentObject(firebaseBackupService)
                .preferredColorScheme(.light)
                .onAppear {
                    audioService.setPersonalizedCzechLettersEnabled(settings.personalizedCzechLettersEnabled)
                    firebaseBackupService.start(profileManager: profileManager, settings: settings)
                    notificationService.updateDailyReminder(
                        enabled: settings.remindersEnabled,
                        layer: settings.activeLearningLayer
                    )
                }
                .onChange(of: settings.personalizedCzechLettersEnabled) { _, enabled in
                    audioService.setPersonalizedCzechLettersEnabled(enabled)
                }
                .onChange(of: settings.remindersEnabled) { _, enabled in
                    notificationService.updateDailyReminder(
                        enabled: enabled,
                        layer: settings.activeLearningLayer
                    )
                }
                .onChange(of: settings.activeLearningLayer) { _, layer in
                    notificationService.updateDailyReminder(
                        enabled: settings.remindersEnabled,
                        layer: layer
                    )
                }
                .onOpenURL { url in
                    _ = firebaseBackupService.handleOpenURL(url)
                }
        }
    }
}

// MARK: - Content View (Root Navigation)

/// Root navigator. Owns the four-screen state machine
/// `profileSelect → calibration → game → sessionEnd` and forwards the
/// `SessionPlan` produced by `ProfileManager.previewSessionPlan` into the
/// game so the game stays a pure consumer of session shape.
struct ContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var checkpointStore: SessionCheckpointStore
    @EnvironmentObject var settings: AppSettings

    @State private var currentScreen: AppScreen = .profileSelect
    @State private var selectedProfile: Profile?
    @State private var activeSessionPlan: SessionPlan?
    @State private var activeGameSnapshot: GameEngineSnapshot?
    @State private var activeCalibrationSnapshot: CalibrationSnapshot?
    @State private var lastSummary: SessionSummary?
    @State private var hasPreparedFirstLaunchState = false

    var body: some View {
        ZStack {
            if !hasPreparedFirstLaunchState {
                BrandBackground()
                    .ignoresSafeArea()
            } else if shouldShowFirstLaunchOnboarding {
                FirstLaunchOnboardingView { language in
                    settings.completeFirstLaunchOnboarding(language: language)
                }
                .transition(.opacity)
            } else {
                switch currentScreen {
                case .profileSelect:
                    ProfileSelectView(
                        onProfileSelected: { profile in
                            handleProfileSelection(profile)
                        },
                        onPracticeSelected: { profile, unitKey in
                            startPractice(for: profile, unitKey: unitKey)
                        }
                    )
                    .transition(.opacity)

                case .calibration:
                    if let profile = selectedProfile {
                        CalibrationView(
                            profile: profile,
                            layer: settings.activeLearningLayer,
                            restoredSnapshot: activeCalibrationSnapshot,
                            onComplete: {
                                checkpointStore.clear(profileId: profile.id, layer: settings.activeLearningLayer)
                                activeCalibrationSnapshot = nil
                                // Re-fetch (calibration just flipped the flag).
                                let updated = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
                                selectedProfile = updated
                                startGame(for: updated)
                            },
                            onHome: {
                                checkpointStore.clear(profileId: profile.id, layer: settings.activeLearningLayer)
                                resetNavigationState()
                            }
                        )
                        .transition(.opacity)
                    } else {
                        navigationRecoveryView
                    }

                case .game:
                    if let profile = selectedProfile, let plan = activeSessionPlan {
                        GameView(
                            profile: profile,
                            plan: plan,
                            profileManager: profileManager,
                            restoredSnapshot: activeGameSnapshot,
                            onExit: { summary in
                                checkpointStore.clear(profileId: profile.id, layer: plan.primaryLayer)
                                activeGameSnapshot = nil
                                lastSummary = summary
                                currentScreen = .sessionEnd
                            },
                            onHome: {
                                checkpointStore.clear(profileId: profile.id, layer: plan.primaryLayer)
                                resetNavigationState()
                            },
                            onWeeklyTestCompletedByParent: {
                                checkpointStore.clear(profileId: profile.id, layer: plan.primaryLayer)
                                let updated = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
                                startGame(for: updated)
                            }
                        )
                        .id(
                            plan.dayStreakCount.description
                            + (plan.focusTarget?.storageKey ?? plan.focusLetter ?? "")
                            + plan.activityKind.rawValue
                            + String(describing: plan.mode)
                            + ":\(plan.dailyPracticeKind.rawValue):\(plan.dailyGoalTarget)"
                            + ":\(plan.dailySpotlightLetter ?? "")"
                            + ":\(plan.dailyGoalStartCount):\(plan.dailyGoalClaimedCount)"
                        )
                        .transition(.move(edge: .trailing))
                    } else {
                        navigationRecoveryView
                    }

                case .sessionEnd:
                    if let profile = selectedProfile, let summary = lastSummary {
                        SessionEndView(
                            profile: profile,
                            summary: summary,
                            onPlayAgain: {
                                startGame(for: profile)
                            },
                            onHome: {
                                checkpointStore.clear(profileId: profile.id)
                                resetNavigationState()
                            }
                        )
                        .transition(.scale)
                    } else {
                        navigationRecoveryView
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentScreen)
        .animation(.easeInOut(duration: 0.3), value: shouldShowFirstLaunchOnboarding)
        .onAppear {
            migrateExistingInstallationIfNeeded()
            hasPreparedFirstLaunchState = true
            restoreCheckpointIfPossible()
        }
        .onChange(of: profileManager.profiles.map(\.id)) { _, _ in
            recoverIfSelectedProfileDisappeared()
        }
    }

    private var shouldShowFirstLaunchOnboarding: Bool {
        !settings.hasCompletedFirstLaunchOnboarding
    }

    private var navigationRecoveryView: some View {
        Color.clear
            .onAppear(perform: resetNavigationState)
    }

    private func handleProfileSelection(_ profile: Profile) {
        selectedProfile = profile
        if let checkpoint = checkpointStore.checkpoint(for: profile.id, layer: settings.activeLearningLayer) {
            restore(checkpoint: checkpoint, profile: profile)
            return
        }
        if hasCompletedActiveLayerCalibration(profile) {
            withoutScreenAnimation {
                startGame(for: profile)
            }
        } else {
            activeCalibrationSnapshot = nil
            currentScreen = .calibration
        }
    }

    /// Calibration completion flag for the currently selected learning layer.
    private func hasCompletedActiveLayerCalibration(_ profile: Profile) -> Bool {
        settings.activeLearningLayer == .numbers
            ? profile.hasCompletedNumberCalibration
            : profile.hasCompletedCalibration
    }

    private func restoreCheckpointIfPossible() {
        guard !shouldShowFirstLaunchOnboarding else { return }
        guard currentScreen == .profileSelect,
              let checkpoint = checkpointStore.checkpoint(for: settings.activeLearningLayer),
              let profile = profileManager.profiles.first(where: { $0.id == checkpoint.profileId }) else {
            return
        }
        restore(checkpoint: checkpoint, profile: profile)
    }

    /// Profiles predate the first-launch flow, so existing installations
    /// should keep opening directly to profile selection after an app update.
    private func migrateExistingInstallationIfNeeded() {
        guard !settings.hasCompletedFirstLaunchOnboarding,
              let existingProfile = profileManager.profiles.first else {
            return
        }
        settings.completeFirstLaunchOnboarding(language: existingProfile.language)
    }

    private func restore(checkpoint: SessionCheckpointEnvelope, profile: Profile) {
        selectedProfile = profile
        switch checkpoint.kind {
        case .calibration:
            let calibrationDone = checkpoint.learningLayer == .numbers
                ? profile.hasCompletedNumberCalibration
                : profile.hasCompletedCalibration
            guard !calibrationDone, let snapshot = checkpoint.calibration else {
                checkpointStore.clear(profileId: profile.id, layer: checkpoint.learningLayer)
                return
            }
            activeCalibrationSnapshot = snapshot
            activeGameSnapshot = nil
            currentScreen = .calibration
        case .game:
            guard let plan = checkpoint.sessionPlan, let snapshot = checkpoint.game else {
                checkpointStore.clear(profileId: profile.id, layer: checkpoint.learningLayer)
                return
            }
            activeSessionPlan = plan
            activeGameSnapshot = snapshot
            activeCalibrationSnapshot = nil
            currentScreen = .game
        }
    }

    /// Builds a fresh `SessionPlan` preview and pushes the game screen. The
    /// day-streak / focus-day state is committed only after the first answer.
    private func startGame(for profile: Profile) {
        let plan = profileManager.previewSessionPlan(
            profileId: profile.id,
            lowercaseMode: settings.lowercaseMode,
            layer: settings.activeLearningLayer
        )
        selectedProfile = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
        activeSessionPlan = plan
        activeGameSnapshot = nil
        currentScreen = .game
    }

    /// `unitKey` is a letter or a number string depending on the active
    /// learning layer — the dashboards only hand out keys matching the layer
    /// they were opened for.
    private func startPractice(for profile: Profile, unitKey: String) {
        let plan = settings.activeLearningLayer == .numbers
            ? profileManager.startPracticeSession(profileId: profile.id, number: unitKey)
            : profileManager.startPracticeSession(profileId: profile.id, letter: unitKey)
        let updated = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
        selectedProfile = updated
        activeSessionPlan = plan
        activeGameSnapshot = nil
        currentScreen = .game
    }

    private func withoutScreenAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }

    private func resetNavigationState() {
        selectedProfile = nil
        activeSessionPlan = nil
        activeGameSnapshot = nil
        activeCalibrationSnapshot = nil
        lastSummary = nil
        currentScreen = .profileSelect
    }

    private func recoverIfSelectedProfileDisappeared() {
        guard let selectedProfile,
              currentScreen != .profileSelect,
              !profileManager.profiles.contains(where: { $0.id == selectedProfile.id }) else {
            return
        }
        checkpointStore.clear(profileId: selectedProfile.id)
        resetNavigationState()
    }
}

// MARK: - App Screen Enum

enum AppScreen {
    case profileSelect
    case calibration
    case game
    case sessionEnd
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(ProfileManager())
        .environmentObject(AudioService.shared)
        .environmentObject(AppSettings())
        .environmentObject(SessionCheckpointStore())
        .environmentObject(NotificationService.shared)
        .environmentObject(FirebaseBackupService())
}
