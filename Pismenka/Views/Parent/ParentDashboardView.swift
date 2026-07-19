//
//  ParentDashboardView.swift
//  Pismenka
//
//  Parent-gated dashboard. Surfaces per-profile letter mastery sorted by
//  response-time-aware certainty (so fast, repeated recognition ranks higher),
//  with a "why this letter?" explanation for the current focus, plus quick
//  links into edit and the music/SFX settings.
//

import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var checkpointStore: SessionCheckpointStore
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var pendingReset: PendingReset?
    @State private var showAllRounds = false
    @State private var showGlossary = false
    @State private var showDashboardActions = false
    @State private var showProfileNoteEditor = false
    @State private var profileNoteDraft = ""
    @State private var showDiagnostics = false
    @State private var showWeeklyTestPerLetter = false
    @State private var lettersSortMode: LettersSortMode = .needsHelpFirst
    @State private var lettersCharsetFilter: LettersCharsetFilter = .all
    #if DEBUG
    @State private var showDebugOverlay = false
    #endif

    /// Identifies which granular reset the parent has tapped, so the
    /// corresponding confirmation alert can fire. We use one alert
    /// per-action rather than a single shared one so the wording can match
    /// the blast radius (recalibrating ≠ wiping the focus letter ≠
    /// clearing the streak).
    private enum PendingReset: Identifiable {
        case calibration
        case currentFocus
        case streak
        case weeklyTest

        var id: String {
            switch self {
            case .calibration: return "calibration"
            case .currentFocus: return "currentFocus"
            case .streak: return "streak"
            case .weeklyTest: return "weeklyTest"
            }
        }
    }

    /// Sort modes for the per-letter detail list. Defaults to "needs help
    /// first" so a parent doing a 5-minute audit reaches their problem
    /// letters without scrolling past every mastered one.
    enum LettersSortMode: String, CaseIterable, Identifiable {
        case needsHelpFirst
        case strongestFirst
        case alphabetical

        var id: String { rawValue }
        var displayLabel: String {
            switch self {
            case .needsHelpFirst: return "Needs help first"
            case .strongestFirst: return "Strongest first"
            case .alphabetical: return "A → Z"
            }
        }
    }

    /// Filter chip for Czech, where parents sometimes want to focus only on
    /// diacritic letters (their data is sparser and they're often
    /// late-introduced). For non-Czech profiles the filter is hidden.
    enum LettersCharsetFilter: String, CaseIterable, Identifiable {
        case all
        case base
        case diacritic

        var id: String { rawValue }
        var displayLabel: String {
            switch self {
            case .all: return "All"
            case .base: return "Base"
            case .diacritic: return "Diacritic"
            }
        }
    }

    let profile: Profile
    let onEdit: () -> Void
    let onPractice: (String) -> Void
    let onClose: () -> Void

    /// Re-fetched live profile (in case stats updated between sheet presentations).
    private var live: Profile {
        profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
    }

    /// Pre-resolved learning state for `live`. Routing every "what does this
    /// child know?" question through `Profile.snapshot` keeps the dashboard
    /// in lockstep with the game — both read the same answer.
    private var snapshot: ProfileLearningSnapshot { live.snapshot }

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground(accent: live.colorTheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        // Tier 1 — 15-second read. Identity + level + what to
                        // do today + what's urgent + why this focus letter +
                        // the unified at-a-glance counts. Order matches the
                        // questions a parent asks in priority: "who am I
                        // looking at?", "what should I do today?", "what's
                        // burning?", "why is the app drilling this letter?",
                        // "give me the numbers".
                        headerCard
                        recommendationCard
                        needsAttentionSection
                        focusCard
                        progressGlanceCard
                        letterPaletteCard

                        // Tier 2 — 1-2 minute read. Weekly test summary stays
                        // compact (cohort tile grid only, per-letter list
                        // behind an expander), letters list defaults to
                        // needs-help-first with sort + charset filter,
                        // reading progress only when unlocked.
                        weeklyTestSummarySection
                        lettersSection
                        unitsProgressSection

                        // Tier 3 — 5-minute deep dive. Single collapsible
                        // block holding retention history, raw rounds,
                        // confusion pairs. Hidden by default so the screen
                        // isn't a wall of diagnostic detail.
                        diagnosticsSection
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(live.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDashboardActions = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    .accessibilityLabel("Profile actions")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(profile: live)
            }
            .confirmationDialog("Profile actions", isPresented: $showDashboardActions, titleVisibility: .visible) {
                profileActionButtons
            }
            .alert(item: $pendingReset, content: resetAlert(for:))
            .alert("What these labels mean", isPresented: $showGlossary) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(glossaryText)
            }
            .alert("Parent note", isPresented: $showProfileNoteEditor) {
                TextField("Observation", text: $profileNoteDraft)
                Button("Save") {
                    profileManager.updateProfileNote(profileId: live.id, note: profileNoteDraft)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Private note for \(live.displayName). It does not change the learning model.")
            }
        }
    }

    @ViewBuilder
    private var profileActionButtons: some View {
        Button {
            performAfterDismiss(onEdit)
        } label: {
            Label("Edit profile", systemImage: "pencil")
        }
        Button {
            performAfterDismiss {
                showSettings = true
            }
        } label: {
            Label("Sound settings", systemImage: "speaker.wave.2.fill")
        }
        Button {
            performAfterDismiss {
                profileNoteDraft = live.parentNote ?? ""
                showProfileNoteEditor = true
            }
        } label: {
            Label(live.parentNote == nil ? "Add parent note" : "Edit parent note", systemImage: "note.text")
        }
        Button {
            performAfterDismiss {
                showGlossary = true
            }
        } label: {
            Label("What do labels mean?", systemImage: "info.circle")
        }
        if profileManager.lastResetSnapshot != nil {
            Button {
                performAfterDismiss {
                    profileManager.undoLastReset()
                }
            } label: {
                Label("Undo last reset", systemImage: "arrow.uturn.backward.circle")
            }
        }
        if let assessment = live.activeWeeklyAssessment, !assessment.isCompleted {
            Button {
                performAfterDismiss {
                    pendingReset = .weeklyTest
                }
            } label: {
                Label("Skip current progress check", systemImage: "forward.end.circle")
            }
        }
        Button {
            performAfterDismiss {
                pendingReset = .calibration
            }
        } label: {
            Label("Re-run calibration", systemImage: "arrow.counterclockwise.circle")
        }
        if live.currentFocusLetter != nil {
            Button {
                performAfterDismiss {
                    pendingReset = .currentFocus
                }
            } label: {
                Label("Pick a new focus letter", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        if live.dailyStreakCount > 0 || live.lastSessionDay != nil {
            Button {
                performAfterDismiss {
                    pendingReset = .streak
                }
            } label: {
                Label("Reset day streak", systemImage: "xmark.circle")
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func performAfterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }

    // MARK: - Reset confirmation alerts

    private func resetAlert(for kind: PendingReset) -> Alert {
        switch kind {
        case .calibration:
            return Alert(
                title: Text("Re-run calibration?"),
                message: Text("\(live.displayName) will see the calibration intro again. Letter progress, trophies, notes, and streak records are kept; new attempts add to the existing record."),
                primaryButton: .default(Text("Re-run")) {
                    checkpointStore.clear(profileId: live.id)
                    profileManager.resetCalibrationOnly(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        case .currentFocus:
            let focusName = live.currentFocusLetter ?? "-"
            return Alert(
                title: Text("Drop focus letter \(focusName)?"),
                message: Text("\(focusName) stops being \(live.displayName)'s active practice letter. Past attempts, trophies, and notes are kept. A new focus can be picked on the next eligible day."),
                primaryButton: .default(Text("Drop")) {
                    checkpointStore.clear(profileId: live.id)
                    profileManager.resetCurrentFocus(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        case .streak:
            return Alert(
                title: Text("Reset day streak?"),
                message: Text("\(live.displayName)'s current streak (\(live.dailyStreakCount) day\(live.dailyStreakCount == 1 ? "" : "s")) goes back to 0. Best streak (\(live.bestDailyStreak)), trophies, and letter progress are kept."),
                primaryButton: .destructive(Text("Reset")) {
                    checkpointStore.clear(profileId: live.id)
                    profileManager.resetStreak(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        case .weeklyTest:
            return Alert(
                title: Text("Skip current progress check?"),
                message: Text("The answers \(live.displayName) already gave will stay in Review/test results. The progress check will end now, today's progress counter restarts, and the next play session can introduce a new letter today."),
                primaryButton: .default(Text("Skip test")) {
                    checkpointStore.clear(profileId: live.id)
                    profileManager.skipActiveWeeklyAssessment(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sections

    /// Tier-1 hero card. Replaces the raw "X/Y confident" headline that used
    /// to live at the top: a parent's first question is "where is my kid?",
    /// which is best answered by named milestones (Alphabet: Advanced,
    /// 7-day streak) — not a numerator. The big
    /// numerator now lives in `progressGlanceCard` further down.
    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(live.colorTheme)
                    .frame(width: 88, height: 88)
                    .shadow(color: live.colorTheme.opacity(0.4), radius: 8)
                Text(live.avatarId.emoji).font(.system(size: 54))
            }

            HStack(spacing: 8) {
                Text(snapshot.alphabetLevel.badgeEmoji).font(.system(size: 22))
                Text("Alphabet: \(snapshot.alphabetLevel.displayName)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(snapshot.alphabetLevel.badgeColor)
                Button {
                    showGlossary = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What do labels mean?")
            }

            HStack(spacing: 8) {
                if live.dailyStreakCount > 0 {
                    streakChip(
                        label: "\(live.dailyStreakCount)-day streak",
                        systemImage: "flame.fill",
                        color: .orange
                    )
                } else {
                    streakChip(
                        label: "No streak yet",
                        systemImage: "flame",
                        color: .secondary
                    )
                }
                if live.bestDailyStreak > 0 && live.bestDailyStreak != live.dailyStreakCount {
                    streakChip(
                        label: "Best \(live.bestDailyStreak)",
                        systemImage: "star.fill",
                        color: Color(red: 0.85, green: 0.65, blue: 0.15)
                    )
                }
            }

            // Only surface the trophy when it diverges from the current level,
            // such as after an explicit progress reset.
            if snapshot.highestAlphabetLevelEver > snapshot.alphabetLevel {
                HStack(spacing: 6) {
                    Text("Best level:")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(snapshot.highestAlphabetLevelEver.badgeEmoji).font(.system(size: 14))
                    Text(snapshot.highestAlphabetLevelEver.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(snapshot.highestAlphabetLevelEver.badgeColor)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.78)))
        #if DEBUG
        .onLongPressGesture {
            showDebugOverlay.toggle()
        }
        .overlay(alignment: .bottom) {
            if showDebugOverlay {
                AdaptiveDebugOverlay(profile: live)
                    .offset(y: 132)
            }
        }
        #endif
    }

    private func streakChip(label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    /// Tier-1 "give me the numbers" card. Merges the old `statRow` (4 letter
    /// buckets) with the old `letterPracticeSummaryCard` (total attempts /
    /// overall accuracy) — they were two visually disconnected summaries
    /// straddling the per-letter list. One card means a parent sees all
    /// aggregate metrics in one glance.
    private var progressGlanceCard: some View {
        let summary = letterKnowledgeSummary
        let practice = live.letterPracticeSummary

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Progress at a glance")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(summary.confidentlyKnownCount)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text("/ \(summary.totalLetters) confidently known")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ProgressView(
                    value: Double(summary.confidentlyKnownCount),
                    total: Double(max(summary.totalLetters, 1))
                )
                .tint(.green)
                Text("Cleared a strict bar at least once and still answered reliably right now. Same number shown on the profile card.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                statCard(
                    icon: "checkmark.seal.fill",
                    color: .blue,
                    value: "\(summary.likelyKnownCount)",
                    label: "Likely known"
                )
                statCard(
                    icon: "pencil.circle.fill",
                    color: .orange,
                    value: "\(summary.needsPracticeCount)",
                    label: "Needs practice"
                )
                statCard(
                    icon: "questionmark.circle.fill",
                    color: .gray,
                    value: "\(summary.notIntroducedCount)",
                    label: "Not introduced"
                )
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(practice.targetAttempts)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Total attempts")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(letterPracticeAccuracyText(practice))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Overall accuracy")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(letterPracticeSummaryText(practice))
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.78)))
    }

    private var letterKnowledgeSummary: ParentLetterKnowledgeSummary {
        snapshot.parentLetterKnowledgeSummary(alphabetLetters: alphabetLetters)
    }

    private var alphabetLetters: Set<String> {
        Set(live.language.letters)
    }

    /// Full alphabet in its canonical teaching order (so every letter shows
    /// in the palette, including ones not yet seen — which is exactly the
    /// "what's still missing?" question parents open this screen to answer).
    private var orderedAlphabetLetters: [String] {
        live.language.letters
    }

    // MARK: - Letter palette (at-a-glance traffic-light map)

    /// Three-state read of a single letter for the palette, collapsing the
    /// richer internal model into the green/yellow/red traffic light a
    /// parent can scan in two seconds. `notIntroduced` is a faded variant of
    /// red ("not known yet, but it isn't the child's fault — we haven't
    /// taught it") so a parent can still tell "struggling" from "untouched".
    private enum LetterPaletteCategory {
        case known
        case maybe
        case needsPractice
        case notIntroduced

        var accessibilityDescription: String {
            switch self {
            case .known: return "knows it"
            case .maybe: return "maybe knows it"
            case .needsPractice: return "doesn't know it yet"
            case .notIntroduced: return "not introduced yet"
            }
        }
    }

    private static let paletteGreen = Color(red: 0.2, green: 0.65, blue: 0.3)
    private static let paletteYellow = Color(red: 0.96, green: 0.72, blue: 0.16)
    private static let paletteRed = Color(red: 0.93, green: 0.39, blue: 0.31)

    private func paletteCategory(
        for letter: String,
        summary: ParentLetterKnowledgeSummary
    ) -> LetterPaletteCategory {
        if summary.confidentlyKnownLetters.contains(letter) { return .known }
        if summary.likelyKnownLetters.contains(letter) { return .maybe }
        if summary.notIntroducedLetters.contains(letter) { return .notIntroduced }
        return .needsPractice
    }

    private func paletteFill(_ category: LetterPaletteCategory) -> Color {
        switch category {
        case .known: return Self.paletteGreen
        case .maybe: return Self.paletteYellow
        case .needsPractice: return Self.paletteRed
        case .notIntroduced: return Self.paletteRed.opacity(0.12)
        }
    }

    private func paletteForeground(_ category: LetterPaletteCategory) -> Color {
        switch category {
        case .known, .needsPractice: return .white
        case .maybe: return .ink
        case .notIntroduced: return Self.paletteRed.opacity(0.7)
        }
    }

    private func paletteStroke(_ category: LetterPaletteCategory) -> Color {
        category == .notIntroduced ? Self.paletteRed.opacity(0.4) : .clear
    }

    /// Tier-1 visual alphabet. A grid of every letter colored green / yellow
    /// / red so a parent gets the whole picture — and what's still missing —
    /// in a single glance, before reading any numbers or scrolling the
    /// detailed Letters list further down.
    private var letterPaletteCard: some View {
        let summary = letterKnowledgeSummary
        let letters = orderedAlphabetLetters
        let categories = letters.map { paletteCategory(for: $0, summary: summary) }
        let knows = categories.filter { $0 == .known }.count
        let maybe = categories.filter { $0 == .maybe }.count
        let notYet = letters.count - knows - maybe
        let hasUnintroduced = categories.contains(.notIntroduced)
        let columns = [GridItem(.adaptive(minimum: 46), spacing: 8)]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Letter map")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(knows) / \(letters.count) known")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(zip(letters, categories)), id: \.0) { letter, category in
                    paletteTile(letter: letter, category: category)
                }
            }

            HStack(spacing: 14) {
                paletteLegendItem(color: Self.paletteGreen, label: "Knows", count: knows)
                paletteLegendItem(color: Self.paletteYellow, label: "Maybe", count: maybe)
                paletteLegendItem(color: Self.paletteRed, label: "Not yet", count: notYet)
                Spacer(minLength: 0)
            }

            if hasUnintroduced {
                Text("Faded red tiles are letters the app hasn't introduced yet.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.78)))
    }

    private func paletteTile(letter: String, category: LetterPaletteCategory) -> some View {
        let glyph = displayRoundKey(letter)
        return Text(glyph)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(paletteForeground(category))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(paletteFill(category))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(paletteStroke(category), lineWidth: 1.5)
            )
            .shadow(
                color: category == .notIntroduced ? .clear : Color.ink.opacity(0.12),
                radius: 2,
                x: 0,
                y: 1
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(glyph): \(category.accessibilityDescription)")
    }

    private func paletteLegendItem(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
            Text("\(count) \(label)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundColor(color)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    private var needsAttentionSection: some View {
        let rows = parentAttentionRows
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Needs attention")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            if rows.isEmpty {
                Text("Nothing urgent right now. Keep the next session light and let the app continue collecting evidence.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.systemImage)
                            .foregroundColor(attentionColor(row.tone))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text(row.detail)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    private var parentAttentionRows: [ParentAttentionItem] {
        var rows: [ParentAttentionItem] = []
        let needsPractice = letterKnowledgeSummary.needsPracticeLetters
            .sorted()
            .prefix(6)
            .map(displayRoundKey)
        if !needsPractice.isEmpty {
            rows.append(ParentAttentionItem(
                id: "needs-practice",
                title: "Practice these letters",
                detail: needsPractice.joined(separator: ", "),
                systemImage: "pencil.circle.fill",
                tone: .warning
            ))
        }

        let slipped = snapshot.recentlySlipped
            .intersection(alphabetLetters)
            .sorted()
            .prefix(6)
            .map(displayRoundKey)
        if !slipped.isEmpty {
            rows.append(ParentAttentionItem(
                id: "recently-slipped",
                title: "Recently slipped",
                detail: slipped.joined(separator: ", "),
                systemImage: "arrow.down.circle.fill",
                tone: .warning
            ))
        }

        if let latest = assessmentHistory.first {
            let reviewLetters = latest.cohortLetters
                .filter { [.needsReview, .watch].contains(latest.outcome(for: $0)) }
                .prefix(6)
                .map(displayRoundKey)
            if !reviewLetters.isEmpty {
                rows.append(ParentAttentionItem(
                    id: "weekly-review",
                    title: "Progress check follow-up",
                    detail: reviewLetters.joined(separator: ", "),
                    systemImage: "checklist.checked",
                    tone: .warning
                ))
            }
        }

        if let pair = commonConfusions.first {
            rows.append(ParentAttentionItem(
                id: "confusion-\(pair.id)",
                title: "Common confusion",
                detail: "\(displayRoundKey(pair.target)) is often mixed with \(displayRoundKey(pair.confused)) (\(pair.count)x).",
                systemImage: "arrow.left.arrow.right.circle.fill",
                tone: .info
            ))
        }

        return rows
    }

    private func attentionColor(_ tone: ParentAttentionTone) -> Color {
        switch tone {
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func letterPracticeAccuracyText(_ summary: LetterPracticeSummary) -> String {
        guard summary.targetAttempts > 0 else { return "-" }
        return "\(Int((summary.accuracy * 100).rounded()))%"
    }

    private func letterPracticeSummaryText(_ summary: LetterPracticeSummary) -> String {
        guard summary.targetAttempts > 0 else {
            return "No letter attempts recorded yet. Calibration and games will add to this total."
        }
        let letterLabel = summary.attemptedLetterCount == 1 ? "letter" : "letters"
        return "\(summary.targetCorrect) correct out of \(summary.targetAttempts) attempts across \(summary.attemptedLetterCount) \(letterLabel)."
    }

    /// Tier-2 weekly test card. Keeps the high-signal summary visible
    /// (outcome badge, cohort tile grid, retained/review/watch/pending
    /// metrics) and hides the duplicated per-cohort-letter row list behind
    /// an expander. Retention history and last-N test rounds — previously
    /// in this card — now live in `diagnosticsSection`.
    private var weeklyTestSummarySection: some View {
        let assessments = assessmentHistory

        return Group {
            if let latest = assessments.first {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Progress check")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Image(systemName: "checklist.checked")
                            .foregroundColor(live.colorTheme)
                    }

                    weeklyAssessmentSummaryCard(latest)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
            }
        }
    }

    private func weeklyAssessmentSummaryCard(_ assessment: WeeklyLetterAssessment) -> some View {
        let retained = assessment.cohortLetters.filter { assessment.outcome(for: $0) == .retained }.count
        let needsReview = assessment.cohortLetters.filter { assessment.outcome(for: $0) == .needsReview }.count
        let watch = assessment.cohortLetters.filter { assessment.outcome(for: $0) == .watch }.count
        let observed = assessment.cohortLetters.filter { assessment.outcome(for: $0) == .observed }.count
        let pending = assessment.cohortLetters.filter { assessment.outcome(for: $0) == .pending }.count
        let newLetterRows = weeklyCohortConfidenceRows(for: assessment)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.isCompleted ? "Latest completed test" : "Test in progress")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(assessmentDateText(assessment))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    if assessment.strategy == .adaptiveAudit {
                        Text("Adaptive audit · \(assessment.assessmentRoundTarget) assessment rounds")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                outcomeBadge(summaryOutcome(pending: pending, needsReview: needsReview, watch: watch, observed: observed))
            }

            if !newLetterRows.isEmpty {
                weeklyCohortConfidencePanel(rows: newLetterRows)
            }

            HStack(spacing: 10) {
                reviewMetric(value: "\(retained)", label: "Retained", color: .green)
                reviewMetric(value: "\(needsReview)", label: "Review", color: .orange)
                reviewMetric(value: "\(watch + observed)", label: "Watch", color: .purple)
                reviewMetric(value: "\(pending)", label: "Pending", color: .secondary)
            }

            // Per-cohort-letter rows duplicate the tile grid above for parents
            // who want the dense data view. Hidden by default; the tile grid
            // is enough for the 15-second read.
            Button(showWeeklyTestPerLetter ? "Hide per-letter rows" : "Show per-letter rows") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showWeeklyTestPerLetter.toggle()
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.blue)

            if showWeeklyTestPerLetter {
                ForEach(assessment.cohortLetters, id: \.self) { letter in
                    let result = assessment.results[letter, default: WeeklyAssessmentLetterResult()]
                    HStack(spacing: 8) {
                        Text(displayRoundKey(letter))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(result.independentCorrect)/\(result.independentAttempts) independent")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("\(result.bucket.displayLabel) · planned \(result.plannedAttempts) · \(avgResponseText(result.responseTimes))")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        outcomeBadge(assessment.outcome(for: letter))
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
                }
            }
        }
    }

    private func weeklyCohortConfidencePanel(rows: [WeeklyCohortConfidenceRow]) -> some View {
        let retained = rows.filter { $0.confidence == .retained }.count
        let maybe = rows.filter { $0.confidence == .maybeRetained }.count
        let notRetained = rows.filter { $0.confidence == .notRetained }.count
        let pending = rows.filter { $0.confidence == .pending }.count
        let columns = [
            GridItem(.adaptive(minimum: 104), spacing: 8)
        ]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New letters this week")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(rows.count) spotlight letters · confidence from independent test taps")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 6) {
                confidenceCountChip(count: retained, label: "retained", confidence: .retained)
                confidenceCountChip(count: maybe, label: "maybe", confidence: .maybeRetained)
                confidenceCountChip(count: notRetained, label: "not", confidence: .notRetained)
                if pending > 0 {
                    confidenceCountChip(count: pending, label: "pending", confidence: .pending)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    weeklyCohortConfidenceTile(row)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.5))
        )
    }

    private func confidenceCountChip(
        count: Int,
        label: String,
        confidence: WeeklyCohortConfidence
    ) -> some View {
        Text("\(count) \(label)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(confidenceColor(confidence))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(confidenceColor(confidence).opacity(0.12)))
    }

    private func weeklyCohortConfidenceTile(_ row: WeeklyCohortConfidenceRow) -> some View {
        let color = confidenceColor(row.confidence)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(displayRoundKey(row.letter))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                Spacer(minLength: 4)
                Text(row.confidence.displayLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.13)))
            }

            Text(row.scoreText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text("planned \(row.plannedAttempts)")
                Text(row.responseText)
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(color.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private func letterRetentionRow(_ row: LetterRetentionRow) -> some View {
        HStack(spacing: 8) {
            Text(displayRoundKey(row.letter))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.retainedTests)/\(row.testCount) tests retained")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("\(row.correct)/\(row.attempts) independent · \(percentageText(row.accuracy))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
            outcomeBadge(row.lastOutcome)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
    }

    private func testRoundRow(_ event: RoundEvent, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(event.wasCorrect ? .green : .orange)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(displayRoundKey(event.target)) → \(selectedText(for: event))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    if let responseTime = event.responseTime {
                        Text(String(format: "%.1fs", responseTime))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                Text(Self.testRoundDateFormatter.string(from: event.date))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                if !event.parentExplanations.isEmpty {
                    Text(event.parentExplanations.joined(separator: " "))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(index < 5 ? 0.62 : 0.5)))
    }

    private func reviewMetric(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
    }

    private func outcomeBadge(_ outcome: WeeklyAssessmentOutcome) -> some View {
        Text(outcomeText(outcome))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(outcomeColor(outcome))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(outcomeColor(outcome).opacity(0.12)))
    }

    private func weeklyCohortConfidenceRows(for assessment: WeeklyLetterAssessment) -> [WeeklyCohortConfidenceRow] {
        assessment.cohortLetters.compactMap { letter in
            let result = assessment.results[letter, default: WeeklyAssessmentLetterResult()]
            guard result.bucket == .cohort else { return nil }
            return WeeklyCohortConfidenceRow(
                letter: letter,
                independentAttempts: result.independentAttempts,
                independentCorrect: result.independentCorrect,
                plannedAttempts: result.plannedAttempts,
                responseTimes: result.responseTimes,
                confidence: weeklyCohortConfidence(for: result)
            )
        }
    }

    private func weeklyCohortConfidence(for result: WeeklyAssessmentLetterResult) -> WeeklyCohortConfidence {
        let requiredAttempts = min(
            result.plannedAttempts,
            WeeklyAssessmentLetterResult.requiredIndependentAttempts
        )
        guard result.independentAttempts >= requiredAttempts else { return .pending }
        if result.independentCorrect >= 4 { return .retained }
        if result.independentCorrect >= 2 { return .maybeRetained }
        return .notRetained
    }

    private func confidenceColor(_ confidence: WeeklyCohortConfidence) -> Color {
        switch confidence {
        case .retained: return .green
        case .maybeRetained: return .orange
        case .notRetained: return .red
        case .pending: return .secondary
        }
    }

    private var assessmentHistory: [WeeklyLetterAssessment] {
        var seen: Set<UUID> = []
        let active = live.activeWeeklyAssessment.map { [$0] } ?? []
        let completed = Array(live.recentWeeklyAssessments.reversed())
        return (active + completed).filter { assessment in
            seen.insert(assessment.id).inserted
        }
    }

    private var weeklyAssessmentRoundEvents: [RoundEvent] {
        Array(live.recentRoundEvents
            .filter { $0.intent == .weeklyAssessment }
            .suffix(50)
            .reversed())
    }

    private var letterRetentionRows: [LetterRetentionRow] {
        var accumulators: [String: LetterRetentionAccumulator] = [:]
        for assessment in assessmentHistory where assessment.isCompleted {
            for letter in assessment.cohortLetters {
                let result = assessment.results[letter, default: WeeklyAssessmentLetterResult()]
                var accumulator = accumulators[letter] ?? LetterRetentionAccumulator(letter: letter)
                accumulator.add(
                    result: result,
                    outcome: assessment.outcome(for: letter)
                )
                accumulators[letter] = accumulator
            }
        }
        return accumulators.values
            .map(\.row)
            .sorted(by: retentionSort)
    }

    private func retentionSort(_ lhs: LetterRetentionRow, _ rhs: LetterRetentionRow) -> Bool {
        let leftRank = retentionSortRank(lhs.lastOutcome)
        let rightRank = retentionSortRank(rhs.lastOutcome)
        if leftRank != rightRank { return leftRank < rightRank }
        if lhs.accuracy != rhs.accuracy { return lhs.accuracy < rhs.accuracy }
        return lhs.letter < rhs.letter
    }

    private func retentionSortRank(_ outcome: WeeklyAssessmentOutcome) -> Int {
        switch outcome {
        case .needsReview: return 0
        case .watch: return 1
        case .pending: return 1
        case .observed: return 2
        case .retained: return 3
        }
    }

    private func assessmentDateText(_ assessment: WeeklyLetterAssessment) -> String {
        if let completedOn = assessment.completedOn {
            return "Completed \(completedOn.iso8601)"
        }
        return "Started \(assessment.startedOn.iso8601)"
    }

    private func avgResponseText(_ responseTimes: [TimeInterval]) -> String {
        guard !responseTimes.isEmpty else { return "No response-time data" }
        let average = responseTimes.reduce(0, +) / Double(responseTimes.count)
        return String(format: "Avg %.1fs", average)
    }

    private func percentageText(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func selectedText(for event: RoundEvent) -> String {
        event.selected.isEmpty ? "no answer" : displayRoundKey(event.selected)
    }

    private func outcomeText(_ outcome: WeeklyAssessmentOutcome) -> String {
        switch outcome {
        case .pending: return "Pending"
        case .retained: return "Retained"
        case .watch: return "Watch"
        case .observed: return "Observed"
        case .needsReview: return "Review"
        }
    }

    private func outcomeColor(_ outcome: WeeklyAssessmentOutcome) -> Color {
        switch outcome {
        case .pending: return .secondary
        case .retained: return .green
        case .watch: return .purple
        case .observed: return .blue
        case .needsReview: return .orange
        }
    }

    private func summaryOutcome(
        pending: Int,
        needsReview: Int,
        watch: Int,
        observed: Int
    ) -> WeeklyAssessmentOutcome {
        if pending > 0 { return .pending }
        if needsReview > 0 { return .needsReview }
        if watch > 0 { return .watch }
        if observed > 0 { return .observed }
        return .retained
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focusTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(live.colorTheme.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Text(snapshot.currentFocusTarget?.displayText ?? snapshot.currentFocus.map { live.displayText(for: $0) } ?? "-")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(live.colorTheme)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(focusExplanation)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if snapshot.currentFocusTarget != nil || snapshot.currentFocus != nil {
                        Text("Day \(max(1, live.focusActiveDays)) of practice")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.78)))
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try this today")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(parentRecommendation)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    private var parentRecommendation: String {
        if let impulseEvent = live.recentRoundEvents.suffix(8).last(where: { $0.mistakeType == .impulsiveTap }) {
            return "Try one slow turn: hear the sound, then point to \(displayRoundKey(impulseEvent.target))."
        }
        if let pair = commonConfusions.first {
            return "Point out \(pair.target) in a book today and say its sound slowly."
        }
        if let slow = snapshot.lettersByReviewPriority.first,
           let stat = live.letterStats[slow],
           stat.responseTimeBucket == .slow {
            return "\(live.displayText(for: slow)) is correct but slow. Keep it in a quick warm-up: find it once, say it once, then stop."
        }
        if !live.name.isEmpty,
           let first = live.firstNameLetterKey {
            return "Name connection: find the first letter of \(live.name), \(first), on a page or sign today."
        }
        return "Keep it light: one minute of pointing to familiar letters in a book is enough for today."
    }

    private var focusExplanation: String {
        if live.letterStats.isEmpty {
            return "Calibration hasn't run yet. Open the app as \(live.displayName) to begin."
        }
        guard let focus = snapshot.currentFocus else {
            if snapshot.alphabetLevel >= .expert {
                return "All letters mastered. The session is now pure letter review."
            }
            if let next = snapshot.nextFocusCandidate {
                return "No focus right now. \(next) is up next session."
            }
            return "No focus right now. A new one will be picked next session."
        }
        let strongLetters = snapshot.lettersByConfidence
            .prefix(4)
            .filter { $0 != focus }
        if let reason = live.lastFocusSelection, reason.selectedKey == focus {
            return focusReasonText(reason.reason, focus: focus, strongLetters: Array(strongLetters))
        }
        if strongLetters.isEmpty {
            return "We're starting with \(focus), the first new letter for \(live.displayName)."
        }
        let strongList = strongLetters.joined(separator: ", ")
        return "Chose \(focus) because \(strongList) are already strong."
    }

    private var focusTitle: String {
        "Today's focus"
    }

    private var unitsProgressSection: some View {
        EmptyView()
    }

    private func unitStatList(title: String, stats: [String: UnitProgressStat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            ForEach(stats.sorted { $0.key < $1.key }.prefix(10), id: \.key) { key, stat in
                HStack {
                    Text(key)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(stat.targetCorrect)/\(stat.targetAttempts)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
            }
        }
    }

    private func focusReasonText(
        _ reason: FocusSelectionReason.Reason,
        focus: String,
        strongLetters: [String]
    ) -> String {
        switch reason {
        case .nextInOrder:
            return "Chose \(focus) as the next letter in the learning order."
        case .prerequisiteReady:
            return "Chose \(focus) because the confusing prerequisite letters are ready."
        case .staleWeakness:
            return "Chose \(focus) because it was introduced before and needs a fresh pass."
        case .diacriticAfterBaseMastered:
            if let base = LetterDifficulty.diacriticBase[focus] {
                return "Chose \(focus) because base letter \(base) is mastered."
            }
            return "Chose \(focus) because its base letter is mastered."
        case .fallbackNoReadyCandidate:
            if strongLetters.isEmpty {
                return "Chose \(focus) as the safest available next step."
            }
            return "Chose \(focus) as a fallback; \(strongLetters.joined(separator: ", ")) can help as easy distractors."
        }
    }

    // MARK: - Letters list

    /// Tier-2 per-letter table. Defaults to "Needs help → Mastered" grouping
    /// (the question a parent doing a real audit asks first), with explicit
    /// sort and — for Czech — base/diacritic filter chips. The old behavior
    /// of "sorted by certainty, strongest first" is still reachable via the
    /// sort picker; this is no longer the default because it buries the
    /// letters the parent actually came here for.
    private var lettersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Letters")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Menu {
                    Picker("Sort", selection: $lettersSortMode) {
                        ForEach(LettersSortMode.allCases) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(lettersSortMode.displayLabel)
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
                }
            }

            if live.language.resolvedLanguage == .czech {
                HStack(spacing: 6) {
                    ForEach(LettersCharsetFilter.allCases) { filter in
                        charsetFilterChip(filter)
                    }
                    Spacer(minLength: 0)
                }
            }

            if filteredSortedLetters.isEmpty {
                Text("No letters seen yet. Run calibration to begin.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
            } else {
                VStack(spacing: 6) {
                    ForEach(knowledgeGroups, id: \.title) { group in
                        letterSubsection(title: group.title, items: group.items)
                    }
                }
            }
        }
    }

    private func charsetFilterChip(_ filter: LettersCharsetFilter) -> some View {
        let isSelected = lettersCharsetFilter == filter
        return Button {
            lettersCharsetFilter = filter
        } label: {
            Text(filter.displayLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? live.colorTheme : Color.white.opacity(0.7))
                )
        }
        .buttonStyle(.plain)
    }

    private func letterSubsection(title: String, items: [(String, LetterStat)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                ForEach(items, id: \.0) { item in
                    LetterStatRow(
                        letter: item.0,
                        stat: item.1,
                        state: live.knowledgeState(for: item.0),
                        baseLetter: LetterDifficulty.diacriticBase[item.0],
                        onPractice: {
                            onPractice(item.0)
                        },
                        onSetOverride: { override in
                            profileManager.setLetterOverride(
                                profileId: live.id,
                                letter: item.0,
                                override: override
                            )
                        },
                        onResetStats: {
                            checkpointStore.clear(profileId: live.id)
                            profileManager.resetLetterStats(
                                profileId: live.id,
                                letter: item.0
                            )
                        },
                        onSetNote: { note in
                            profileManager.updateLetterNote(
                                profileId: live.id,
                                letter: item.0,
                                note: note
                            )
                        }
                    )
                }
            }
        }
    }

    /// Knowledge-state buckets shown in the letters list, ordered so the
    /// group most likely to need a parent's attention sits at the top. The
    /// per-letter sort inside each group is controlled by `lettersSortMode`.
    /// `needsHelpFirst` is the default; `strongestFirst` reverses the group
    /// order; `alphabetical` keeps the same buckets but sorts each by letter.
    private var knowledgeGroups: [(title: String, items: [(String, LetterStat)])] {
        let allOrder: [(String, [LetterKnowledgeState])] = [
            ("Needs help", [.needsHelp, .learning, .exposed]),
            ("Getting there", [.gettingThere, .tentative]),
            ("Recently slipped", [.recentlySlipped]),
            ("Practicing now", [.focus]),
            ("Confident", [.confident, .known]),
            ("Mastered", [.mastered]),
            ("Marked known by parent", [.markedKnown]),
            ("Reset by parent", [.parentReset]),
            ("Not yet seen", [.unseen]),
        ]

        let displayOrder: [(String, [LetterKnowledgeState])]
        switch lettersSortMode {
        case .needsHelpFirst, .alphabetical:
            displayOrder = allOrder
        case .strongestFirst:
            displayOrder = allOrder.reversed()
        }

        let base = filteredSortedLetters
        return displayOrder.map { title, states in
            let items = base.filter { states.contains(live.knowledgeState(for: $0.0)) }
            return (title, items)
        }.filter { !$0.items.isEmpty }
    }

    /// Letters after charset filter (Czech base/diacritic) and the selected
    /// intra-group sort.
    private var filteredSortedLetters: [(String, LetterStat)] {
        let charsetFiltered: [(String, LetterStat)] = live.letterStats
            .filter { entry in
                guard live.language.resolvedLanguage == .czech else { return true }
                let isDiacritic = LetterDifficulty.diacriticBase[entry.key] != nil
                switch lettersCharsetFilter {
                case .all: return true
                case .base: return !isDiacritic
                case .diacritic: return isDiacritic
                }
            }
            .map { ($0.key, $0.value) }

        switch lettersSortMode {
        case .needsHelpFirst:
            // Highest reviewPriority first (weakness + staleness + slowness);
            // ties fall back to letter for a stable order.
            return charsetFiltered.sorted { a, b in
                let ra = a.1.reviewPriority
                let rb = b.1.reviewPriority
                if ra != rb { return ra > rb }
                return a.0 < b.0
            }
        case .strongestFirst:
            return charsetFiltered.sorted { a, b in
                let ra = a.1.certaintyScore
                let rb = b.1.certaintyScore
                if ra != rb { return ra > rb }
                if a.1.targetAttempts != b.1.targetAttempts {
                    return a.1.targetAttempts > b.1.targetAttempts
                }
                return a.0 < b.0
            }
        case .alphabetical:
            return charsetFiltered.sorted { $0.0 < $1.0 }
        }
    }

    // MARK: - Diagnostics (Tier 3)

    /// Tier-3 deep-dive expander. Bundles everything previously scattered
    /// across the dashboard for a parent who wants to *audit* — not glance:
    /// letter retention across weekly tests, recent test rounds, common
    /// confusion pairs (the full list, not just the top one surfaced in
    /// Needs attention), and the raw round log. Hidden by default so the
    /// top of the screen stays focused on the 15-second read.
    private var diagnosticsSection: some View {
        let hasContent = !letterRetentionRows.isEmpty
            || !weeklyAssessmentRoundEvents.isEmpty
            || !commonConfusions.isEmpty
            || !live.recentRoundEvents.isEmpty

        return Group {
            if hasContent {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDiagnostics.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Diagnostics")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("Retention, test rounds, confusions, raw history")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)

                    if showDiagnostics {
                        if !letterRetentionRows.isEmpty {
                            letterRetentionListCard
                        }
                        if !weeklyAssessmentRoundEvents.isEmpty {
                            weeklyAssessmentRoundsListCard
                        }
                        if !commonConfusions.isEmpty {
                            commonConfusionsListCard
                        }
                        if !live.recentRoundEvents.isEmpty {
                            rawRoundsListCard
                        }
                    }
                }
            }
        }
    }

    private var letterRetentionListCard: some View {
        let rows = letterRetentionRows
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Letter retention")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Across \(assessmentHistory.filter { $0.isCompleted }.count) tests")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            ForEach(rows) { row in
                letterRetentionRow(row)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
    }

    private var weeklyAssessmentRoundsListCard: some View {
        let rounds = weeklyAssessmentRoundEvents
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent test rounds")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Last \(rounds.count) · newest first")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            ForEach(Array(rounds.enumerated()), id: \.offset) { index, event in
                testRoundRow(event, index: index)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
    }

    private var commonConfusionsListCard: some View {
        let pairs = commonConfusions
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Common confusions")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("≥ 3 mix-ups")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            ForEach(pairs, id: \.id) { pair in
                HStack {
                    Text("\(displayRoundKey(pair.target)) → \(displayRoundKey(pair.confused))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(pair.count)x")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
    }

    private var rawRoundsListCard: some View {
        let events = Array(live.recentRoundEvents.suffix(showAllRounds ? RoundEvent.maxRetained : 30).reversed())
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Raw round history")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(showAllRounds ? "Show 30" : "Show all") {
                    showAllRounds.toggle()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            HStack {
                Text("Newest first")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            ForEach(events, id: \.date) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(displayRoundKey(event.target)) → \(displayRoundKey(event.selected))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(event.intent.rawValue)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let responseTime = event.responseTime {
                            Text(String(format: "%.1fs", responseTime))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        if event.wasDiscounted {
                            Text("discounted")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    if !event.parentExplanations.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(event.parentExplanations, id: \.self) { explanation in
                                Text("- \(explanation)")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
    }

    /// Single source of truth for the glossary alert. Documents both the
    /// 4-bucket summary used at the top (Confidently known / Likely known /
    /// Needs practice / Not introduced) and the per-letter knowledge states
    /// used in the Letters list, since both vocabularies appear on the same
    /// screen and a parent shouldn't have to guess how they relate.
    private var glossaryText: String {
        """
        PROGRESS BUCKETS (top counts)
        • Confidently known: letter has cleared a strict bar at least once \
        (Wilson 95% on lifetime accuracy, or 7/8 of recent attempts, or \
        previously mastered) AND is still answered reliably right now.
        • Likely known: currently passes the loose 4/5 recent check, or was \
        previously mastered but has wobbled in the last few attempts.
        • Needs practice: introduced and has never reliably cleared the bar.
        • Not introduced: not yet intentionally taught.

        SPEED IS ASYMMETRIC
        A fast tap is strong positive evidence; a slow tap is no evidence \
        either way (3-year-olds get distracted). Slow answers never demote \
        certainty or push letters into "needs practice".

        PER-LETTER STATE (Letters list)
        • Mastered: lifetime mastery, ≥ 7/8 of recent target attempts.
        • Confident: currently passes the looser known rule.
        • Getting there: recent accuracy ≥ 50% but not yet known.
        • Needs help: recent accuracy below 50%.
        • Recently slipped: was mastered, now failing recent checks.
        • Practicing now: today's focus letter.
        • Marked known / Reset by parent: your manual overrides.
        • Not seen yet: never encountered as target or distractor.
        """
    }

    private func displayRoundKey(_ key: String) -> String {
        FocusTarget(storageKey: key)?.displayText ?? key
    }

    private var commonConfusions: [(id: String, target: String, confused: String, count: Int)] {
        var totals: [String: (target: String, confused: String, count: Int)] = [:]
        for (target, stat) in live.letterStats {
            for (confused, count) in stat.confusedWith where count >= 3 {
                let id = "\(target)-\(confused)"
                totals[id] = (target, confused, count)
            }
        }
        return totals
            .map { (id: $0.key, target: $0.value.target, confused: $0.value.confused, count: $0.value.count) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.id < b.id
            }
            .prefix(3)
            .map { $0 }
    }

    private static let testRoundDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum ParentAttentionTone {
    case warning
    case info
}

private struct ParentAttentionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tone: ParentAttentionTone
}

private struct LetterRetentionRow: Identifiable {
    let letter: String
    let attempts: Int
    let correct: Int
    let testCount: Int
    let retainedTests: Int
    let lastOutcome: WeeklyAssessmentOutcome

    var id: String { letter }

    var accuracy: Double {
        guard attempts > 0 else { return 0 }
        return Double(correct) / Double(attempts)
    }
}

private enum WeeklyCohortConfidence: Int {
    case retained
    case maybeRetained
    case notRetained
    case pending

    var displayLabel: String {
        switch self {
        case .retained: return "Retained"
        case .maybeRetained: return "Maybe"
        case .notRetained: return "Not retained"
        case .pending: return "Pending"
        }
    }
}

private struct WeeklyCohortConfidenceRow: Identifiable {
    let letter: String
    let independentAttempts: Int
    let independentCorrect: Int
    let plannedAttempts: Int
    let responseTimes: [TimeInterval]
    let confidence: WeeklyCohortConfidence

    var id: String { letter }

    var scoreText: String {
        "\(independentCorrect)/\(independentAttempts) independent"
    }

    var responseText: String {
        guard !responseTimes.isEmpty else { return "No response-time data" }
        let average = responseTimes.reduce(0, +) / Double(responseTimes.count)
        return String(format: "avg %.1fs", average)
    }
}

private struct LetterRetentionAccumulator {
    let letter: String
    var attempts = 0
    var correct = 0
    var testCount = 0
    var retainedTests = 0
    var lastOutcome: WeeklyAssessmentOutcome?

    mutating func add(
        result: WeeklyAssessmentLetterResult,
        outcome: WeeklyAssessmentOutcome
    ) {
        attempts += result.independentAttempts
        correct += result.independentCorrect
        testCount += 1
        if outcome == .retained {
            retainedTests += 1
        }
        if lastOutcome == nil {
            lastOutcome = outcome
        }
    }

    var row: LetterRetentionRow {
        LetterRetentionRow(
            letter: letter,
            attempts: attempts,
            correct: correct,
            testCount: testCount,
            retainedTests: retainedTests,
            lastOutcome: lastOutcome ?? .pending
        )
    }
}

// MARK: - Letter row

struct LetterStatRow: View {
    let letter: String
    let stat: LetterStat
    let state: LetterKnowledgeState
    let baseLetter: String?
    let onPractice: () -> Void
    /// Set/clear a parent override on this letter. Pass `nil` to clear.
    let onSetOverride: (LetterOverride?) -> Void
    /// Wipes this letter's stats entirely (counters, timestamps, override).
    let onResetStats: () -> Void
    let onSetNote: (String?) -> Void

    @State private var showResetConfirm = false
    @State private var showMarkKnownConfirm = false
    @State private var showParentResetConfirm = false
    @State private var showNoteEditor = false
    @State private var showActionDialog = false
    @State private var noteDraft = ""

    private var isFocus: Bool { state == .focus }
    private var isOverridden: Bool { stat.parentOverride != nil }
    private var hasAnyData: Bool {
        stat.targetAttempts > 0 || stat.distractorExposures > 0 || isOverridden
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(letterTileFill)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(letterTileStroke, lineWidth: 2)
                    )
                Text(displayLetter)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.displayLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(state.displayColor)
                    Circle()
                        .fill(recencyColor)
                        .frame(width: 8, height: 8)
                }
                Text(detailText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
                signalBadges
                if let note = stat.parentNote {
                    Text("Note: \(note)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.purple)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(percentText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("\(stat.targetCorrect) / \(stat.targetAttempts)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                Text(certaintyText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text(stat.evidenceStrength.displayLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Button {
                showActionDialog = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Actions for \(displayLetter)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
        .confirmationDialog("Actions for \(displayLetter)", isPresented: $showActionDialog, titleVisibility: .visible) {
            rowActionButtons
        }
        .alert("Wipe \(letter)'s stats?", isPresented: $showResetConfirm) {
            Button("Wipe", role: .destructive) { onResetStats() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All recorded attempts, exposures, and overrides for \(letter) will be deleted. Other letters and the day streak are unaffected.")
        }
        .alert("Mark \(letter) as known?", isPresented: $showMarkKnownConfirm) {
            Button("Mark known") { onSetOverride(.markedKnown(date: Date())) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a parent override, not earned in-game. It keeps the raw attempt history visible.")
        }
        .alert("Reset \(letter) for re-teaching?", isPresented: $showParentResetConfirm) {
            Button("Reset", role: .destructive) { onSetOverride(.reset(date: Date())) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recorded attempts are kept, but the app treats \(letter) as needing practice until you clear the override.")
        }
        .alert("Letter note", isPresented: $showNoteEditor) {
            TextField("Observation", text: $noteDraft)
            Button("Save") { onSetNote(noteDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Private note for \(letter). Notes do not change the learning model.")
        }
    }

    // MARK: Row actions (overrides + per-letter reset)

    @ViewBuilder
    private var rowActionButtons: some View {
        if isOverridden {
            Button {
                performAfterDismiss {
                    onSetOverride(nil)
                }
            } label: {
                Label("Clear parent override", systemImage: "arrow.uturn.backward")
            }
        }
        if !isMarkedKnown {
            Button {
                performAfterDismiss {
                    showMarkKnownConfirm = true
                }
            } label: {
                Label("Mark as known", systemImage: "checkmark.seal")
            }
        }
        if !isReset {
            Button {
                performAfterDismiss {
                    showParentResetConfirm = true
                }
            } label: {
                Label("Reset (re-teach)", systemImage: "arrow.clockwise")
            }
        }
        Button {
            performAfterDismiss {
                onPractice()
            }
        } label: {
            Label("Extra practice for \(letter)", systemImage: "target")
        }
        Button {
            performAfterDismiss {
                noteDraft = stat.parentNote ?? ""
                showNoteEditor = true
            }
        } label: {
            Label(stat.parentNote == nil ? "Add note" : "Edit note", systemImage: "note.text")
        }
        if hasAnyData {
            // `resetLetterStats` (destructive) is offered only for letters
            // that actually have something to lose — wiping a never-seen
            // letter's empty stat is a no-op and would just clutter the menu.
            Button(role: .destructive) {
                performAfterDismiss {
                    showResetConfirm = true
                }
            } label: {
                Label("Wipe stats for \(letter)", systemImage: "trash")
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func performAfterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }

    private var isMarkedKnown: Bool {
        if case .markedKnown = stat.parentOverride { return true }
        return false
    }

    private var displayLetter: String {
        if letter.hasSuffix("|lower") {
            return String(letter.dropLast("|lower".count)).lowercased()
        }
        return letter
    }

    private var isReset: Bool {
        if case .reset = stat.parentOverride { return true }
        return false
    }

    // MARK: Visual styling

    private var letterTileFill: Color {
        if isFocus { return Color.yellow.opacity(0.3) }
        if isOverridden { return state.displayColor.opacity(0.15) }
        return Color.white.opacity(0.7)
    }

    private var letterTileStroke: Color {
        if isFocus { return Color.orange }
        if isOverridden { return state.displayColor.opacity(0.6) }
        return Color.clear
    }

    private var recencyColor: Color {
        switch stat.recencyState {
        case .green: return Color(red: 0.3, green: 0.75, blue: 0.4)
        case .amber: return Color(red: 0.95, green: 0.7, blue: 0.2)
        case .red: return Color(red: 0.9, green: 0.35, blue: 0.3)
        case .gray: return Color.gray.opacity(0.5)
        }
    }

    private var percentText: String {
        guard stat.targetAttempts > 0 else { return "-" }
        return "\(Int((stat.accuracy * 100).rounded()))%"
    }

    private var certaintyText: String {
        guard stat.targetAttempts > 0 else { return "Certainty: -" }
        return "Certainty \(Int((stat.certaintyScore * 100).rounded()))%"
    }

    @ViewBuilder
    private var signalBadges: some View {
        HStack(spacing: 6) {
            if let baseLetter {
                badge("base: \(baseLetter)", color: .blue)
            }
            if let confusion = topConfusion {
                badge("mixes with \(confusion.letter)", color: .orange)
            }
            if stat.responseTimeBucket != .unknown {
                badge(stat.responseTimeBucket.rawValue, color: responseBucketColor)
            }
            if stat.promptReplayCount > max(1, stat.targetAttempts / 2) {
                badge("replay often", color: .purple)
            }
            if stat.wasKnownBefore && !stat.isKnown {
                badge("slipped", color: .pink)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var topConfusion: (letter: String, count: Int)? {
        stat.confusedWith
            .filter { $0.value >= 3 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .first
            .map { ($0.key, $0.value) }
    }

    private var responseBucketColor: Color {
        switch stat.responseTimeBucket {
        case .fast: return .green
        case .normal: return .secondary
        case .slow: return .orange
        case .unknown: return .gray
        }
    }

    private var detailText: String {
        if stat.targetAttempts == 0 && stat.distractorExposures == 0 {
            // Even an unseen letter can carry an override (parent marked
            // it without any in-app evidence). Surface that honestly.
            if isOverridden { return "Override only: no in-app data" }
            return "Not seen yet"
        }
        let totalSeen = stat.targetAttempts + stat.distractorExposures
        return "Seen \(totalSeen) · Tested \(stat.targetAttempts)"
    }
}

#if DEBUG
struct AdaptiveDebugOverlay: View {
    let profile: Profile

    private var latest: RoundEvent? { profile.recentRoundEvents.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adaptive Debug")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            if let latest {
                Text("phase: \(latest.phase.rawValue) · intent: \(latest.intent.rawValue)")
                Text("target: \(latest.target) · options: \(latest.options.joined(separator: ","))")
                Text("live: \(latest.liveDifficulty?.rawValue ?? "nil") · rescue: \(latest.rescueDifficulty?.rawValue ?? "nil")")
                Text("response: \(latest.responseTime.map { String(format: "%.2fs", $0) } ?? "nil") · mistake: \(latest.mistakeType?.rawValue ?? "nil")")
            } else {
                Text("No round events yet")
            }
            Text("focusScaffolding: \(profile.focusScaffoldingLevel)")
            Text("top reviewPriority: \(topReviewPriority)")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.85)))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var topReviewPriority: String {
        profile.lettersByReviewPriority
            .prefix(3)
            .map { key in
                let value = profile.letterStats[key]?.reviewPriority ?? 0
                return "\(key)=\(String(format: "%.2f", value))"
            }
            .joined(separator: " ")
    }
}
#endif

#Preview {
    ParentDashboardView(
        profile: Profile(avatarId: .lion),
        onEdit: {},
        onPractice: { _ in },
        onClose: {}
    )
    .environmentObject(ProfileManager())
    .environmentObject(AppSettings())
    .environmentObject(SessionCheckpointStore())
}
