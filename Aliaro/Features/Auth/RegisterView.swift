import SwiftUI

/// Create an account: name, email and password. The name is saved on the
/// account (`user_metadata.name`) and reused when creating/joining a group.
struct RegisterView: View {
    @Binding var path: [AuthWelcomeView.Route]

    @EnvironmentObject private var authSession: AuthSession

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isPasswordLongEnough: Bool { password.count >= AuthValidation.minPasswordLength }

    private var canSubmit: Bool {
        !isSubmitting
            && !name.trimmed.isEmpty
            && AuthValidation.isValidEmail(email.trimmed)
            && isPasswordLongEnough
    }

    var body: some View {
        AuthFormScaffold(
            title: "Create account",
            subtitle: "Just a few details and you're in.",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)

            ALITextField(placeholder: "Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 6) {
                ALISecureField(placeholder: "Password", text: $password, isNewPassword: true, onSubmit: submit)
                Text("At least \(AuthValidation.minPasswordLength) characters")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(password.isEmpty || isPasswordLongEnough ? ALIColors.mutedInk : ALIColors.error)
                    .padding(.leading, 4)
            }

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Create account",
                enabled: canSubmit,
                accent: ALIColors.familyAccent,
                action: submit
            )
            .padding(.top, 8)

            ALITextButton(text: "Already have an account? Log in") {
                path = [.login]
            }
        }
        .trackScreen("auth_register")
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let email = email.trimmed
        Task {
            do {
                let result = try await authSession.signUp(name: name.trimmed, email: email, password: password)
                isSubmitting = false
                Track.event("auth_register_success", ["needs_confirmation": result == .needsConfirmation])
                if result == .needsConfirmation {
                    path.append(.confirmEmail(email: email))
                }
            } catch {
                isSubmitting = false
                Track.event("auth_register_error")
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}

/// Shown when Supabase requires confirming the email after signing up:
/// type the code from the email to finish (signs the person in).
struct ConfirmEmailView: View {
    let email: String

    @EnvironmentObject private var authSession: AuthSession

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Seconds until "Resend code" can be tapped again. A code was just
    /// sent when this screen opens, so it starts locked.
    @State private var resendCooldown = ConfirmEmailView.resendInterval
    @State private var isResending = false

    static let resendInterval = 60

    private var canSubmit: Bool { !isSubmitting && AuthValidation.isValidCode(code.trimmed) }

    var body: some View {
        AuthFormScaffold(
            title: "Confirm your email",
            subtitle: "Enter the code we sent to \(email).",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Code", text: $code, onSubmit: submit)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Confirm",
                enabled: canSubmit,
                accent: ALIColors.familyAccent,
                action: submit
            )
            .padding(.top, 8)

            ALITextButton(text: resendCooldown > 0 ? "Resend code in \(resendCooldown) s" : "Resend code") {
                resend()
            }
            .disabled(resendCooldown > 0 || isResending)
            .opacity(resendCooldown > 0 || isResending ? 0.5 : 1)
        }
        .task(id: resendCooldown > 0) {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                resendCooldown -= 1
            }
        }
        .trackScreen("auth_confirm_email")
    }

    private func resend() {
        guard resendCooldown == 0, !isResending else { return }
        isResending = true
        errorMessage = nil
        Task {
            do {
                try await authSession.resendSignUpCode(email: email)
                Track.event("auth_confirm_email_resend")
                resendCooldown = Self.resendInterval
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
            isResending = false
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await authSession.confirmSignUp(email: email, code: code.trimmed)
                Track.event("auth_confirm_email_success")
            } catch {
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}

/// Mandatory, one-time step for accounts created before the name was
/// required at sign-up (no `user_metadata.name`). The account name is the
/// one used everywhere in the app, so nothing else is shown until it's set.
/// If this device already belongs to a group, the member's name there is
/// updated too.
struct CompleteNameView: View {
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool { !isSubmitting && !name.trimmed.isEmpty && name.trimmed.count <= 40 }

    var body: some View {
        NavigationStack {
            AuthFormScaffold(
                title: "What's your name?",
                subtitle: "This is how the rest of your family group sees you.",
                errorMessage: errorMessage
            ) {
                ALITextField(placeholder: "Your name", text: $name, onSubmit: submit)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)

                ALIPrimaryButton(
                    text: isSubmitting ? "One moment…" : "Continue",
                    enabled: canSubmit,
                    accent: ALIColors.familyAccent,
                    action: submit
                )
                .padding(.top, 8)

                ALITextButton(text: "Log out") {
                    Task { await authSession.signOut() }
                }
            }
        }
        .trackScreen("auth_complete_name")
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let newName = name.trimmed
        Task {
            do {
                if familySession.hasJoinedFamily {
                    // Also renames the member and syncs the account name.
                    try await familyService.updateMyName(newName, modelContext: modelContext)
                } else {
                    try await authSession.updateDisplayName(newName)
                }
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
            isSubmitting = false
        }
    }
}
