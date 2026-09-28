import SwiftUI

/// Password recovery in two steps, without leaving the app: (1) email →
/// Supabase sends a code, (2) code + new password → signs the person in
/// with the new password.
struct ForgotPasswordView: View {
    let initialEmail: String

    @EnvironmentObject private var authSession: AuthSession

    private enum Step { case email, reset }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSendCode: Bool { !isSubmitting && AuthValidation.isValidEmail(email.trimmed) }

    private var canReset: Bool {
        !isSubmitting
            && AuthValidation.isValidCode(code.trimmed)
            && newPassword.count >= AuthValidation.minPasswordLength
    }

    var body: some View {
        Group {
            switch step {
            case .email: emailStep
            case .reset: resetStep
            }
        }
        .onAppear { if email.isEmpty { email = initialEmail } }
        .trackScreen("auth_forgot_password")
    }

    private var emailStep: some View {
        AuthFormScaffold(
            title: "Reset your password",
            subtitle: "Enter your account's email and we'll send you a code to set a new password.",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Email", text: $email, onSubmit: sendCode)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Send code",
                enabled: canSendCode,
                accent: ALIColors.familyAccent,
                action: sendCode
            )
            .padding(.top, 8)
        }
    }

    private var resetStep: some View {
        AuthFormScaffold(
            title: "New password",
            subtitle: "Enter the code we sent to \(email.trimmed) and choose a new password.",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            VStack(alignment: .leading, spacing: 6) {
                ALISecureField(placeholder: "New password", text: $newPassword, isNewPassword: true, onSubmit: reset)
                Text("At least \(AuthValidation.minPasswordLength) characters")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.leading, 4)
            }

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Save and log in",
                enabled: canReset,
                accent: ALIColors.familyAccent,
                action: reset
            )
            .padding(.top, 8)

            ALITextButton(text: "Use a different email") {
                step = .email
                code = ""
                newPassword = ""
                errorMessage = nil
            }
        }
    }

    private func sendCode() {
        guard canSendCode else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await authSession.sendPasswordReset(email: email.trimmed)
                Track.event("auth_reset_code_sent")
                isSubmitting = false
                step = .reset
            } catch {
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }

    private func reset() {
        guard canReset else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await authSession.resetPassword(email: email.trimmed, code: code.trimmed, newPassword: newPassword)
                Track.event("auth_reset_success")
            } catch {
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}
