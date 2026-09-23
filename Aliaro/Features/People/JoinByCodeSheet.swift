import SwiftUI
import SwiftData

/// Alternative to the QR code: type in the 6-character invite code someone
/// else in the group shared (out loud, by chat...), without needing the camera.
struct JoinByCodeSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var codeText = ""
    @State private var parsedCode: String?
    @State private var parsedFamilyName: String?
    @State private var isChecking = false
    @State private var errorMessage: String?

    private static let codeLength = 6

    var body: some View {
        trackedBody.trackScreen("join_by_code")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Join with a code")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                Text("Type in the 6-character code someone in your family shared with you. It expires 15 minutes after being generated.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                ALITextField(placeholder: "Invite code", text: $codeText, onSubmit: submit)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(.title2, design: .monospaced))
                    .onChange(of: codeText) { _, newValue in
                        let sanitized = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Self.codeLength))
                        if sanitized != newValue { codeText = sanitized }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                }

                ALIPrimaryButton(
                    text: isChecking ? "Checking…" : "Continue",
                    enabled: codeText.count == Self.codeLength && !isChecking,
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
            .sheet(isPresented: Binding(
                get: { parsedCode != nil },
                set: { if !$0 { parsedCode = nil; parsedFamilyName = nil } }
            )) {
                if let parsedCode {
                    NameEntrySheet(title: "What's your name?", confirmTitle: "Join group", joiningFamilyName: parsedFamilyName) { name in
                        // Fire-and-forget, mirroring `CreateFamilySheet`: this
                        // dismisses right away and `ContentView` takes over
                        // with the "loading your family group" screen while
                        // `FamilyService` does the actual work behind it.
                        familyService.startJoiningFamily(code: parsedCode, myName: name, modelContext: modelContext, dataSync: dataSync)
                        await MainActor.run { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Validates the code and, if it's valid, looks up the group's name
    /// before opening the "join" dialog.
    private func submit() {
        guard codeText.count == Self.codeLength else { return }
        errorMessage = nil
        isChecking = true
        let code = codeText
        Task {
            do {
                let familyName = try await familyService.inviteInfo(code: code)
                Track.event("join_invite_checked", ["method": "code", "valid": true])
                await MainActor.run {
                    isChecking = false
                    parsedFamilyName = familyName
                    parsedCode = code
                }
            } catch {
                Track.event("join_invite_checked", ["method": "code", "valid": false])
                await MainActor.run {
                    isChecking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
