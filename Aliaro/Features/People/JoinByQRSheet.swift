import SwiftUI
import SwiftData

/// Sheet that opens the camera to scan someone else's invite QR code
/// and, after reading it, asks for the name before joining the family group.
struct JoinByQRSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var scannedToken: String?
    @State private var scannedFamilyName: String?
    @State private var isCheckingInvite = false
    @State private var scanErrorMessage: String?

    var body: some View {
        trackedBody.trackScreen("join_by_qr")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ZStack {
                QRScannerView { payload in
                    guard scannedToken == nil, !isCheckingInvite else { return }
                    guard let token = InviteLink.token(from: payload) else {
                        scanErrorMessage = "That code isn't an Aliaro invite."
                        return
                    }
                    scanErrorMessage = nil
                    checkInvite(token: token)
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text(scanErrorMessage ?? (isCheckingInvite ? String(localized: "Checking invite…") : String(localized: "Point at an Aliaro invite QR code")))
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { scannedToken != nil },
                set: { if !$0 { scannedToken = nil; scannedFamilyName = nil } }
            )) {
                if let scannedToken {
                    NameEntrySheet(title: "What's your name?", confirmTitle: "Join group", joiningFamilyName: scannedFamilyName) { name in
                        // Fire-and-forget, mirroring `CreateFamilySheet`: this
                        // dismisses right away and `ContentView` takes over
                        // with the "loading your family group" screen while
                        // `FamilyService` does the actual work behind it.
                        familyService.startJoiningFamily(token: scannedToken, myName: name, modelContext: modelContext, dataSync: dataSync)
                        await MainActor.run { dismiss() }
                    }
                }
            }
        }
    }

    /// Looks up the group's name before opening the "join" dialog, so
    /// the person knows which group they're joining before confirming.
    private func checkInvite(token: String) {
        isCheckingInvite = true
        Task {
            do {
                let familyName = try await familyService.inviteInfo(token: token)
                Track.event("join_invite_checked", ["method": "qr", "valid": true])
                await MainActor.run {
                    isCheckingInvite = false
                    scannedFamilyName = familyName
                    scannedToken = token
                }
            } catch {
                Track.event("join_invite_checked", ["method": "qr", "valid": false])
                await MainActor.run {
                    isCheckingInvite = false
                    scanErrorMessage = error.localizedDescription
                }
            }
        }
    }

}
