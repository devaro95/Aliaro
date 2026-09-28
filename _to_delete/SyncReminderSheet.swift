import SwiftUI

/// Shown once, right after this device creates or joins a family group,
/// if it isn't linked to a real account yet (`FamilyService.showSyncReminder`).
/// Purely informational — points to the People tab, where `PeopleScreen`'s
/// own banner (and `LoginSheet`) actually do the linking — rather than
/// collecting the email inline, so the person isn't asked for it twice.
struct SyncReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premium: PremiumManager

    /// Cloud sync itself is free to keep using once set up — only the act
    /// of linking an email (`.link`, the actual button this sheet points
    /// to in People) is gated. Shown here so this doesn't read as a free
    /// promise when it isn't.
    private var isCloudBackupLocked: Bool { premium.isLocked(.cloudBackup) }

    var body: some View {
        trackedBody.trackScreen("sync_reminder")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(ALIColors.peopleAccent)
                .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Don't lose this group")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)
                    .multilineTextAlignment(.center)
                if isCloudBackupLocked {
                    HStack(spacing: 5) {
                        ALIPremiumLockBadge()
                        Text("Aliaro Premium feature")
                            .font(ALITypography.labelLarge)
                    }
                    .foregroundStyle(ALIColors.economiaAccent)
                }
                Text("To keep everything saved and get it back if you reinstall the app or switch phones, sync with the cloud. You can do this any time from People.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            ALIPrimaryButton(text: "Got it", accent: ALIColors.peopleAccent) {
                dismiss()
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 20)
        .background(ALIColors.background)
        .presentationDetents([.height(320)])
    }
}
