import SwiftUI

/// Sheet to create a new family group: asks only for the group's name — the
/// creator's name is always the account's (`AuthSession.displayName`, set
/// at sign-up). As soon as the group name is valid and
/// the user taps "Create group", this sheet hands the data off via
/// `onConfirm` and dismisses immediately — it does not wait for any
/// network call. `ContentView` takes over right away and shows the
/// "creating your group" screen while `FamilyService` does the actual
/// work (and surfaces any error) behind it — see
/// `FamilyService.isCreatingFamily` / `FamilyService.createFamilyError`.
struct CreateFamilySheet: View {
    let onConfirm: (_ familyName: String, _ myName: String) -> Void

    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss
    @State private var familyName = ""

    private var resolvedMyName: String { authSession.displayName ?? "" }

    private var canSubmit: Bool {
        !familyName.trimmed.isEmpty && !resolvedMyName.isEmpty
    }

    var body: some View {
        trackedBody.trackScreen("family_create")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Create family group")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                ALITextField(placeholder: "Group name (e.g. The Smiths)", text: $familyName, onSubmit: submit)

                ALIPrimaryButton(
                    text: "Create group",
                    enabled: canSubmit,
                    accent: ALIColors.familyAccent,
                    action: submit
                )

                Spacer()
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        let trimmedFamilyName = familyName.trimmed
        let trimmedMyName = resolvedMyName
        guard !trimmedFamilyName.isEmpty, !trimmedMyName.isEmpty else { return }
        onConfirm(trimmedFamilyName, trimmedMyName)
        dismiss()
    }
}
