import SwiftUI

/// Turns this device's anonymous session into a real account (just an
/// email — confirmed by typing the 6-digit code Supabase sends), so the
/// family group survives a reinstall. Two entry points share this same
/// flow:
/// - `.link`: from an existing family group (banner in People, or right
///   after creating/joining a group) — keeps the current session, just
///   adds an email to it.
/// - `.signIn`: from a fresh install with no group yet ("I already have
///   an account") — signs in to a previously-linked account; on success
///   the caller still needs to try recovering the family group it
///   belongs to (`FamilyService.restoreMembership`).
///
/// `.link` can fail because the email already belongs to a DIFFERENT,
/// already-registered account — meaning this device (with its own group)
/// and that account (possibly with its own, different group) can't both
/// keep what they have. `showReplaceGroupWarning` asks which one should
/// win, right when that's detected, before sending any code.
struct LoginSheet: View {
    enum Mode {
        case link
        case signIn
    }

    let mode: Mode
    var onSuccess: () -> Void = {}

    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var step: Step = .email
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Set once the person picks "continue" on `showReplaceGroupWarning`:
    /// `.link` failed because the email belongs to another account, and
    /// they chose to sign in to it (and adopt whatever group it already
    /// has) instead, replacing this device's current group.
    @State private var usingSignInFallback = false
    /// Shown right when `.link` fails because the email already belongs
    /// to another account — asks whether to replace this device's group
    /// with that account's, or leave this group and log in fresh instead.
    @State private var showReplaceGroupWarning = false

    private enum Step { case email, code }

    private var effectiveMode: Mode { usingSignInFallback ? .signIn : mode }

    private var canSubmitEmail: Bool {
        !isSubmitting && email.trimmed.contains("@")
    }

    private var canSubmitCode: Bool {
        !isSubmitting && code.trimmed.count == 8
    }

    private var title: LocalizedStringKey {
        effectiveMode == .link ? "Save your family group" : "Log in"
    }

    private var subtitle: LocalizedStringKey {
        switch (effectiveMode, step) {
        case (.link, .email):
            return "Aliaro Premium: add an email so you can always get your group back, even after reinstalling the app."
        case (.signIn, .email):
            return "Enter the email you used before to recover your family group."
        case (_, .code):
            return "Enter the 8-digit code we sent to \(email.trimmed)."
        }
    }

    var body: some View {
        trackedBody.trackScreen("login")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title)
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                Text(subtitle)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)

                if step == .email {
                    ALITextField(placeholder: "Email", text: $email, onSubmit: submitEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    ALITextField(placeholder: "8-digit code", text: $code, onSubmit: submitCode)
                        .keyboardType(.numberPad)
                    ALITextButton(text: "Use a different email") {
                        step = .email
                        code = ""
                        errorMessage = nil
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                        .multilineTextAlignment(.center)
                }

                if step == .email {
                    ALIPrimaryButton(
                        text: isSubmitting ? "One moment…" : "Send code",
                        enabled: canSubmitEmail,
                        accent: ALIColors.peopleAccent,
                        action: submitEmail
                    )
                } else {
                    ALIPrimaryButton(
                        text: isSubmitting ? "One moment…" : "Confirm",
                        enabled: canSubmitCode,
                        accent: ALIColors.peopleAccent,
                        action: submitCode
                    )
                }

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
        .confirmationDialog(
            "This account already has a family group",
            isPresented: $showReplaceGroupWarning,
            titleVisibility: .visible
        ) {
            Button("Continue — sign in and use that group instead", role: .destructive) {
                Track.event("login_replace_group_choice", ["choice": "replace"])
                usingSignInFallback = true
                submitEmail()
            }
            Button("Leave this group & go to the login screen") {
                Track.event("login_replace_group_choice", ["choice": "leave_first"])
                Task { await leaveCurrentGroupAndReturnToLogin() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing in with this email will replace your current family group with the one already linked to it. You can also leave this group first and sign in from the home screen to join the other one instead.")
        }
    }

    private func submitEmail() {
        guard canSubmitEmail else { return }
        isSubmitting = true
        errorMessage = nil
        let modeKey = effectiveMode == .link ? "link" : "sign_in"
        Track.event("login_email_submit", ["mode": modeKey, "fallback": usingSignInFallback])
        Task {
            do {
                switch effectiveMode {
                case .link: try await authSession.requestLink(email: email.trimmed)
                case .signIn: try await authSession.requestSignIn(email: email.trimmed)
                }
                isSubmitting = false
                code = ""
                step = .code
                Track.event("login_code_sent", ["mode": modeKey])
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
                Track.event("login_email_error", ["mode": modeKey, "already_registered": isAlreadyRegisteredError(error)])
                if mode == .link, !usingSignInFallback, isAlreadyRegisteredError(error) {
                    // This device has its own group, and this email
                    // belongs to a different, already-registered account
                    // — ask which group should win before doing anything.
                    showReplaceGroupWarning = true
                }
            }
        }
    }

    private func isAlreadyRegisteredError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("already")
    }

    private func submitCode() {
        guard canSubmitCode else { return }
        Task { await confirmCode() }
    }

    private func confirmCode() async {
        isSubmitting = true
        errorMessage = nil
        let modeKey = effectiveMode == .link ? "link" : "sign_in"
        Track.event("login_code_submit", ["mode": modeKey])
        do {
            switch effectiveMode {
            case .link:
                try await authSession.confirmLink(email: email.trimmed, code: code.trimmed)
            case .signIn where usingSignInFallback:
                // Reached via the warning dialog above: the person already
                // chose to replace this device's group with whatever this
                // account already has linked to it.
                try await familyService.leaveFamily(modelContext: modelContext, dataSync: dataSync)
                try await authSession.confirmSignIn(email: email.trimmed, code: code.trimmed)
                _ = try await familyService.restoreMembershipShowingProgress(modelContext: modelContext, dataSync: dataSync)
            case .signIn:
                // Plain sign-in from the onboarding screen (no group yet
                // on this device) — the caller restores the group itself
                // via `onSuccess` (see `FamilyOnboardingView`).
                try await authSession.confirmSignIn(email: email.trimmed, code: code.trimmed)
            }
            isSubmitting = false
            Track.event("login_success", ["mode": modeKey, "replaced_group": usingSignInFallback])
            Track.refreshUserProperties()
            onSuccess()
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            Track.event("login_code_error", ["mode": modeKey])
        }
    }

    /// "Leave this group & go to the login screen": leaves the current
    /// group without signing in to the other account yet. Leaving flips
    /// `hasJoinedFamily` to false, so `ContentView` swaps back to
    /// `FamilyOnboardingView` on its own the moment this sheet closes,
    /// where the person can sign in to that other account from scratch.
    private func leaveCurrentGroupAndReturnToLogin() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await familyService.leaveFamily(modelContext: modelContext, dataSync: dataSync)
            isSubmitting = false
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}
