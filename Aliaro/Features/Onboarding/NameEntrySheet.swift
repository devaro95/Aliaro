import SwiftUI

/// Simple sheet to ask for the person's name before creating or joining a
/// family group. `onConfirm` can throw; the error is shown inline.
struct NameEntrySheet: View {
    let title: String
    let confirmTitle: String
    /// Name of the family group being joined, when known (joining by
    /// QR or link). `nil` when creating a new group, where it doesn't apply.
    var joiningFamilyName: String? = nil
    let onConfirm: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title)
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                if let joiningFamilyName {
                    Text("You're joining the group \"\(joiningFamilyName)\"")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .multilineTextAlignment(.center)
                }

                ALITextField(placeholder: "Your name", text: $name, onSubmit: submit)

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                }

                ALIPrimaryButton(
                    text: isSubmitting ? "One moment…" : LocalizedStringKey(confirmTitle),
                    enabled: !name.trimmed.isEmpty && !isSubmitting,
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
        let trimmedName = name.trimmed
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
