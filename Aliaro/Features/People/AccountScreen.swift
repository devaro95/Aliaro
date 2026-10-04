import SwiftUI
import StoreKit
import SwiftData
import Supabase

/// Account settings, opened from the "Account" card at the bottom of
/// People: change the name shown in the family group, change the
/// password, and log out. Logging out keeps this person in the family
/// group — logging back in restores it. Deleting the account (required by
/// the App Store) lives at the bottom, behind a password check.
struct AccountScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @State private var showLogoutConfirmation = false
    @State private var isLoggingOut = false

    private var myName: String? {
        authSession.displayName ?? members.first(where: { $0.isCurrentDevice })?.name
    }

    var body: some View {
        trackedBody.trackScreen("account")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ALICard {
                        VStack(spacing: 0) {
                            NavigationLink {
                                ChangeNameView(currentName: myName ?? "")
                            } label: {
                                row(icon: "person.text.rectangle", title: "Name", subtitle: myName)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(ALIColors.outline)
                            NavigationLink {
                                ChangePasswordView()
                            } label: {
                                row(icon: "key", title: "Change password", subtitle: authSession.email)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ALICard {
                        logoutRow
                    }

                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Text("Delete account")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .underline()
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(ALIColors.ink)
    }

    private func row(icon: String, title: LocalizedStringKey, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ALIColors.peopleAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ALIColors.mutedInk)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var logoutRow: some View {
        Button {
            Track.event("logout_tap")
            showLogoutConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Group {
                    if isLoggingOut {
                        ProgressView()
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 24)
                Text("Log out")
                    .font(ALITypography.bodyLarge)
                Spacer()
            }
            .foregroundStyle(ALIColors.error)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoggingOut)
        .confirmationDialog("Log out of Aliaro?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                isLoggingOut = true
                Task {
                    await familyService.signOut(modelContext: modelContext, dataSync: dataSync)
                    isLoggingOut = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let email = authSession.email {
                Text("You're logged in as \(email). You'll stay in your family group — log back in to get everything back.")
            } else {
                Text("You'll stay in your family group. Log back in to get everything back.")
            }
        }
    }
}

/// Changes the name this person shows with in the family group.
private struct ChangeNameView: View {
    let currentName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var familyService: FamilyService

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && trimmedName.count <= 40 && trimmedName != currentName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This is how the rest of your family group sees you.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
            ALITextField(placeholder: "Your name", text: $name, onSubmit: save)
                .textContentType(.name)
            if let errorMessage {
                Text(errorMessage)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.error)
            }
            ALIPrimaryButton(
                text: isSaving ? "One moment…" : "Save",
                enabled: canSave,
                accent: ALIColors.peopleAccent,
                action: save
            )
            Spacer()
        }
        .padding(20)
        .background(ALIColors.background)
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if name.isEmpty { name = currentName } }
        .trackScreen("change_name")
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await familyService.updateMyName(trimmedName, modelContext: modelContext)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Changes the account password, asking for the current one first.
private struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private var canSave: Bool {
        !isSaving
            && !currentPassword.isEmpty
            && newPassword.count >= AuthValidation.minPasswordLength
            && newPassword != currentPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ALISecureField(placeholder: "Current password", text: $currentPassword)
            VStack(alignment: .leading, spacing: 6) {
                ALISecureField(placeholder: "New password", text: $newPassword, isNewPassword: true, onSubmit: save)
                Text("At least \(AuthValidation.minPasswordLength) characters")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.leading, 4)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.error)
            }
            ALIPrimaryButton(
                text: isSaving ? "One moment…" : "Change password",
                enabled: canSave,
                accent: ALIColors.peopleAccent,
                action: save
            )
            Spacer()
        }
        .padding(20)
        .background(ALIColors.background)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password changed", isPresented: $didSave) {
            Button("OK") { dismiss() }
        }
        .trackScreen("change_password")
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await authSession.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                Track.event("password_changed")
                didSave = true
            } catch {
                Track.event("password_change_error")
                if let authError = error as? AuthError, authError.errorCode == .invalidCredentials {
                    errorMessage = String(localized: "Your current password is incorrect.")
                } else {
                    errorMessage = AuthErrorMessage.text(for: error)
                }
            }
            isSaving = false
        }
    }
}

/// Permanently deletes the account after asking for the password again.
/// Leaves the family group (the rest keep their data; if this was the
/// last member, the whole group is deleted). An App Store subscription
/// isn't cancelled by this — the person does it in Apple's own sheet.
private struct DeleteAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var premiumManager: PremiumManager

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    @State private var showManageSubscription = false

    private var canDelete: Bool { !isDeleting && !password.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This permanently deletes your Aliaro account. You'll leave your family group; if you're its only member, the group and everything in it will be deleted too. This can't be undone.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)

                if premiumManager.subscriptions.isSubscribed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deleting your account doesn't cancel your Aliaro Premium subscription. Cancel it first if you don't want to keep paying.")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                        Button("Manage subscription") { showManageSubscription = true }
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.peopleAccent)
                    }
                }

                ALISecureField(placeholder: "Password", text: $password, onSubmit: { if canDelete { showConfirmation = true } })

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.error)
                }

                ALIPrimaryButton(
                    text: isDeleting ? "One moment…" : "Delete account",
                    enabled: canDelete,
                    accent: ALIColors.error,
                    action: { showConfirmation = true }
                )
            }
            .padding(20)
        }
        .background(ALIColors.background)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your account?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .trackScreen("delete_account")
    }

    private func delete() {
        guard canDelete else { return }
        Track.event("account_delete_tap")
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await familyService.deleteAccount(password: password, modelContext: modelContext, dataSync: dataSync)
            } catch {
                Track.event("account_delete_error")
                if let authError = error as? AuthError, authError.errorCode == .invalidCredentials {
                    errorMessage = String(localized: "Your password is incorrect.")
                } else {
                    errorMessage = AuthErrorMessage.text(for: error)
                }
            }
            isDeleting = false
        }
    }
}
