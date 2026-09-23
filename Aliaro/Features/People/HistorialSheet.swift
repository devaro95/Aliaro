import SwiftUI
import SwiftData

/// "History" of the family group: every create/edit/delete on a
/// shared item, and who did it — so no change goes unnoticed, even if
/// it was made by a kid on someone else's device. Premium (`historial`):
/// when locked, it opens as a preview built from sample entries (never
/// the group's real history), blurred, with a banner leading to the paywall.
struct HistorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premium: PremiumManager
    @Query(sort: \ActivityLogEntry.createdAt, order: .reverse) private var realEntries: [ActivityLogEntry]

    @State private var showPaywall = false

    private var isLocked: Bool { premium.isLocked(.historial) }
    private var entries: [ActivityLogEntry] { isLocked ? Self.demoEntries : realEntries }

    /// Sample history for the locked preview; never inserted into a context.
    @MainActor private static let demoEntries: [ActivityLogEntry] = {
        let now = Date.now
        let samples: [(String, String, String, String, Double)] = [
            ("house_task_log", String(localized: "Dishes"), "created", "Ana", 0.3),
            ("expense", String(localized: "Weekly groceries"), "created", "Luis", 2),
            ("reminder", String(localized: "Dentist appointment"), "updated", "Ana", 5),
            ("house_task", String(localized: "Change the sheets"), "created", "Marta", 20),
            ("family_event", String(localized: "Grandma's birthday"), "created", "Luis", 26),
            ("expense", String(localized: "Dinner out"), "deleted", "Ana", 30),
            ("house_task_log", String(localized: "Take out the trash"), "created", "Marta", 49),
            ("expense", String(localized: "Electricity bill"), "updated", "Luis", 72)
        ]
        return samples.map { type, name, action, actor, hoursAgo in
            ActivityLogEntry(
                entityType: type, entityName: name, action: action,
                actorName: actor, createdAt: now.addingTimeInterval(-hoursAgo * 3600)
            )
        }
    }()

    var body: some View {
        trackedBody.trackScreen("history")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if entries.isEmpty {
                        ALIEmptyState(
                            emoji: "🕘",
                            title: "No history yet",
                            subtitle: "Every time someone creates, edits or deletes something in the group, it'll show up here."
                        )
                    } else {
                        ALICard {
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    HistorialRow(entry: entry)
                                    if index < entries.count - 1 {
                                        Divider().overlay(ALIColors.outline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .aliPremiumPreview(isLocked)
            }
            .aliPremiumPreviewBanner(isLocked, buttonTitle: "Unlock history") { showPaywall = Track.paywall("history_banner") }
            .background(ALIColors.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents(isLocked ? [.large] : [.medium, .large])
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

private struct HistorialRow: View {
    let entry: ActivityLogEntry

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var entityLabel: String {
        switch entry.entityType {
        case "house_task": return String(localized: "Task")
        case "house_task_log": return String(localized: "Task history")
        case "family_event": return String(localized: "Calendar")
        case "reminder": return String(localized: "Reminder")
        case "expense": return String(localized: "Finances")
        case "expense_archive": return String(localized: "Finances archive")
        default: return entry.entityType.capitalized
        }
    }

    private var actionVerb: String {
        switch entry.action {
        case "created": return String(localized: "created")
        case "updated": return String(localized: "edited")
        case "deleted": return String(localized: "deleted")
        default: return entry.action
        }
    }

    private var icon: String {
        switch entry.action {
        case "created": return "plus.circle.fill"
        case "updated": return "pencil.circle.fill"
        case "deleted": return "trash.circle.fill"
        default: return "circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.action {
        case "created": return ALIColors.houseTasksAccent
        case "updated": return ALIColors.economiaAccent
        case "deleted": return ALIColors.error
        default: return ALIColors.mutedInk
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.actorName ?? String(localized: "Someone")) \(actionVerb) \"\(entry.entityName)\"")
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                Text("\(entityLabel) · \(Self.dateTimeFormatter.string(from: entry.createdAt))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}
