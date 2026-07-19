//
//  CreateProfileView.swift
//  Pismenka
//
//  Profile creation flow
//

import AuthenticationServices
import SwiftUI

// MARK: - First Launch

struct FirstLaunchOnboardingView: View {
    @EnvironmentObject private var firebaseBackupService: FirebaseBackupService

    let onComplete: (GameLanguage) -> Void

    @State private var step: Step = .language
    @State private var selectedLanguage: GameLanguage = .czech

    private enum Step: Equatable {
        case language
        case backup
    }

    var body: some View {
        ZStack {
            BrandBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    Group {
                        switch step {
                        case .language:
                            languageStep
                        case .backup:
                            backupStep
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var header: some View {
        HStack {
            if step == .backup {
                Button {
                    HapticService.shared.tap()
                    step = .language
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.82)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to language selection")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            HStack(spacing: 8) {
                progressDot(isActive: step == .language)
                progressDot(isActive: step == .backup)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step == .language ? "Step 1 of 2" : "Step 2 of 2")

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func progressDot(isActive: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isActive ? Color.ink : Color.slate400.opacity(0.35))
            .frame(width: isActive ? 28 : 9, height: 9)
    }

    private var languageStep: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text("WELCOME TO PÍSMENKA")
                    .brandEyebrowStyle()
                Text("Which language will your child learn?")
                    .font(.brandTitleXL(34))
                    .tracking(-1.1)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)
                Text("Choose the language used for letters and spoken prompts. You can choose again for every child profile.")
                    .font(.brandBody(15, weight: .semibold))
                    .foregroundColor(.slate500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                LanguageSelectionView(
                    selectedLanguage: $selectedLanguage,
                    accentColor: .sky
                )

                Text("Czech is selected by default. Tap the play buttons to hear a sample.")
                    .font(.brandBody(12, weight: .semibold))
                    .foregroundColor(.slate500)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .softCard()

            Button {
                HapticService.shared.tap()
                step = .backup
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }

    private var backupStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: firebaseBackupService.isSignedIn ? "checkmark.icloud.fill" : "icloud.and.arrow.up.fill")
                    .font(.system(size: 42, weight: .black))
                    .foregroundColor(firebaseBackupService.isSignedIn ? .leaf : .sky)
                    .frame(width: 84, height: 84)
                    .background(
                        Circle()
                            .fill(firebaseBackupService.isSignedIn ? Color.mintTint : Color.skyTint)
                    )

                Text(firebaseBackupService.isSignedIn ? "Your progress is protected" : "Keep their progress safe")
                    .font(.brandTitleXL(32))
                    .tracking(-1.0)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)

                Text("Signing in is optional. Your child can play without an account.")
                    .font(.brandBody(16, weight: .black))
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)

                Text("Without backup, progress can be lost if the app is deleted or you get a new phone.")
                    .font(.brandBody(14, weight: .semibold))
                    .foregroundColor(.slate500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Apple or Google is only for backup. No ads, and we do not use your email for anything else.")
                    .font(.brandBody(14, weight: .semibold))
                    .foregroundColor(.slate500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if firebaseBackupService.isSignedIn {
                    Label(backupStatusMessage, systemImage: "checkmark.circle.fill")
                        .font(.brandBody(14, weight: .black))
                        .foregroundColor(.leaf)
                        .multilineTextAlignment(.center)

                    Button {
                        finishOnboarding()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } else if isFirebaseConfigured {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: firebaseBackupService.configureAppleSignInRequest,
                        onCompletion: firebaseBackupService.handleAppleSignInCompletion
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isSyncing)

                    Button {
                        HapticService.shared.tap()
                        firebaseBackupService.signInWithGoogle()
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.sky)
                            Text("Sign in with Google")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(isSyncing)

                    if shouldShowBackupStatus {
                        Text(backupStatusMessage)
                            .font(.brandBody(12, weight: .semibold))
                            .foregroundColor(backupStatusColor)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Cloud recovery isn't available in this build. You can continue without it.")
                        .font(.brandBody(13, weight: .semibold))
                        .foregroundColor(.slate500)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.75))
                        )
                }

                if !firebaseBackupService.isSignedIn {
                    Button {
                        finishOnboarding()
                    } label: {
                        Text("Not now, continue without backup")
                            .font(.brandBody(14, weight: .black))
                            .foregroundColor(.slate600)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .softCard()
        }
    }

    private var isFirebaseConfigured: Bool {
        if case .notConfigured = firebaseBackupService.status { return false }
        return true
    }

    private var isSyncing: Bool {
        if case .syncing = firebaseBackupService.status { return true }
        return false
    }

    private var shouldShowBackupStatus: Bool {
        switch firebaseBackupService.status {
        case .offline, .failed, .syncing:
            return true
        case .notConfigured, .signedOut, .synced, .restored, .tooLarge:
            return false
        }
    }

    private var backupStatusColor: Color {
        switch firebaseBackupService.status {
        case .failed:
            return .berryInk
        case .offline:
            return .sun
        default:
            return .slate500
        }
    }

    private var backupStatusMessage: String {
        switch firebaseBackupService.status {
        case .notConfigured:
            return "Cloud recovery is not configured."
        case .signedOut:
            return "Choose Apple or Google to turn on backup."
        case .syncing:
            return "Connecting and checking for an existing backup…"
        case .synced:
            return "Cloud backup is ready."
        case .restored:
            return "Your existing progress has been restored."
        case .tooLarge:
            return "The backup is too large to sync automatically."
        case .offline:
            return "You're offline. Check your connection or continue without backup."
        case .failed(let message):
            return message
        }
    }

    private func finishOnboarding() {
        HapticService.shared.success()
        onComplete(selectedLanguage)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brandBody(17, weight: .black))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.ink)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brandBody(16, weight: .black))
            .foregroundColor(.ink)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.creamDeep, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Profile Creation

struct CreateProfileView: View {
    @EnvironmentObject var profileManager: ProfileManager
    
    let onComplete: (Profile) -> Void
    let onCancel: () -> Void
    
    @State private var selectedAvatar: AvatarType?
    @State private var profileName: String = ""
    @State private var selectedLanguage: GameLanguage

    init(
        initialLanguage: GameLanguage = .czech,
        onComplete: @escaping (Profile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        _selectedLanguage = State(initialValue: initialLanguage.resolvedLanguage)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground(accent: selectedAvatar?.themeColor ?? .clear)
                    .ignoresSafeArea()
                    .animation(.easeInOut, value: selectedAvatar)
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 32) {
                            AvatarSelectionView(
                                selectedAvatar: $selectedAvatar,
                                profileName: $profileName,
                                availableAvatars: profileManager.availableAvatars()
                            )

                            LanguageSelectionView(
                                selectedLanguage: $selectedLanguage,
                                accentColor: selectedAvatar?.themeColor ?? .blue
                            )
                        }
                        .padding(.top, 32)
                        .padding(.bottom, 24)
                    }

                    // Create button
                    Button(action: {
                        HapticService.shared.tap()
                        createProfile()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(
                                Circle()
                                    .fill(selectedAvatar != nil ? Color.green : Color.gray)
                            )
                            .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(selectedAvatar == nil)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    private func createProfile() {
        guard let avatar = selectedAvatar else { return }
        
        if let profile = profileManager.createProfile(name: profileName, avatar: avatar, language: selectedLanguage) {
            HapticService.shared.success()
            onComplete(profile)
        }
    }
}

// MARK: - Avatar Selection
struct AvatarSelectionView: View {
    @Binding var selectedAvatar: AvatarType?
    @Binding var profileName: String
    let availableAvatars: [AvatarType]
    
    @FocusState private var isNameFieldFocused: Bool
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon instruction (no text for toddlers)
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            // Name input field
            VStack(spacing: 8) {
                TextField("", text: $profileName, prompt: Text("Name").foregroundColor(.gray.opacity(0.6)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedAvatar?.themeColor ?? Color.gray.opacity(0.3), lineWidth: 2)
                            )
                    )
                    .frame(maxWidth: 200)
                    .focused($isNameFieldFocused)
                    .onChange(of: profileName) { _, newValue in
                        // Limit to max characters
                        if newValue.count > Profile.maxNameLength {
                            profileName = String(newValue.prefix(Profile.maxNameLength))
                        }
                    }
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit {
                        isNameFieldFocused = false
                    }
                
                // Character counter
                Text("\(profileName.count)/\(Profile.maxNameLength)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.gray)
            }
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AvatarType.allCases, id: \.self) { avatar in
                    let isAvailable = availableAvatars.contains(avatar)
                    
                    Button(action: {
                        if isAvailable {
                            HapticService.shared.select()
                            withAnimation(.spring(response: 0.3)) {
                                selectedAvatar = avatar
                            }
                            // Dismiss keyboard when selecting avatar
                            isNameFieldFocused = false
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(avatar.backgroundColor)
                                .frame(width: 110, height: 110)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedAvatar == avatar ? avatar.themeColor : Color.clear,
                                            lineWidth: 6
                                        )
                                )
                                .shadow(
                                    color: selectedAvatar == avatar ? avatar.themeColor.opacity(0.5) : Color.clear,
                                    radius: 10
                                )
                            
                            Text(avatar.emoji)
                                .font(.system(size: 55))
                            
                            if !isAvailable {
                                // Overlay for unavailable avatars
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 110, height: 110)
                                
                                Image(systemName: "xmark")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .disabled(!isAvailable)
                    .scaleEffect(selectedAvatar == avatar ? 1.1 : 1.0)
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Language Selection

struct LanguageSelectionView: View {
    @EnvironmentObject var audioService: AudioService

    @Binding var selectedLanguage: GameLanguage
    let accentColor: Color

    private let languages: [GameLanguage] = [.czech, .english]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(languages, id: \.self) { language in
                VStack(spacing: 10) {
                    Button(action: {
                        HapticService.shared.select()
                        withAnimation(.spring(response: 0.3)) {
                            selectedLanguage = language
                        }
                    }) {
                        VStack(spacing: 5) {
                            Text(language.displayFlag)
                                .font(.system(size: 42))
                            Text(language.accessibilityName)
                                .font(.brandBody(14, weight: .black))
                                .foregroundColor(.ink)
                        }
                        .frame(width: 104, height: 84)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(selectedLanguage == language ? 0.95 : 0.55))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedLanguage == language ? accentColor : Color.clear, lineWidth: 4)
                                )
                        )
                        .scaleEffect(selectedLanguage == language ? 1.04 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.accessibilityName)
                    .accessibilityAddTraits(selectedLanguage == language ? .isSelected : [])

                    Button {
                        HapticService.shared.tap()
                        audioService.playLetter("A", language: language)
                    } label: {
                        Label("Hear A", systemImage: "play.fill")
                            .font(.brandBody(12, weight: .black))
                            .foregroundColor(.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 90)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.creamDeep, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(language.accessibilityName) letter sound")
                }
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                )
            }
        }
    }
}

private extension GameLanguage {
    var accessibilityName: String {
        switch self {
        case .english: return "English"
        case .czech: return "Czech"
        case .system: return resolvedLanguage.accessibilityName
        }
    }
}

#Preview {
    CreateProfileView(onComplete: { _ in }, onCancel: {})
        .environmentObject(ProfileManager())
        .environmentObject(AudioService.shared)
}
