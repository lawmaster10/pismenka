//
//  ParentNumberDashboardView.swift
//  Pismenka
//
//  Parent-gated numbers dashboard. A deliberately focused sibling of
//  `ParentDashboardView` for the numbers learning layer: knowledge buckets,
//  a traffic-light number map over the introduced pool, recent number
//  rounds, common confusions, and the numbers-layer reset actions.
//

import SwiftUI

extension ProfileLearningSnapshot {
    /// Curriculum-relevant numbers the child has actually met: the introduced
    /// pool plus anything with learning evidence. Deliberately *not* all 101
    /// numbers — parent-facing counts should be honest about what has been
    /// taught, not dilute progress across the whole 0…100 curriculum.
    var numberKnowledgePool: Set<String> {
        NumberDifficulty.allNumberSet
            .subtracting(unseenNumbers)
            .union(knownNumbers)
            .union(everMasteredNumbers)
            .union(learningNumbers)
            .intersection(NumberDifficulty.allNumberSet)
    }
}

struct ParentNumberDashboardView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var checkpointStore: SessionCheckpointStore

    let profile: Profile
    let onPractice: (String) -> Void
    let onClose: () -> Void

    @State private var selectedNumber: String?
    @State private var showNumberActions = false
    @State private var pendingReset: PendingReset?
    @State private var showDashboardActions = false

    private enum PendingReset: Identifiable {
        case calibration
        case currentFocus
        case number(String)

        var id: String {
            switch self {
            case .calibration: return "calibration"
            case .currentFocus: return "currentFocus"
            case .number(let key): return "number-\(key)"
            }
        }
    }

    /// Re-fetched live profile (in case stats updated between sheet presentations).
    private var live: Profile {
        profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
    }

    private var snapshot: ProfileLearningSnapshot { live.snapshot }

    private var pool: Set<String> { snapshot.numberKnowledgePool }

    private var summary: ParentNumberKnowledgeSummary {
        snapshot.parentNumberKnowledgeSummary(pool: pool)
    }

    /// Pool numbers in pedagogical introduction order (introduced-first view).
    private var orderedPoolNumbers: [String] {
        NumberDifficulty.introductionOrder.filter { pool.contains($0) }
    }

    private var recentNumberRounds: [RoundEvent] {
        Array(live.recentRoundEvents
            .filter { $0.unitKind == .number }
            .suffix(30)
            .reversed())
    }

    private var commonNumberConfusions: [(id: String, target: String, confused: String, count: Int)] {
        var totals: [(id: String, target: String, confused: String, count: Int)] = []
        for (target, stat) in live.numberStats {
            for (confused, count) in stat.confusedWith where count >= 2 {
                totals.append((id: "\(target)-\(confused)", target: target, confused: confused, count: count))
            }
        }
        return totals
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.id < b.id
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground(accent: live.colorTheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerCard
                        bucketsCard
                        numberMapCard
                        if !recentNumberRounds.isEmpty {
                            recentRoundsCard
                        }
                        if !commonNumberConfusions.isEmpty {
                            confusionsCard
                        }
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
                    .accessibilityLabel("Numbers actions")
                }
            }
            .confirmationDialog("Numbers actions", isPresented: $showDashboardActions, titleVisibility: .visible) {
                dashboardActionButtons
            }
            .confirmationDialog(
                "Number \(selectedNumber ?? "")",
                isPresented: $showNumberActions,
                titleVisibility: .visible
            ) {
                numberActionButtons
            }
            .alert(item: $pendingReset, content: resetAlert(for:))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var dashboardActionButtons: some View {
        if profileManager.lastResetSnapshot != nil {
            Button {
                performAfterDismiss {
                    profileManager.undoLastReset()
                }
            } label: {
                Label("Undo last reset", systemImage: "arrow.uturn.backward.circle")
            }
        }
        Button {
            performAfterDismiss {
                pendingReset = .calibration
            }
        } label: {
            Label("Re-run numbers calibration", systemImage: "arrow.counterclockwise.circle")
        }
        if live.currentFocusNumber != nil {
            Button {
                performAfterDismiss {
                    pendingReset = .currentFocus
                }
            } label: {
                Label("Pick a new focus number", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var numberActionButtons: some View {
        if let number = selectedNumber {
            Button {
                performAfterDismiss {
                    onPractice(number)
                }
            } label: {
                Label("Extra practice for \(number)", systemImage: "target")
            }
            Button(role: .destructive) {
                performAfterDismiss {
                    pendingReset = .number(number)
                }
            } label: {
                Label("Reset \(number) (re-teach)", systemImage: "arrow.clockwise")
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func performAfterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }

    private func resetAlert(for kind: PendingReset) -> Alert {
        switch kind {
        case .calibration:
            return Alert(
                title: Text("Re-run numbers calibration?"),
                message: Text("\(live.displayName) will see the numbers calibration intro again. Number progress and history are kept; new attempts add to the existing record."),
                primaryButton: .default(Text("Re-run")) {
                    checkpointStore.clear(profileId: live.id, layer: .numbers)
                    profileManager.resetNumberCalibrationOnly(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        case .currentFocus:
            let focusName = live.currentFocusNumber ?? "-"
            return Alert(
                title: Text("Drop focus number \(focusName)?"),
                message: Text("\(focusName) stops being \(live.displayName)'s active practice number. Past attempts are kept. A new focus can be picked on the next eligible day."),
                primaryButton: .default(Text("Drop")) {
                    checkpointStore.clear(profileId: live.id, layer: .numbers)
                    profileManager.resetCurrentNumberFocus(profileId: live.id)
                },
                secondaryButton: .cancel()
            )
        case .number(let number):
            return Alert(
                title: Text("Reset number \(number)?"),
                message: Text("All attempts for \(number) are wiped and it leaves the introduced pool, so the app can re-teach it from scratch. Other numbers are untouched."),
                primaryButton: .destructive(Text("Reset")) {
                    checkpointStore.clear(profileId: live.id, layer: .numbers)
                    profileManager.resetNumberStats(profileId: live.id, number: number)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(live.colorTheme)
                    .frame(width: 72, height: 72)
                    .shadow(color: live.colorTheme.opacity(0.35), radius: 10, x: 0, y: 6)
                Text(live.avatarId.emoji)
                    .font(.system(size: 40))
            }
            VStack(spacing: 4) {
                Text("Numbers".uppercased())
                    .brandEyebrowStyle()
                Text("\(summary.confidentlyKnownCount) of \(summary.totalNumbers) confident")
                    .font(.brandTitleM(20))
                    .tracking(-0.4)
                    .foregroundColor(.ink)
            }
            HStack(spacing: 8) {
                BrandChip(text: snapshot.numberInstructionalBand.displayName)
                if let focus = live.currentFocusNumber {
                    BrandChip(text: "Focus \(focus)", background: .skyTint)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .softCard()
    }

    private var bucketsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Number knowledge")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                bucketTile(count: summary.confidentlyKnownCount, label: "Confident", color: Self.paletteGreen)
                bucketTile(count: summary.likelyKnownCount, label: "Likely", color: Self.paletteYellow)
                bucketTile(count: summary.needsPracticeCount, label: "Practice", color: Self.paletteRed)
                bucketTile(count: summary.notIntroducedCount, label: "Not yet", color: Color.slate400)
            }

            Text("Counts cover the \(summary.totalNumbers) number\(summary.totalNumbers == 1 ? "" : "s") introduced so far, not the whole 0–100 curriculum.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.78)))
    }

    private func bucketTile(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    // MARK: - Number map

    private enum NumberPaletteCategory {
        case known
        case maybe
        case needsPractice
    }

    private static let paletteGreen = Color(red: 0.2, green: 0.65, blue: 0.3)
    private static let paletteYellow = Color(red: 0.96, green: 0.72, blue: 0.16)
    private static let paletteRed = Color(red: 0.93, green: 0.39, blue: 0.31)

    private func paletteCategory(for number: String) -> NumberPaletteCategory {
        if summary.confidentlyKnownNumbers.contains(number) { return .known }
        if summary.likelyKnownNumbers.contains(number) { return .maybe }
        return .needsPractice
    }

    private func paletteFill(_ category: NumberPaletteCategory) -> Color {
        switch category {
        case .known: return Self.paletteGreen
        case .maybe: return Self.paletteYellow
        case .needsPractice: return Self.paletteRed
        }
    }

    private func paletteForeground(_ category: NumberPaletteCategory) -> Color {
        category == .maybe ? .ink : .white
    }

    private var numberMapCard: some View {
        let numbers = orderedPoolNumbers
        let columns = [GridItem(.adaptive(minimum: 52), spacing: 8)]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Number map")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Tap a number for actions")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if numbers.isEmpty {
                Text("No numbers introduced yet. Play a numbers session (or run the numbers calibration) to start filling this map.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(numbers, id: \.self) { number in
                        numberTile(number)
                    }
                }

                HStack(spacing: 14) {
                    legendItem(color: Self.paletteGreen, label: "Knows")
                    legendItem(color: Self.paletteYellow, label: "Maybe")
                    legendItem(color: Self.paletteRed, label: "Not yet")
                    Spacer(minLength: 0)
                }
            }

            if let next = NumberDifficulty.nextFocusCandidate(
                introduced: live.introducedNumbers,
                known: snapshot.knownNumbers
            ) {
                Text("Next up: \(next)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.78)))
    }

    private func numberTile(_ number: String) -> some View {
        let category = paletteCategory(for: number)
        return Button {
            selectedNumber = number
            showNumberActions = true
        } label: {
            Text(number)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(paletteForeground(category))
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(paletteFill(category))
                )
                .shadow(color: Color.ink.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number \(number). Double tap for practice and reset options.")
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Recent rounds

    private var recentRoundsCard: some View {
        let events = recentNumberRounds
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent number rounds")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Last \(events.count) · newest first")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 8) {
                    Image(systemName: event.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(event.wasCorrect ? Self.paletteGreen : Self.paletteRed)
                    Text("\(displayRoundKey(event.target)) → \(displayRoundKey(event.selected))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.62)))
    }

    // MARK: - Confusions

    private var confusionsCard: some View {
        let pairs = commonNumberConfusions
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Common confusions")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("≥ 2 mix-ups")
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

    private func displayRoundKey(_ key: String) -> String {
        FocusTarget(storageKey: key.hasPrefix("number:") ? key : "number:\(key)")?.displayText ?? key
    }
}

#Preview {
    ParentNumberDashboardView(
        profile: Profile(avatarId: .lion, language: .english),
        onPractice: { _ in },
        onClose: {}
    )
    .environmentObject(ProfileManager())
    .environmentObject(SessionCheckpointStore())
}
