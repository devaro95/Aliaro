import SwiftUI

/// Password recovery, without leaving the app, in three screens:
/// 1. `ForgotPasswordView`: email → Supabase sends a code.
/// 2. `ResetCodeView`: the code (resend after 60 s).
/// 3. `NewPasswordView`: new password → signs the person in.
/// Going back from 2 or 3 always lands on the log in screen (the path is
/// rebuilt as `[.login, …]`); leaving 3 without saving drops the recovery
/// session (`AuthSession.cancelPasswordRecovery`).
struct ForgotPasswordView: View {
    @Binding var path: [AuthWelcomeView.Route]
    let initialEmail: String

    @EnvironmentObject private var authSession: AuthSession

    @State private var email = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSendCode: Bool { !isSubmitting && AuthValidation.isValidEmail(email.trimmed) }

    var body: some View {
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
        .onAppear { if email.isEmpty { email = initialEmail } }
        .trackScreen("auth_forgot_password")
    }

    private func sendCode() {
        guard canSendCode else { return }
        isSubmitting = true
        errorMessage = nil
        let email = email.trimmed
        Task {
            do {
                try await authSession.sendPasswordReset(email: email)
                Track.event("auth_reset_code_sent")
                isSubmitting = false
                // Replaces this screen: back from the code goes to log in.
                path = [.login, .resetCode(email: email)]
            } catch {
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}

/// Step 2: the code from the email. "Resend code" is locked for 60 s
/// after each send, like `ConfirmEmailView`.
struct ResetCodeView: View {
    @Binding var path: [AuthWelcomeView.Route]
    let email: String

    @EnvironmentObject private var authSession: AuthSession

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resendCooldown = ConfirmEmailView.resendInterval
    @State private var isResending = false

    private var canSubmit: Bool { !isSubmitting && AuthValidation.isValidCode(code.trimmed) }

    var body: some View {
        AuthFormScaffold(
            title: "Reset your password",
            subtitle: "Enter the code we sent to \(email).",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Code", text: $code, onSubmit: submit)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Continue",
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

            ALITextButton(text: "Use a different email") {
                path = [.login, .forgotPassword(email: email)]
            }
        }
        .task(id: resendCooldown > 0) {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                resendCooldown -= 1
            }
        }
        .trackScreen("auth_reset_code")
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await authSession.verifyRecoveryCode(email: email, code: code.trimmed)
                Track.event("auth_reset_code_ok")
                isSubmitting = false
                // Replaces this screen: back from the new password goes to log in.
                path = [.login, .newPassword]
            } catch {
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }

    private func resend() {
        guard resendCooldown == 0, !isResending else { return }
        isResending = true
        errorMessage = nil
        Task {
            do {
                try await authSession.sendPasswordReset(email: email)
                Track.event("auth_reset_code_resend")
                resendCooldown = ConfirmEmailView.resendInterval
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
            isResending = false
        }
    }
}

/// Step 3: the new password. Saving it signs the person in (`ContentView`
/// moves on by itself). Leaving without saving (back button or swipe)
/// cancels the recovery session, so log in is shown signed out.
struct NewPasswordView: View {
    @EnvironmentObject private var authSession: AuthSession

    @State private var newPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private var isPasswordLongEnough: Bool { newPassword.count >= AuthValidation.minPasswordLength }
    private var canSubmit: Bool { !isSubmitting && isPasswordLongEnough }

    var body: some View {
        AuthFormScaffold(
            title: "New password",
            subtitle: "Choose a new password for your account.",
            errorMessage: errorMessage
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ALISecureField(placeholder: "New password", text: $newPassword, isNewPassword: true, onSubmit: submit)
                Text("At least \(AuthValidation.minPasswordLength) characters")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(newPassword.isEmpty || isPasswordLongEnough ? ALIColors.mutedInk : ALIColors.error)
                    .padding(.leading, 4)
            }

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Save and log in",
                enabled: canSubmit,
                accent: ALIColors.familyAccent,
                action: submit
            )
            .padding(.top, 8)
        }
        .onDisappear {
            guard !didSave else { return }
            Task { await authSession.cancelPasswordRecovery() }
        }
        .trackScreen("auth_new_password")
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                didSave = true
                try await authSession.setNewPassword(newPassword)
                Track.event("auth_reset_success")
            } catch {
                didSave = false
                isSubmitting = false
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}
