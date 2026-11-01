import SwiftUI

/// Save flow for forms (recipe, event, task, reminder, note, expense): the
/// sheet waits until Supabase confirms the save before closing. If it
/// fails, a dialog explains it and offers to retry:
/// - **No connection**: it's already kept on the device (`PendingSync`)
///   and uploads by itself later, so "OK" just closes the form.
/// - **Rejected** by Supabase (no permission, invalid data…): "Discard"
///   undoes it (new → deleted on this device; edit → the saved version is
///   reloaded).
///
/// Quick actions (marking a product, completing a task…) don't wait: they
/// go through `PendingSync` and the general notice (`ALISaveFailureToast`).
@MainActor
final class ALISaveFlow: ObservableObject {
    enum Failure { case offline, rejected }

    @Published private(set) var isSaving = false
    @Published var failure: Failure?

    /// Past this, a slow connection counts as offline (the upload keeps going and is kept if it fails).
    private static let timeout: Duration = .seconds(10)

    private var id = UUID()
    private var attempt = 0
    private var retryUpload: (() -> Task<Void, Error>)?
    private var onDone: () -> Void = {}
    private var onDiscard: () -> Void = {}

    /// `upload` is the first attempt (already started); `retry` starts a new one.
    /// Without an upload (no family yet) it closes right away.
    func track(
        _ upload: Task<Void, Error>?,
        id: UUID,
        retry: (() -> Task<Void, Error>)?,
        onDone: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        guard let upload, let retry else { onDone(); return }
        self.id = id
        retryUpload = retry
        self.onDone = onDone
        self.onDiscard = onDiscard
        wait(for: upload)
    }

    func retry() {
        failure = nil
        Track.event("save_retry")
        if let retryUpload { wait(for: retryUpload()) }
    }

    func close() {
        let failed = failure
        failure = nil
        if failed == .rejected { onDiscard() } else { onDone() }
    }

    private func wait(for upload: Task<Void, Error>) {
        attempt += 1
        let current = attempt
        isSaving = true
        Task {
            try? await Task.sleep(for: Self.timeout)
            guard current == attempt, isSaving else { return }
            fail(.offline)
        }
        Task {
            let result = await upload.result
            guard current == attempt, isSaving else { return }
            switch result {
            case .success:
                isSaving = false
                onDone()
            case .failure(let error):
                if SyncErrors.isRetryable(error) {
                    fail(.offline)
                } else {
                    SyncErrors.claim(id) // this dialog replaces the general notice
                    fail(.rejected)
                }
            }
        }
    }

    private func fail(_ kind: Failure) {
        isSaving = false
        failure = kind
        Track.event("save_failed", ["kind": kind == .offline ? "offline" : "rejected"])
    }
}

private struct ALISaveFlowModifier: ViewModifier {
    @ObservedObject var flow: ALISaveFlow

    func body(content: Content) -> some View {
        content
            .disabled(flow.isSaving)
            .interactiveDismissDisabled(flow.isSaving)
            .overlay {
                if flow.isSaving {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(get: { flow.failure != nil }, set: { _ in }),
                presenting: flow.failure
            ) { failure in
                Button("Retry") { flow.retry() }
                if failure == .offline {
                    Button("OK", role: .cancel) { flow.close() }
                } else {
                    Button("Discard", role: .destructive) { flow.close() }
                }
            } message: { failure in
                if failure == .offline {
                    Text("There's no connection. It's saved on this device and will upload by itself when you're back online.")
                } else {
                    Text("Something went wrong while saving it. Try again in a moment.")
                }
            }
    }
}

extension View {
    /// Waits for the save and shows the "Couldn't save" dialog (see `ALISaveFlow`).
    func aliSaveFlow(_ flow: ALISaveFlow) -> some View {
        modifier(ALISaveFlowModifier(flow: flow))
    }
}

/// Short notice when Supabase rejects a quick change (outside a form).
struct ALISaveFailureToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(ALIColors.error)
            Text("A change couldn't be saved. Try again.")
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ALIColors.surface)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
