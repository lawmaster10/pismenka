//
//  CreateProfileView.swift
//  Pismenka
//
//  Profile creation flow
//

import SwiftUI

struct CreateProfileView: View {
    @EnvironmentObject var profileManager: ProfileManager
    
    let onComplete: (Profile) -> Void
    let onCancel: () -> Void
    
    @State private var selectedAvatar: AvatarType?
    @State private var profileName: String = ""
    @State private var selectedLanguage: GameLanguage = .system.resolvedLanguage
    
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
    @Binding var selectedLanguage: GameLanguage
    let accentColor: Color

    private let languages: [GameLanguage] = [.english, .czech]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(languages, id: \.self) { language in
                Button(action: {
                    HapticService.shared.select()
                    withAnimation(.spring(response: 0.3)) {
                        selectedLanguage = language
                    }
                }) {
                    Text(language.displayFlag)
                        .font(.system(size: 38))
                        .frame(width: 70, height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(selectedLanguage == language ? 0.95 : 0.55))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(selectedLanguage == language ? accentColor : Color.clear, lineWidth: 4)
                                )
                        )
                        .scaleEffect(selectedLanguage == language ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.accessibilityName)
                .accessibilityAddTraits(selectedLanguage == language ? .isSelected : [])
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
}
