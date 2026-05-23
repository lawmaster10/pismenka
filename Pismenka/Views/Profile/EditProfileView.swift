//
//  EditProfileView.swift
//  Pismenka
//
//  Parent-only profile editor. Surfaces the new mastery model
//  (letters mastered + level + day-streak) and exposes destructive actions
//  behind explicit confirmation: Reset Progress (re-runs calibration) and
//  Delete (removes profile).
//

import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State var profile: Profile
    @State private var editedName: String = ""
    @State private var showAvatarPicker = false

    let onSave: (Profile) -> Void
    let onDelete: () -> Void
    let onResetProgress: () -> Void
    let onCancel: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showResetConfirmation = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground(accent: profile.colorTheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 12) {
                            Button(action: {
                                HapticService.shared.tap()
                                isNameFieldFocused = false
                                withAnimation(.spring(response: 0.3)) {
                                    showAvatarPicker.toggle()
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(profile.colorTheme)
                                        .frame(width: 120, height: 120)
                                        .shadow(color: profile.colorTheme.opacity(0.4), radius: 10)

                                    Text(profile.avatarId.emoji)
                                        .font(.system(size: 70))
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(profile.colorTheme)
                                        .background(Circle().fill(Color.white))
                                        .offset(x: -4, y: -4)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Change avatar")

                            Text("Tap avatar to change")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)

                            if showAvatarPicker {
                                avatarPicker
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.top, 16)

                        VStack(spacing: 8) {
                            TextField("", text: $editedName, prompt: Text("Name").foregroundColor(.gray.opacity(0.6)))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(profile.colorTheme, lineWidth: 2)
                                        )
                                )
                                .frame(maxWidth: 200)
                                .focused($isNameFieldFocused)
                                .onChange(of: editedName) { _, newValue in
                                    if newValue.count > Profile.maxNameLength {
                                        editedName = String(newValue.prefix(Profile.maxNameLength))
                                    }
                                    profile.name = editedName
                                }
                                .keyboardType(.asciiCapable)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    isNameFieldFocused = false
                                }

                            Text("\(editedName.count)/\(Profile.maxNameLength)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.gray)
                        }

                        // Mastery summary
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                Text(profile.alphabetLevel.badgeEmoji).font(.system(size: 30))
                                Text(profile.alphabetLevel.displayName)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(profile.alphabetLevel.badgeColor)
                            }
                            HStack(spacing: 24) {
                                masteryStat(
                                    icon: "star.fill",
                                    color: .yellow,
                                    value: "\(profile.letterMasteredCount)",
                                    label: "Letters"
                                )
                                masteryStat(
                                    icon: "flame.fill",
                                    color: .orange,
                                    value: "\(profile.bestDailyStreak)",
                                    label: "Best streak"
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.6))
                        )
                        .padding(.horizontal)

                        Spacer(minLength: 24)

                        // Reset progress
                        Button(action: {
                            HapticService.shared.warning()
                            showResetConfirmation = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset progress")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.15))
                            )
                        }

                        // Delete profile
                        Button(action: {
                            HapticService.shared.warning()
                            showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.red))
                                .shadow(color: .red.opacity(0.3), radius: 8)
                        }
                        .padding(.bottom, 40)
                    }
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

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticService.shared.success()
                        onSave(profile)
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
            .alert("Delete profile?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    HapticService.shared.error()
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes \(profile.displayName)'s profile, letter progress, notes, settings for this child, and trophies.")
            }
            .alert("Reset progress?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    HapticService.shared.warning()
                    onResetProgress()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(profile.displayName) will start over with calibration. Letter progress and current streak are removed. Best streak and level trophies are kept.")
            }
            .onAppear {
                editedName = profile.name
            }
        }
    }

    private var avatarPicker: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(AvatarType.allCases, id: \.self) { avatar in
                let isAvailable = editableAvatars.contains(avatar)

                Button(action: {
                    guard isAvailable else {
                        HapticService.shared.error()
                        return
                    }
                    HapticService.shared.select()
                    withAnimation(.spring(response: 0.3)) {
                        profile.avatarId = avatar
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(avatar.backgroundColor)
                            .frame(width: 82, height: 82)
                            .overlay(
                                Circle()
                                    .stroke(
                                        profile.avatarId == avatar ? avatar.themeColor : Color.clear,
                                        lineWidth: 5
                                    )
                            )
                            .shadow(
                                color: profile.avatarId == avatar ? avatar.themeColor.opacity(0.45) : Color.clear,
                                radius: 8
                            )

                        Text(avatar.emoji)
                            .font(.system(size: 42))

                        if !isAvailable {
                            Circle()
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 82, height: 82)
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .scaleEffect(profile.avatarId == avatar ? 1.08 : 1.0)
                .accessibilityLabel(avatar.displayName)
                .accessibilityAddTraits(profile.avatarId == avatar ? .isSelected : [])
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.55)))
        .padding(.horizontal, 40)
    }

    private var editableAvatars: Set<AvatarType> {
        let usedByOtherProfiles = Set(
            profileManager.profiles
                .filter { $0.id != profile.id }
                .map(\.avatarId)
        )
        return Set(AvatarType.allCases.filter { !usedByOtherProfiles.contains($0) })
    }

    private func masteryStat(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    EditProfileView(
        profile: Profile(avatarId: .lion),
        onSave: { _ in },
        onDelete: {},
        onResetProgress: {},
        onCancel: {}
    )
    .environmentObject(ProfileManager())
}
