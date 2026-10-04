import SwiftUI
import Supabase

/// First screen for anyone who isn't signed in: create an account or log
/// in. Skipped entirely once `AuthSession.isSignedIn` (see `ContentView`).
struct AuthWelcomeView: View {
    enum Route: Hashable {
        case register
        case login
        case forgotPassword(email: String)
        case resetCode(email: String)
        case newPassword
        case confirmEmail(email: String)
    }

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .register:
                        RegisterView(path: $path)
                    case .login:
                        LoginView(path: $path)
                    case .forgotPassword(let email):
                        ForgotPasswordView(path: $path, initialEmail: email)
                    case .resetCode(let email):
                        ResetCodeView(path: $path, email: email)
                    case .newPassword:
                        NewPasswordView()
                    case .confirmEmail(let email):
                        ConfirmEmailView(email: email)
                    }
                }
        }
        .tint(ALIColors.ink)
        .trackScreen("auth_welcome")
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Circle()
                    .fill(ALIColors.familyAccent.opacity(0.25))
                    .frame(width: 120, height: 120)
                    .overlay(ALIIconView(icon: ALIIcon.home, size: 52))
                AliaroWordmark(size: 34)
                Text("Organize your home life as a family, all in one shared space.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                ALIPrimaryButton(text: "Create account", accent: ALIColors.familyAccent) {
                    Track.event("auth_choice", ["choice": "register"])
                    path.append(.register)
                }
                ALISecondaryButton(text: "Log in") {
                    Track.event("auth_choice", ["choice": "login"])
                    path.append(.login)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Shared layout for the auth screens: title, subtitle, content, error.
struct AuthFormScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var errorMessage: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(ALITypography.headlineLarge)
                        .foregroundStyle(ALIColors.ink)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)

                content

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ALIColors.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum AuthValidation {
    static let minPasswordLength = 6

    static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    static func isValidCode(_ code: String) -> Bool {
        (6...8).contains(code.count) && code.allSatisfy(\.isNumber)
    }
}

/// Friendly messages for the Supabase Auth errors people actually hit.
enum AuthErrorMessage {
    static func text(for error: Error) -> String {
        if case AuthSession.SignUpError.emailAlreadyRegistered? = error as? AuthSession.SignUpError {
            return String(localized: "There's already an account with this email. Log in instead.")
        }
        if let authError = error as? AuthError {
            let code = authError.errorCode
            if code == .invalidCredentials {
                return String(localized: "Incorrect email or password.")
            }
            if code == .emailExists || code == .userAlreadyExists {
                return String(localized: "There's already an account with this email. Log in instead.")
            }
            if code == .weakPassword {
                return String(localized: "That password is too weak. Use at least \(AuthValidation.minPasswordLength) characters.")
            }
            if code == .emailNotConfirmed {
                return String(localized: "Confirm your email before logging in.")
            }
            if code == .otpExpired {
                return String(localized: "That code is wrong or has expired.")
            }
            if code == .overEmailSendRateLimit || code == .overRequestRateLimit {
                return String(localized: "Too many attempts. Wait a moment and try again.")
            }
        }
        return error.localizedDescription
    }

    static func isEmailNotConfirmed(_ error: Error) -> Bool {
        (error as? AuthError)?.errorCode == .emailNotConfirmed
    }
}
