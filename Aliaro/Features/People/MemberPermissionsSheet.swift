import SwiftUI

/// Lets an admin (the group's creator, or a member promoted to admin)
/// change what another member is allowed to do: turn individual
/// permissions on/off, or make them an admin themselves. Never opened
/// (editably) for the creator — their permissions can't be restricted.
struct MemberPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familyService: FamilyService

    let member: FamilyMember

    @State private var restrictedDraft: Set<String> = []
    @State private var isAdminDraft = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isCreator: Bool { member.isCreator }

    private func isGranted(_ permission: FamilyPermission) -> Bool {
        isAdminDraft || !restrictedDraft.contains(permission.rawValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isCreator {
                        ALICard(containerColor: ALIColors.surfaceVariant) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(ALIColors.mutedInk)
                                Text("\(member.name) created the group, so they always have every permission.")
                                    .font(ALITypography.bodyMedium)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                        }
                    } else {
                        adminCard

                        ForEach(FamilyPermission.Section.allCases) { section in
                            permissionsCard(for: section)
                        }
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            restrictedDraft = Set(member.restrictedPermissions)
            isAdminDraft = member.isAdmin
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var adminCard: some View {
        ALICard {
            Toggle(isOn: Binding(get: { isAdminDraft }, set: { setAdmin($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make admin")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text("Full access to everything, and can change other members' permissions (except the creator's).")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
            .tint(ALIColors.peopleAccent)
            .disabled(isSaving)
        }
    }

    private func permissionsCard(for section: FamilyPermission.Section) -> some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text(section.label)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                VStack(spacing: 10) {
                    ForEach(section.permissions) { permission in
                        Toggle(isOn: Binding(
                            get: { isGranted(permission) },
                            set: { toggle(permission, isOn: $0) }
                        )) {
                            Text(permission.label)
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(isAdminDraft ? ALIColors.mutedInk : ALIColors.ink)
                        }
                        .tint(section.accent)
                        .disabled(isSaving || isAdminDraft)
                    }
                }
            }
        }
        .opacity(isAdminDraft ? 0.6 : 1)
    }

    private func toggle(_ permission: FamilyPermission, isOn: Bool) {
        var updated = restrictedDraft
        if isOn {
            updated.remove(permission.rawValue)
        } else {
            updated.insert(permission.rawValue)
        }
        save(restrictedPermissions: updated, isAdmin: isAdminDraft)
    }

    private func setAdmin(_ isOn: Bool) {
        save(restrictedPermissions: restrictedDraft, isAdmin: isOn)
    }

    private func save(restrictedPermissions: Set<String>, isAdmin: Bool) {
        let previousRestricted = restrictedDraft
        let previousAdmin = isAdminDraft
        restrictedDraft = restrictedPermissions
        isAdminDraft = isAdmin
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await familyService.updateMemberPermissions(
                    targetMemberID: member.id,
                    restrictedPermissions: restrictedPermissions,
                    isAdmin: isAdmin
                )
            } catch {
                errorMessage = error.localizedDescription
                restrictedDraft = previousRestricted
                isAdminDraft = previousAdmin
            }
        }
    }
}
