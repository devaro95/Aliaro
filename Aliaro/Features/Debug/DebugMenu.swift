#if DEBUG
import SwiftUI
import SwiftData
import UIKit

// MARK: - Shake detection

extension Notification.Name {
    /// Posted (debug builds only) every time the device is shaken.
    static let deviceDidShake = Notification.Name("aliaro.deviceDidShake")
}

extension UIWindow {
    /// Debug-only: forwards the shake gesture as a notification so SwiftUI
    /// can open `DebugMenuSheet` from anywhere in the app.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

private struct DebugMenuOnShake: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                DebugMenuSheet()
            }
    }
}

extension View {
    /// Debug-only: shaking the phone opens the debug menu bottom sheet.
    func debugMenuOnShake() -> some View { modifier(DebugMenuOnShake()) }
}

// MARK: - Sheet

/// Debug-only tools (moved out of People): fill every tab with sample
/// content for App Store screenshots, and clear it again. Local data
/// only, never synced.
struct DebugMenuSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSeedingMockData = false
    @State private var hasMockData = DebugMockData.hasSeededData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ALICard {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mock data")
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(ALIColors.ink)
                                Text("Fills every tab with sample content, for App Store screenshots.")
                                    .font(ALITypography.labelLarge)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                            ALIPrimaryButton(
                                text: isSeedingMockData ? "Adding sample data\u{2026}" : "Seed mock data for screenshots",
                                accent: ALIColors.peopleAccent
                            ) {
                                isSeedingMockData = true
                                DebugMockData.seed(modelContext: modelContext)
                                isSeedingMockData = false
                                hasMockData = DebugMockData.hasSeededData
                            }
                            .disabled(isSeedingMockData)

                            ALISecondaryButton(text: "Delete all mock data") {
                                DebugMockData.clear(modelContext: modelContext)
                                hasMockData = DebugMockData.hasSeededData
                            }
                            .disabled(!hasMockData)
                            .opacity(hasMockData ? 1 : 0.5)

                            ALISecondaryButton(text: "Preview force update screen") {
                                dismiss()
                                ForceUpdate.shared.debugPreview = true
                            }

                            ALISecondaryButton(text: "Show rating dialog") {
                                dismiss()
                                ReviewPrompt.shared.debugRequestNow()
                            }

                            ALISecondaryButton(text: "Reset rating counters") {
                                ReviewPrompt.shared.debugReset()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
