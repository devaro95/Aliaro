import SwiftUI
import Combine
import UIKit
import CoreImage.CIFilterBuiltins

/// Sheet that generates a single-use invite and shows it as a QR code so
/// another person can scan it and join the family group.
struct InviteQRSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage?
    @State private var inviteToken: String?
    @State private var shortCode: String?
    @State private var expiresAt: Date?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        trackedBody.trackScreen("invite_qr")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Invite someone")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)

                Text("Have the other person scan this code from Aliaro to join your family group.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(ALIColors.surface)
                        .frame(width: 240, height: 240)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(ALIColors.outline, lineWidth: 1)
                        )

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 200, height: 200)
                    } else if isLoading {
                        ProgressView()
                    }
                }

                if let expiresAt {
                    Text(timeRemainingLabel(until: expiresAt))
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.error)
                }

                if let shortCode {
                    VStack(spacing: 8) {
                        Text("Or share this code")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)

                        Button {
                            Track.event("invite_code_copied")
                            UIPasteboard.general.string = shortCode
                        } label: {
                            HStack(spacing: 10) {
                                Text(shortCode)
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .kerning(2)
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 16))
                            }
                            .foregroundStyle(ALIColors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                            .background(ALIColors.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await generateInvite() }
        .onReceive(timer) { date in
            now = date
            if let expiresAt, expiresAt <= date {
                Task { await generateInvite() }
            }
        }
    }

    private func generateInvite() async {
        isLoading = true
        errorMessage = nil
        qrImage = nil
        do {
            let invite = try await familyService.createInvite()
            inviteToken = invite.token
            shortCode = invite.shortCode
            expiresAt = invite.expiresAtDate
            qrImage = Self.renderQR(from: InviteLink.url(token: invite.token).absoluteString)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func timeRemainingLabel(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return "Valid \(seconds / 60):\(String(format: "%02d", seconds % 60)) min"
    }

    private static func renderQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
