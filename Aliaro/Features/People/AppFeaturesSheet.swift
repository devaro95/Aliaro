import SwiftUI
import SwiftData

/// Lets the family group choose which tabs show up in everyone's bottom
/// bar, and which one the app opens on. Anyone in the group can open
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
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isAdmin: Bool {
        members.first(where: { $0.isCurrentDevice })?.isCreator ?? false
    }

    /// Tabs that can be picked as the group's start screen: never
    /// "People" (that's where this setting lives, so it can
    /// never be the first thing people see) and never one that's
    /// currently hidden.
    private var availableStartTabs: [AppTab] {
        AppTab.allCases.filter { $0.isConfigurable && !disabledTabsDraft.contains($0.settingsKey) }
    }

    private var selectedStartTab: AppTab {
        let key = startTabDraft ?? AppTab.firstAvailable(excluding: disabledTabsDraft).settingsKey
        return AppTab.from(settingsKey: key) ?? .weeklyMenu
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
                            Text("Choose what everyone in the group sees in the bottom bar.")
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)

                            VStack(spacing: 10) {
                                ForEach(AppTab.allCases.filter(\.isConfigurable)) { tab in
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
        }
        .onChange(of: familySession.disabledTabs) { _, newValue in
            disabledTabsDraft = newValue
        }
        .onChange(of: familySession.startTab) { _, newValue in
            startTabDraft = newValue
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
