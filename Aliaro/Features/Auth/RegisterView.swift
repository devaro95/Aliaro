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
    @State private var didResend = false

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

            ALITextButton(text: didResend ? "Code sent again" : "Resend code") {
                Task {
                    do {
                        try await authSession.resendSignUpCode(email: email)
                        didResend = true
                    } catch {
                        errorMessage = AuthErrorMessage.text(for: error)
                    }
                }
            }
            .disabled(didResend)
        }
        .trackScreen("auth_confirm_email")
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
