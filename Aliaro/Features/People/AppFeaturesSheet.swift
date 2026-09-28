import SwiftUI
import SwiftData

/// Lets the family group choose which features are available to
/// everyone, which (up to 5) are favorites in the bottom bar (next to Home), and
/// which screen the app opens on. Anyone in the group can open
/// this to see the current setup, but only the group's creator (admin)
/// can actually change it — everyone else gets every control locked,
/// with a banner explaining why.
struct AppFeaturesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var disabledTabsDraft: Set<String> = []
    @State private var startTabDraft: String?
    @State private var favoriteTabsDraft: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isAdmin: Bool {
        members.first(where: { $0.isCurrentDevice })?.isCreator ?? false
    }

    /// Screens that can be picked as the group's start screen: Home or
    /// any visible feature — never "People" (that's where this setting
    /// lives) and never one that's currently hidden.
    private var availableStartTabs: [AppTab] {
        [.home] + AppTab.visibleFeatures(excluding: disabledTabsDraft)
    }

    private var selectedStartTab: AppTab {
        AppTab.start(stored: startTabDraft, excluding: disabledTabsDraft)
    }

    /// Favorites currently in effect (the stored choice, or the default
    /// first 3 visible features when nothing is stored yet).
    private var effectiveFavorites: [AppTab] {
        AppTab.favorites(stored: favoriteTabsDraft, excluding: disabledTabsDraft)
    }

    var body: some View {
        trackedBody.trackScreen("app_features")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !isAdmin {
                        ALICard(containerColor: ALIColors.surfaceVariant) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(ALIColors.mutedInk)
                                Text("Only the admin can change this setting")
                                    .font(ALITypography.bodyMedium)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                        }
                    }

                    ALICard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Choose which features everyone in the group can use.")
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)

                            VStack(spacing: 10) {
                                ForEach(AppTab.features) { tab in
                                    Toggle(isOn: Binding(
                                        get: { !disabledTabsDraft.contains(tab.settingsKey) },
                                        set: { isOn in toggleFeature(tab, isOn: isOn) }
                                    )) {
                                        Label(tab.label, systemImage: tab.systemImage)
                                            .font(ALITypography.bodyLarge)
                                            .foregroundStyle(isAdmin ? ALIColors.ink : ALIColors.mutedInk)
                                    }
                                    .tint(tab.accent)
                                    .disabled(!isAdmin || isSaving)
                                }
                            }
                        }
                    }

                    favoritesCard

                    ALICard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Choose which screen opens first for everyone in the group.")
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)

                            Menu {
                                ForEach(availableStartTabs) { tab in
                                    Button {
                                        setStartTab(tab.settingsKey)
                                    } label: {
                                        Label(tab.label, systemImage: tab.systemImage)
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedStartTab.systemImage)
                                    Text(selectedStartTab.label)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(ALIColors.peopleAccent)
                            }
                            .disabled(!isAdmin || isSaving)
                        }
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("App features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            disabledTabsDraft = familySession.disabledTabs
            startTabDraft = familySession.startTab
            favoriteTabsDraft = familySession.favoriteTabs
        }
        .onChange(of: familySession.disabledTabs) { _, newValue in
            disabledTabsDraft = newValue
        }
        .onChange(of: familySession.startTab) { _, newValue in
            startTabDraft = newValue
        }
        .onChange(of: familySession.favoriteTabs) { _, newValue in
            favoriteTabsDraft = newValue
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Pick up to `AppTab.maxFavorites` features for the bottom bar; Home
    /// is always there first. Order = the order they were picked.
    private var favoritesCard: some View {
        let favorites = effectiveFavorites
        let isFull = favorites.count >= AppTab.maxFavorites
        return ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick up to 5 favorites for the bottom bar. Home is always first; everything else is on Home.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)

                VStack(spacing: 4) {
                    ForEach(AppTab.visibleFeatures(excluding: disabledTabsDraft)) { tab in
                        let position = favorites.firstIndex(of: tab)
                        // At least one favorite always stays (clearing them all would
                        // silently bring back the defaults).
                        let canPick = position != nil ? favorites.count > 1 : !isFull
                        Button {
                            toggleFavorite(tab)
                        } label: {
                            HStack(spacing: 10) {
                                Label(tab.label, systemImage: tab.systemImage)
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(isAdmin && canPick ? ALIColors.ink : ALIColors.mutedInk)
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
                        .disabled(!isAdmin || isSaving || !canPick)
                    }
                }
            }
        }
    }

    private func toggleFavorite(_ tab: AppTab) {
        let previous = favoriteTabsDraft
        var updated = effectiveFavorites.map(\.settingsKey)
        if let index = updated.firstIndex(of: tab.settingsKey) {
            guard updated.count > 1 else { return }
            updated.remove(at: index)
        } else if updated.count < AppTab.maxFavorites {
            updated.append(tab.settingsKey)
        } else {
            return
        }
        favoriteTabsDraft = updated
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await familyService.updateFavoriteTabs(updated)
            } catch {
                errorMessage = error.localizedDescription
                favoriteTabsDraft = previous // revert on failure
            }
        }
    }

    private func toggleFeature(_ tab: AppTab, isOn: Bool) {
        var updated = disabledTabsDraft
        if isOn {
            updated.remove(tab.settingsKey)
        } else {
            updated.insert(tab.settingsKey)
        }
        disabledTabsDraft = updated
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await familyService.updateDisabledTabs(updated)
            } catch {
                errorMessage = error.localizedDescription
                disabledTabsDraft = familySession.disabledTabs // revert on failure
            }
        }
    }

    private func setStartTab(_ tab: String) {
        let previous = startTabDraft
        startTabDraft = tab
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await familyService.updateStartTab(tab)
            } catch {
                errorMessage = error.localizedDescription
                startTabDraft = previous // revert on failure
            }
        }
    }
}
