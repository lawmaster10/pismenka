//
//  SettingsView.swift
//  Pismenka
//
//  Parent-gated settings sheet (music + SFX toggles). Relocated out of the
//  deleted GameMenuView so it can be presented from the parent-dashboard
//  entry point in ProfileSelectView.
//

import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var audioService: AudioService
    @EnvironmentObject var checkpointStore: SessionCheckpointStore
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var firebaseBackupService: FirebaseBackupService
    @Environment(\.dismiss) var dismiss

    let profile: Profile?

    @State private var showAudioCheck = false
    @State private var shareURL: ShareURL?
    @State private var showImporter = false
    @State private var importEnvelope: ProfileExportEnvelope?
    @State private var importError: String?
    @State private var showImportMode = false
    @State private var showPersonalizedLettersCode = false

    init(profile: Profile? = nil) {
        self.profile = profile
    }

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parent area".uppercased())
                                .brandEyebrowStyle()
                            Text("Settings")
                                .font(.brandTitleXL(34))
                                .tracking(-1.2)
                                .foregroundColor(.ink)
                        }
                        .padding(.horizontal, 4)

                        settingsGroup(title: "Play") {
                            SettingsToggle(title: "Music", subtitle: "Off by default for calm play.", icon: "music.note", isOn: $settings.musicEnabled)
                            SettingsToggle(title: "Voice and sounds", subtitle: "Letter prompts and feedback sounds.", icon: "speaker.wave.2.fill", isOn: $settings.sfxEnabled)
                            PersonalizedLettersRow(isOn: settings.personalizedCzechLettersEnabled) {
                                if settings.personalizedCzechLettersEnabled {
                                    settings.personalizedCzechLettersEnabled = false
                                    audioService.setPersonalizedCzechLettersEnabled(false)
                                } else {
                                    showPersonalizedLettersCode = true
                                }
                            }
                            SettingsToggle(title: "Reduce motion", subtitle: "Softens confetti, shaking, and bouncy effects.", icon: "figure.walk.motion", isOn: $settings.reduceMotionEnabled)
                            SettingsToggle(title: "Confetti", subtitle: "Celebrations stay gentle when off.", icon: "sparkles", isOn: $settings.confettiEnabled)
                        }

                        settingsGroup(title: "Learning") {
                            PickerRow(title: "Parent gate", selection: $settings.parentGateMethod)
                            PickerRow(
                                title: "Case practice",
                                subtitle: settings.lowercaseMode.settingsSubtitle,
                                selection: $settings.lowercaseMode
                            )
                            SettingsToggle(title: "Daily reminder", subtitle: "7:00 AM local time. Parent opt-in, no streak pressure.", icon: "bell.badge", isOn: $settings.remindersEnabled)
                                .onChange(of: settings.remindersEnabled) { _, _ in updateReminder() }
                        }

                        settingsGroup(title: "Backup") {
                            ButtonRow(title: "Audio check", subtitle: "Play prompts and diagnose missing audio.", icon: "waveform") {
                                audioService.validateAssets()
                                showAudioCheck = true
                            }
                            ButtonRow(title: "Export backup", subtitle: "Share a local JSON backup.", icon: "square.and.arrow.up") {
                                exportProfiles()
                            }
                            ButtonRow(title: "Import backup", subtitle: "Replace or merge from JSON.", icon: "square.and.arrow.down") {
                                showImporter = true
                            }
                            FirebaseBackupStatusRow(
                                status: firebaseBackupService.status,
                                signedInEmail: firebaseBackupService.signedInEmail,
                                onAppleRequest: firebaseBackupService.configureAppleSignInRequest,
                                onAppleCompletion: firebaseBackupService.handleAppleSignInCompletion,
                                onGoogleSignIn: { firebaseBackupService.signInWithGoogle() },
                                onSignOut: { firebaseBackupService.signOut() },
                                onBackupNow: { firebaseBackupService.backupNow() },
                                onRestoreNow: { firebaseBackupService.restoreNow() }
                            )
                            ButtonRow(title: "Copy diagnostic summary", subtitle: "Progress summary for support.", icon: "doc.on.doc") {
                                UIPasteboard.general.string = diagnosticSummary()
                            }
                        }

                        if let importError {
                            Text(importError)
                                .font(.brandBody(13, weight: .semibold))
                                .foregroundColor(.berryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.roseTint)
                                )
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.slate500)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    .accessibilityLabel("Close settings")
                }
            }
            .sheet(isPresented: $showAudioCheck) {
                AudioCheckView(profile: profile)
                    .environmentObject(audioService)
                    .environmentObject(settings)
            }
            .sheet(item: $shareURL) { item in
                ShareSheet(activityItems: [item.url])
            }
            .sheet(isPresented: $showPersonalizedLettersCode) {
                PersonalizedLettersCodeSheet {
                    settings.personalizedCzechLettersEnabled = true
                    audioService.setPersonalizedCzechLettersEnabled(true)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImportResult(result)
            }
            .confirmationDialog("Import backup", isPresented: $showImportMode, titleVisibility: .visible) {
                Button("Replace all profiles", role: .destructive) { applyImport(mode: .replaceAll) }
                Button("Merge with existing profiles") { applyImport(mode: .merge) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Importing clears active resume checkpoints because profile progress may change. Merging updates matching profiles and adds new ones up to the profile limit.")
            }
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .brandEyebrowStyle()
                .padding(.horizontal, 4)
            VStack(spacing: 12) {
                content()
            }
        }
    }

    private func updateReminder() {
        notificationService.updateDailyReminder(enabled: settings.remindersEnabled)
    }

    private func exportProfiles() {
        do {
            let data = try ProfileExportService.exportData(profiles: profileManager.profiles)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pismenka-backup-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            shareURL = ShareURL(url: url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Písmenka couldn't access that backup file. Try moving it to On My iPhone or iCloud Drive and importing again."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            importEnvelope = try ProfileExportService.decodeImport(data)
            importError = nil
            showImportMode = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func applyImport(mode: ProfileImportMode) {
        guard let importEnvelope else { return }
        do {
            let merged = try ProfileExportService.merged(
                existing: profileManager.profiles,
                imported: importEnvelope.profiles,
                mode: mode
            )
            profileManager.replaceProfiles(merged)
            checkpointStore.clear()
            self.importEnvelope = nil
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func diagnosticSummary() -> String {
        profileManager.profiles.map { profile in
            "\(profile.displayName): \(profile.letterMasteredCount)/\(profile.language.letters.count) mastered, streak \(profile.dailyStreakCount), best \(profile.bestDailyStreak)"
        }
        .joined(separator: "\n")
    }
}

struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Settings Toggle

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: {
            HapticService.shared.select()
            isOn.toggle()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isOn ? Color.leaf.opacity(0.15) : Color.creamDeep.opacity(0.6))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(isOn ? .leaf : .slate500)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.brandBody(16, weight: .black))
                        .foregroundColor(.ink)
                    Text(subtitle)
                        .font(.brandBody(12, weight: .semibold))
                        .foregroundColor(.slate500)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.leaf : Color.slate400.opacity(0.35))
                        .frame(width: 56, height: 32)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .offset(x: isOn ? 12 : -12)
                        .shadow(color: Color.ink.opacity(0.18), radius: 3, x: 0, y: 1)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.05), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct PersonalizedLettersRow: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticService.shared.select()
            action()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isOn ? Color.leaf.opacity(0.15) : Color.creamDeep.opacity(0.6))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(isOn ? .leaf : .slate500)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalized letters")
                        .font(.brandBody(16, weight: .black))
                        .foregroundColor(.ink)
                    Text(isOn ? "Čermák family prompts are active." : "Use the standard Czech examples by default.")
                        .font(.brandBody(12, weight: .semibold))
                        .foregroundColor(.slate500)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(isOn ? "On" : "Off")
                    .font(.brandBody(13, weight: .black))
                    .foregroundColor(isOn ? .leaf : .slate500)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isOn ? Color.leaf.opacity(0.12) : Color.slate400.opacity(0.12))
                    )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.05), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Personalized letters")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct PersonalizedLettersCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var errorMessage: String?
    @FocusState private var isCodeFieldFocused: Bool

    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            BrandBackground().ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(.sun)
                        .frame(width: 70, height: 70)
                        .background(Circle().fill(Color.amberTint))

                    Text("Personalized letters")
                        .font(.brandTitleL(28))
                        .tracking(-0.8)
                        .foregroundColor(.ink)
                    Text("Enter the 4-digit family code to unlock the Čermák letter prompts.")
                        .font(.brandBody(15, weight: .semibold))
                        .foregroundColor(.slate500)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ZStack {
                        TextField("", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($isCodeFieldFocused)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .accessibilityHidden(true)

                        HStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { index in
                                codeDigitBox(at: index)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isCodeFieldFocused = true
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Four digit family code")
                    .accessibilityValue("\(code.count) of 4 digits entered")

                    Text("4 digits")
                        .font(.brandEyebrow(11))
                        .tracking(2.0)
                        .foregroundColor(errorMessage == nil ? .slate400 : .berryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill((errorMessage == nil ? Color.amberTint : Color.roseTint).opacity(0.85))
                        )
                }
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    code = String(digits.prefix(4))
                    errorMessage = nil
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.brandBody(13, weight: .black))
                        .foregroundColor(.berryInk)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())

                    Button("Unlock") {
                        unlock()
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(code.count < 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.16), radius: 24, x: 0, y: 14)
            .padding(24)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isCodeFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func codeDigitBox(at index: Int) -> some View {
        let digits = Array(code)
        let digit = index < digits.count ? String(digits[index]) : ""
        let isActive = isCodeFieldFocused && index == min(code.count, 3)
        let hasError = errorMessage != nil

        Text(digit.isEmpty ? " " : digit)
            .font(.brandTitleL(30))
            .monospacedDigit()
            .foregroundColor(.ink)
            .frame(width: 58, height: 66)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.amberMist],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor(isActive: isActive, hasError: hasError), lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: Color.ink.opacity(isActive ? 0.12 : 0.07), radius: isActive ? 12 : 8, x: 0, y: 6)
            .scaleEffect(isActive ? 1.04 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isActive)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: digit)
    }

    private func borderColor(isActive: Bool, hasError: Bool) -> Color {
        if hasError { return .berryInk.opacity(0.65) }
        if isActive { return .sky.opacity(0.75) }
        return .creamDeep
    }

    private func unlock() {
        guard code == "2436" else {
            HapticService.shared.warning()
            errorMessage = code.count < 4 ? "Enter all 4 digits." : "That 4-digit code didn't work."
            isCodeFieldFocused = true
            return
        }

        HapticService.shared.success()
        onUnlock()
        dismiss()
    }
}

struct PickerRow<Option>: View where Option: CaseIterable & Identifiable & Hashable, Option.AllCases: RandomAccessCollection {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: Option

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.brandBody(16, weight: .black))
                    .foregroundColor(.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.brandBody(12, weight: .semibold))
                        .foregroundColor(.slate500)
                }
            }
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(Option.allCases) { option in
                    Text(displayName(for: option)).tag(option)
                }
            }
            .tint(.ink)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.ink.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    private func displayName(for option: Option) -> String {
        if let gate = option as? ParentGateMethod { return gate.displayName }
        if let mode = option as? LowercaseMode { return mode.displayName }
        return String(describing: option)
    }
}

struct FirebaseBackupStatusRow: View {
    let status: FirebaseBackupStatus
    let signedInEmail: String?
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void
    let onGoogleSignIn: () -> Void
    let onSignOut: () -> Void
    let onBackupNow: () -> Void
    let onRestoreNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud recovery")
                        .font(.brandBody(16, weight: .black))
                        .foregroundColor(.ink)
                    Text(subtitle)
                        .font(.brandBody(12, weight: .semibold))
                        .foregroundColor(.slate500)
                        .fixedSize(horizontal: false, vertical: true)
                    if let signedInEmail {
                        Text(signedInEmail)
                            .font(.brandBody(11, weight: .semibold))
                            .foregroundColor(.slate400)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if showsSyncedCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.leaf)
                        .accessibilityLabel("Cloud backup is up to date")
                }
            }

            HStack(spacing: 10) {
                if signedInEmail == nil {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: onAppleRequest,
                        onCompletion: onAppleCompletion
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(width: 210, height: 44)

                    Button("Sign in with Google", action: onGoogleSignIn)
                        .buttonStyle(BrandSecondaryButtonStyle())
                } else {
                    Button("Sync now", action: onBackupNow)
                        .buttonStyle(BrandSecondaryButtonStyle())
                    Button("Restore", action: onRestoreNow)
                        .buttonStyle(BrandSecondaryButtonStyle())
                    Button("Sign out", role: .destructive, action: onSignOut)
                        .buttonStyle(BrandSecondaryButtonStyle(tint: .berryInk))
                }
            }
            .disabled(isSyncing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.ink.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    private var iconName: String {
        switch status {
        case .notConfigured:
            return "exclamationmark.triangle"
        case .signedOut:
            return "person.crop.circle.badge.plus"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .restored:
            return "arrow.down.circle.fill"
        case .offline:
            return "wifi.slash"
        case .tooLarge, .failed:
            return "exclamationmark.icloud"
        }
    }

    private var iconColor: Color {
        switch status {
        case .notConfigured, .failed, .tooLarge, .offline:
            return .sun
        case .syncing:
            return .sky
        case .synced, .restored:
            return .leaf
        case .signedOut:
            return .slate500
        }
    }

    private var subtitle: String {
        switch status {
        case .notConfigured:
            return "Add GoogleService-Info.plist from Firebase to enable cloud recovery."
        case .signedOut:
            return "Without backup, progress can be lost after delete or a new phone. Sign-in is only for backup."
        case .syncing:
            return "Syncing cloud backup."
        case .synced(let date):
            return "Up to date. Last backed up \(Self.shortDateFormatter.string(from: date))."
        case .restored(let date):
            return "Restored and up to date from \(Self.shortDateFormatter.string(from: date))."
        case .tooLarge:
            return "Progress is too large for automatic cloud backup. Export backup still works."
        case .offline:
            return "No internet connection. Cloud recovery will retry when you're back online."
        case .failed(let message):
            return message
        }
    }

    private var showsSyncedCheckmark: Bool {
        switch status {
        case .synced, .restored:
            return true
        case .notConfigured, .signedOut, .syncing, .tooLarge, .offline, .failed:
            return false
        }
    }

    private var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ButtonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.sky.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.sky)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.brandBody(16, weight: .black))
                        .foregroundColor(.ink)
                    Text(subtitle)
                        .font(.brandBody(12, weight: .semibold))
                        .foregroundColor(.slate500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.slate400)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.creamDeep.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.05), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Solid ink primary CTA used inside settings rows. Mirrors the website's
/// `bg-ink rounded-full text-white` App Store button.
struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brandBody(14, weight: .black))
            .tracking(-0.2)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ink)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Subtler secondary CTA — translucent cream pill, ink/berry/etc label.
struct BrandSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brandBody(13, weight: .black))
            .tracking(-0.2)
            .foregroundColor(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.creamDeep, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AudioCheckView: View {
    @EnvironmentObject var audioService: AudioService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let profile: Profile?

    private var language: GameLanguage { profile?.language.resolvedLanguage ?? .system.resolvedLanguage }
    private var samples: [String] { Array(language.letters.prefix(4)) }

    var body: some View {
        NavigationView {
            List {
                Section("Voice") {
                    ForEach(samples, id: \.self) { letter in
                        Button("Replay “Find \(letter)”") {
                            audioService.playFindPrompt(letter: letter, language: language)
                        }
                    }
                }
                Section("Game sounds") {
                    Button("Correct") { audioService.playCorrect() }
                    Button("Wrong") { audioService.playWrong() }
                    Button("Streak 5") { audioService.playStreak5() }
                    Button("Streak 10") { audioService.playStreak10() }
                    Button("Click") { audioService.playClick() }
                }
                Section("Missing audio") {
                    if audioService.missingAssets.isEmpty {
                        Text("No missing audio detected.")
                    } else {
                        ForEach(audioService.missingAssets, id: \.self) { asset in
                            Text(asset).foregroundColor(.red)
                        }
                    }
                    if audioService.lastPlaybackFailed {
                        Text("Last playback failed. Check mute switch, volume, Bluetooth, and bundled files.")
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Audio Check")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(ProfileManager())
        .environmentObject(AudioService.shared)
        .environmentObject(SessionCheckpointStore())
        .environmentObject(NotificationService.shared)
        .environmentObject(FirebaseBackupService())
}
