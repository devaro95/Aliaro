import SwiftUI

/// Email + password log in. On success `AuthSession.isSignedIn` flips and
/// `ContentView` moves on by itself (to the family group, or to create/join).
struct LoginView: View {
    @Binding var path: [AuthWelcomeView.Route]

    @EnvironmentObject private var authSession: AuthSession

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSubmitting && AuthValidation.isValidEmail(email.trimmed) && !password.isEmpty
    }

    var body: some View {
        AuthFormScaffold(
            title: "Log in",
            subtitle: "Welcome back! Log in to get to your family group.",
            errorMessage: errorMessage
        ) {
            ALITextField(placeholder: "Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            ALISecureField(placeholder: "Password", text: $password, onSubmit: submit)

            HStack {
                Spacer()
                Button("Forgot your password?") {
                    Track.event("auth_forgot_password_tap")
                    path.append(.forgotPassword(email: email.trimmed))
                }
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            }

            ALIPrimaryButton(
                text: isSubmitting ? "One moment…" : "Log in",
                enabled: canSubmit,
                accent: ALIColors.familyAccent,
                action: submit
            )
            .padding(.top, 8)

            ALITextButton(text: "Don't have an account? Create one") {
                path = [.register]
            }
        }
        .trackScreen("auth_login")
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let email = email.trimmed
        Task {
            do {
                try await authSession.signIn(email: email, password: password)
                Track.event("auth_login_success")
            } catch {
                isSubmitting = false
                Track.event("auth_login_error")
                if AuthErrorMessage.isEmailNotConfirmed(error) {
                    try? await authSession.resendSignUpCode(email: email)
                    path.append(.confirmEmail(email: email))
                } else {
                    errorMessage = AuthErrorMessage.text(for: error)
                }
            }
        }
    }
}
