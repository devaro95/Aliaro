import SwiftUI
import SwiftData

/// "History" of the family group: every create/edit/delete on a
/// shared item, and who did it — so no change goes unnoticed, even if
/// it was made by a kid on someone else's device.
struct HistorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ActivityLogEntry.createdAt, order: .reverse) private var entries: [ActivityLogEntry]

    var body: some View {
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
            }
            .background(ALIColors.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
