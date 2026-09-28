import SwiftUI

/// Shown once, right after the admin creates a new family group (see
/// `FamilyService.needsInitialSetup`), before landing on Home. Two steps:
///
/// 1. Which features the group uses (same as the toggles in `AppFeaturesSheet`).
/// 2. The up-to-5 favorites that sit in the bottom bar next to Home.
///
/// Both are saved together at the end. Every step reminds the admin that
/// this can be changed anytime from People → App features.
struct FamilySetupView: View {
    @EnvironmentObject private var familyService: FamilyService

    private enum Step: Int { case features = 1, bottomBar = 2 }

    @State private var step: Step = .features
    @State private var disabledTabs: Set<String> = []
    @State private var favoriteTabs: [String] = AppTab.favorites(stored: [], excluding: []).map(\.settingsKey)
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var visibleFeatures: [AppTab] { AppTab.visibleFeatures(excluding: disabledTabs) }

    /// Picked favorites that are still visible, in pick order.
    private var favorites: [AppTab] {
        favoriteTabs.compactMap(AppTab.from(settingsKey:)).filter { visibleFeatures.contains($0) }
    }

    private var canContinue: Bool {
        switch step {
        case .features: return !visibleFeatures.isEmpty
        case .bottomBar: return !favorites.isEmpty
        }
    }

    var body: some View {
        trackedBody.trackScreen("family_setup")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .features: featuresCard
                    case .bottomBar:
                        barPreview
                        favoritesCard
                    }
                    changeLaterHint
                }
                .padding(20)
            }

            footer
        }
        .background(ALIColors.background)
        .animation(.easeInOut(duration: 0.2), value: step)
        .alert("Couldn't save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(step.rawValue) of 2")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                Spacer()
                Button("Skip") { familyService.skipInitialSetup() }
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .disabled(isSaving)
            }
            Text(step == .features ? "Choose your features" : "Set up your bottom bar")
                .font(ALITypography.headlineMedium)
                .foregroundStyle(ALIColors.ink)
            Text(step == .features
                 ? "Turn on what your family will use. Hidden features won't show up for anyone in the group."
                 : "Pick up to 5 favorites. Home is always first, and everything else is one tap away on Home.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            ALIPrimaryButton(
                text: step == .features ? "Continue" : "Start using Aliaro",
                enabled: canContinue && !isSaving,
                accent: ALIColors.familyAccent,
                action: next
            )
            if step == .bottomBar {
                ALITextButton(text: "Back") { step = .features }
                    .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var changeLaterHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ALIColors.peopleAccent)
            Text("You can change this anytime from People (your avatar on Home) → App features.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(ALIColors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Step 1: features

    private var featuresCard: some View {
        ALICard {
            VStack(spacing: 10) {
                ForEach(AppTab.features) { tab in
                    let isOn = !disabledTabs.contains(tab.settingsKey)
                    // At least one feature always stays on.
                    let isLastOn = isOn && visibleFeatures.count == 1
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { toggleFeature(tab, isOn: $0) }
                    )) {
                        Label(tab.label, systemImage: tab.systemImage)
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                    }
                    .tint(tab.accent)
                    .disabled(isLastOn)
                }
            }
        }
    }

    private func toggleFeature(_ tab: AppTab, isOn: Bool) {
        if isOn {
            disabledTabs.remove(tab.settingsKey)
        } else {
            disabledTabs.insert(tab.settingsKey)
            favoriteTabs.removeAll { $0 == tab.settingsKey }
        }
    }

    // MARK: - Step 2: bottom bar

    /// Live preview of how the bottom bar will look: Home + picked favorites.
    private var barPreview: some View {
        HStack(spacing: 0) {
            ForEach([AppTab.home] + favorites) { tab in
                VStack(spacing: 4) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                    Text(tab.label)
                        .font(ALITypography.labelLarge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(tab.accent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(ALIColors.surfaceVariant)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: favoriteTabs)
    }

    private var favoritesCard: some View {
        let isFull = favorites.count >= AppTab.maxFavorites
        return ALICard {
            VStack(spacing: 4) {
                ForEach(visibleFeatures) { tab in
                    let position = favorites.firstIndex(of: tab)
                    let canPick = position != nil || !isFull
                    Button {
                        toggleFavorite(tab)
                    } label: {
                        HStack(spacing: 10) {
                            Label(tab.label, systemImage: tab.systemImage)
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(canPick ? ALIColors.ink : ALIColors.mutedInk)
                            Spacer(minLength: 4)
                            if let position {
                                Text("\(position + 1)")
                                    .font(ALITypography.labelLarge.weight(.bold))
                                    .foregroundStyle(ALIColors.onAccent)
                                    .frame(width: 24, height: 24)
                                    .background(tab.accent)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .stroke(ALIColors.outline, lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPick)
                }
            }
        }
    }

    private func toggleFavorite(_ tab: AppTab) {
        var current = favorites.map(\.settingsKey)
        if let index = current.firstIndex(of: tab.settingsKey) {
            current.remove(at: index)
        } else if current.count < AppTab.maxFavorites {
            current.append(tab.settingsKey)
        }
        favoriteTabs = current
    }

    // MARK: - Actions

    private func next() {
        switch step {
        case .features:
            // Keep valid picks; refill with the first visible features if
            // hiding some left the bar empty.
            if favorites.isEmpty {
                favoriteTabs = AppTab.favorites(stored: [], excluding: disabledTabs).map(\.settingsKey)
            }
            step = .bottomBar
        case .bottomBar:
            save()
        }
    }

    private func save() {
        let favoriteKeys = favorites.map(\.settingsKey)
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await familyService.completeInitialSetup(disabledTabs: disabledTabs, favoriteTabs: favoriteKeys)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
