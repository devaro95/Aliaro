import SwiftUI

/// Confirmation sheet before joining a family group. The member's name is
/// always the one on the account (`AuthSession.displayName`, set at
/// sign-up) — it's never asked here. `onConfirm` can throw; the error is
/// shown inline.
struct NameEntrySheet: View {
    let title: String
    let confirmTitle: String
    /// Name of the family group being joined, when known (joining by
    /// QR or link). `nil` when creating a new group, where it doesn't apply.
    var joiningFamilyName: String? = nil
    let onConfirm: (String) async throws -> Void

    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var resolvedName: String { authSession.displayName ?? "" }

    var body: some View {
        trackedBody.trackScreen("name_entry")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Join family group")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                if let joiningFamilyName {
                    Text("You're joining the group \"\(joiningFamilyName)\"")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                }

                ALIPrimaryButton(
                    text: isSubmitting ? "One moment…" : LocalizedStringKey(confirmTitle),
                    enabled: !resolvedName.isEmpty && !isSubmitting,
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
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        let trimmedName = resolvedName
        guard !trimmedName.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await onConfirm(trimmedName)
                isSubmitting = false
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
