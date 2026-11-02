import SwiftUI

/// Sheet to send a suggestion or report a bug. Saved in Supabase's
/// `feedback` table; a trigger there notifies Varo through ntfy.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familySession: FamilySession

    enum Kind: String, CaseIterable, Identifiable {
        case suggestion, bug
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .suggestion ? "Suggestion" : "Bug" }
        var placeholder: LocalizedStringKey {
            self == .suggestion ? "What would you improve or add?" : "What happened? Tell us where and how"
        }
    }

    static let maxLength = 2000

    @State private var kind: Kind = .suggestion
    @State private var text = ""
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmed.isEmpty && !isSending }

    var body: some View {
        trackedBody.trackScreen("feedback")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(kind.placeholder, text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(6...12)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                        .padding(16)
                        .background(ALIColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ALIColors.outline, lineWidth: 1)
                        )
                        .onChange(of: text) { _, new in
                            if new.count > Self.maxLength { text = String(new.prefix(Self.maxLength)) }
                        }

                    ALIPrimaryButton(
                        text: isSending ? "Sending…" : "Send",
                        enabled: canSend,
                        accent: ALIColors.peopleAccent
                    ) {
                        Task { await send() }
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Suggestions and bugs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .alert("Couldn't send", isPresented: .constant(sendError != nil)) {
                Button("OK", role: .cancel) { sendError = nil }
            } message: {
                Text(sendError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private struct NewFeedback: Encodable {
        let kind: String
        let message: String
        let family_id: UUID?
        let member_id: UUID?
        let platform: String
        let app_version: String
        let locale: String
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        do {
            try await supabase
                .from("feedback")
                .insert(NewFeedback(
                    kind: kind.rawValue,
                    message: text.trimmed,
                    family_id: familySession.familyID,
                    member_id: familySession.memberID,
                    platform: "ios",
                    app_version: build.isEmpty ? version : "\(version) (\(build))",
                    locale: Locale.current.identifier
                ))
                .execute()
            Track.event("feedback_sent", ["kind": kind.rawValue])
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }
}
