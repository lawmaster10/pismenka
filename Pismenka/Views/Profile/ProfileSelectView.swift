//
//  ProfileSelectView.swift
//  Pismenka
//
//  Profile selection screen — main entry point. Each card surfaces the
//  child's per-profile mastery (letters known + day streak) and exposes a
//  parent-gated entry into the parent dashboard / settings via a long-press
//  on the avatar.
//

import SwiftUI

struct ProfileSelectView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var checkpointStore: SessionCheckpointStore

    let onProfileSelected: (Profile) -> Void
    let onPracticeSelected: (Profile, String) -> Void

    @State private var showCreateProfile = false
    @State private var selectedProfileForEdit: Profile?
    @State private var showParentGate = false
    @State private var parentGateAction: ParentGateAction = .create
    @State private var pendingParentGateAction: ParentGateAction?
    @State private var shakeAddButton = false
    @State private var selectedProfileForDashboard: Profile?
    @State private var showSettings = false

    enum ParentGateAction {
        case create
        case openSettings
        case openParentArea(Profile)
        case editProfile(Profile)
    }

    var body: some View {
        ZStack {
            BrandBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                heroHeader

                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let persistenceError = profileManager.persistenceErrorMessage {
                            Text(persistenceError)
                                .font(.brandBody(14, weight: .bold))
                                .foregroundColor(.berryInk)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.roseTint)
                                )
                        }

                        if profileManager.profiles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("First profile")
                                    .brandEyebrowStyle()
                                Text("Add a child to start playing.")
                                    .font(.brandTitleM(20))
                                    .tracking(-0.4)
                                    .foregroundColor(.ink)
                                Text("Use the gear for settings, backup, and recovery.")
                                    .font(.brandBody(14, weight: .semibold))
                                    .foregroundColor(.slate500)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .softCard()
                        }

                        ForEach(profileManager.profiles) { profile in
                            ProfileCardView(
                                profile: profile,
                                onTap: {
                                    HapticService.shared.tap()
                                    onProfileSelected(profile)
                                },
                                onViewResults: {
                                    HapticService.shared.tap()
                                    parentGateAction = .openParentArea(profile)
                                    showParentGate = true
                                },
                                onEditProfile: {
                                    HapticService.shared.tap()
                                    parentGateAction = .editProfile(profile)
                                    showParentGate = true
                                }
                            )
                        }

                        if !profileManager.profiles.isEmpty {
                            Text("Tap a card to play · Hold for parent options.")
                                .font(.brandBody(12, weight: .bold))
                                .foregroundColor(.slate400)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                BrandIconButton(
                    systemImage: "plus",
                    action: {
                        if profileManager.canCreateProfile {
                            HapticService.shared.tap()
                            parentGateAction = .create
                            showParentGate = true
                        } else {
                            HapticService.shared.error()
                            withAnimation(.default) {
                                shakeAddButton = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                shakeAddButton = false
                            }
                        }
                    },
                    size: 70,
                    style: .ink,
                    accessibilityLabel: "Add a profile"
                )
                .modifier(ShakeEffect(shakes: shakeAddButton ? 3 : 0))
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showParentGate, onDismiss: completePendingParentGateAction) {
            ParentGateView(
                method: settings.parentGateMethod,
                onSuccess: {
                    pendingParentGateAction = parentGateAction
                    showParentGate = false
                },
                onCancel: {
                    pendingParentGateAction = nil
                    showParentGate = false
                }
            )
        }
        .sheet(isPresented: $showCreateProfile) {
            CreateProfileView(
                onComplete: { _ in
                    showCreateProfile = false
                },
                onCancel: {
                    showCreateProfile = false
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $selectedProfileForDashboard) { profile in
            ParentDashboardView(
                profile: profile,
                onEdit: {
                    selectedProfileForDashboard = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedProfileForEdit = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
                    }
                },
                onPractice: { letter in
                    selectedProfileForDashboard = nil
                    onPracticeSelected(profile, letter)
                },
                onClose: {
                    selectedProfileForDashboard = nil
                }
            )
        }
        .sheet(item: $selectedProfileForEdit) { profile in
            EditProfileView(
                profile: profile,
                onSave: { updatedProfile in
                    profileManager.updateProfile(updatedProfile)
                    selectedProfileForEdit = nil
                },
                onDelete: {
                    checkpointStore.clear(profileId: profile.id)
                    profileManager.deleteProfile(profile)
                    selectedProfileForEdit = nil
                },
                onResetProgress: {
                    checkpointStore.clear(profileId: profile.id)
                    profileManager.resetAllProgress(profileId: profile.id)
                    selectedProfileForEdit = nil
                },
                onCancel: {
                    selectedProfileForEdit = nil
                }
            )
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi there")
                    .brandEyebrowStyle()
                Text("Písmenka")
                    .font(.brandTitleXL(40))
                    .tracking(-1.6)
                    .foregroundColor(.ink)
            }

            Spacer()

            Button(action: openSettingsGate) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.slate500)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.85)))
                    .overlay(Circle().stroke(Color.creamDeep, lineWidth: 1))
                    .shadow(color: Color.ink.opacity(0.06), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("Open parent settings")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func completePendingParentGateAction() {
        guard let action = pendingParentGateAction else { return }
        pendingParentGateAction = nil

        switch action {
        case .create:
            showCreateProfile = true
        case .openSettings:
            showSettings = true
        case .openParentArea(let profile):
            selectedProfileForDashboard = profile
        case .editProfile(let profile):
            selectedProfileForEdit = profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
        }
    }

    private func openSettingsGate() {
        HapticService.shared.tap()
        parentGateAction = .openSettings
        showParentGate = true
    }
}

// MARK: - Profile Card View

struct ProfileCardView: View {
    let profile: Profile
    let onTap: () -> Void
    let onViewResults: () -> Void
    let onEditProfile: () -> Void

    /// Pre-resolved learning snapshot — same source of truth the dashboard
    /// and game read from. The card deliberately shows only the parent-facing
    /// confident count, not trophies or streaks.
    private var snapshot: ProfileLearningSnapshot { profile.snapshot }
    private var letterKnowledgeSummary: ParentLetterKnowledgeSummary {
        snapshot.parentLetterKnowledgeSummary(alphabetLetters: Set(profile.language.letters))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(profile.colorTheme)
                        .frame(width: 72, height: 72)
                        .shadow(color: profile.colorTheme.opacity(0.35), radius: 10, x: 0, y: 6)
                    Text(profile.avatarId.emoji)
                        .font(.system(size: 40))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile")
                        .brandEyebrowStyle()
                    Text(profile.displayName)
                        .font(.brandTitleL(24))
                        .tracking(-0.6)
                        .foregroundColor(.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(letterKnowledgeSummary.confidentlyKnownCount) / \(letterKnowledgeSummary.totalLetters)")
                        .font(.brandTitleM(22))
                        .tracking(-0.6)
                        .foregroundColor(.ink)
                        .monospacedDigit()
                    Text("Confident")
                        .brandEyebrowStyle()
                }
            }
            .padding(20)
            .softCard(cornerRadius: 28)
        }
        .buttonStyle(ProfileCardButtonStyle())
        .contextMenu {
            Button(action: onViewResults) {
                Label("View results", systemImage: "chart.bar.fill")
            }
            Button(action: onEditProfile) {
                Label("Edit profile", systemImage: "pencil")
            }
        }
        .accessibilityHint("Double tap to play. Press and hold for parent options.")
    }
}

// MARK: - Button Style

struct ProfileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shake Effect Modifier

struct ShakeEffect: GeometryEffect {
    var shakes: Int
    var animatableData: CGFloat {
        get { CGFloat(shakes) }
        set { shakes = Int(newValue) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(CGFloat(shakes) * .pi * 2) * 10
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

#Preview {
    ProfileSelectView(onProfileSelected: { _ in }, onPracticeSelected: { _, _ in })
        .environmentObject(ProfileManager())
        .environmentObject(AppSettings())
        .environmentObject(SessionCheckpointStore())
        .environmentObject(AudioService.shared)
        .environmentObject(NotificationService.shared)
        .environmentObject(FirebaseBackupService())
}
