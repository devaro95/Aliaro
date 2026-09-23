import SwiftUI
import SwiftData

/// "Reminders" tab: one-off alerts for the whole family or for a
/// specific person. The server sends a push to each recipient device
/// when it's due — and at each configured advance alert.
struct RemindersScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \Reminder.fireDate) private var reminders: [Reminder]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var showAddSheet = false
    @State private var selectedReminder: Reminder?
    @State private var reminderPendingDelete: Reminder?
    @State private var showPaywall = false

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canCreate: Bool { currentMember?.can(.remindersCreate) ?? true }
    /// Beyond 3 reminders, creating another one needs a subscription if
    /// `unlimitedReminders` is currently premium.
    private var isNewReminderLocked: Bool { reminders.count >= 3 && premium.isLocked(.unlimitedReminders) }
    /// If the group loses premium, only the first 3 reminders it ever
    /// created stay usable — the rest get locked behind the paywall
    /// instead of being deleted.
    private var lockedReminderIDs: Set<UUID> {
        guard premium.isLocked(.unlimitedReminders) else { return [] }
        let extra = reminders.sorted { $0.createdAt < $1.createdAt }.dropFirst(3)
        return Set(extra.map(\.id))
    }
    private var canDelete: Bool { currentMember?.can(.remindersDelete) ?? true }

    var body: some View {
        trackedBody.trackScreen("reminders")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Reminders", accent: ALIColors.remindersAccent) {
                    if canCreate {
                        ALIFloatingButton(accent: ALIColors.remindersAccent) {
                            if isNewReminderLocked { showPaywall = Track.paywall("new_reminder") } else {
                                Track.event("reminder_add_tap", ["reminders": reminders.count])
                                showAddSheet = true
                            }
                        }
                        .scaleEffect(0.72)
                        .aliPremiumLockOverlay(isNewReminderLocked)
                    }
                }

                if reminders.isEmpty {
                    ALIEmptyState(
                        emoji: "🔔",
                        title: "No reminders",
                        subtitle: "Create the first one and we'll notify whoever needs it, whenever it's needed."
                    )
                } else {
                    ALICard {
                        VStack(spacing: 0) {
                            ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                                let isLocked = lockedReminderIDs.contains(reminder.id)
                                ReminderRow(
                                    reminder: reminder,
                                    recipientsLabel: recipientsLabel(for: reminder),
                                    canDelete: canDelete,
                                    locked: isLocked,
                                    onOpenDetail: {
                                        if isLocked { showPaywall = Track.paywall("locked_reminder_detail") } else {
                                            Track.event("reminder_open", ["is_past": reminder.fireDate < .now])
                                            selectedReminder = reminder
                                        }
                                    },
                                    onDelete: {
                                        Track.event("reminder_delete_tap")
                                        reminderPendingDelete = reminder
                                    }
                                )
                                if index < reminders.count - 1 {
                                    Divider().overlay(ALIColors.outline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet(reminderToEdit: nil)
        }
        .sheet(item: $selectedReminder) { reminder in
            AddReminderSheet(reminderToEdit: reminder)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { reminderPendingDelete != nil }, set: { if !$0 { reminderPendingDelete = nil } }),
            itemName: reminderPendingDelete?.title ?? ""
        ) {
            if let reminder = reminderPendingDelete {
                let reminderID = reminder.id
                let reminderTitle = reminder.title
                modelContext.delete(reminder)
                dataSync.deleteReminder(id: reminderID)
                if let familyID = familySession.familyID {
                    dataSync.logActivity(
                        entityType: "reminder", entityName: reminderTitle, action: "deleted",
                        actorID: familySession.memberID,
                        actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                        familyID: familyID, modelContext: modelContext
                    )
                }
            }
            reminderPendingDelete = nil
        }
    }

    private func recipientsLabel(for reminder: Reminder) -> String {
        if reminder.notifyEveryone { return "Everyone" }
        let names = members.filter { reminder.recipientIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No recipient" : names.joined(separator: ", ")
    }
}

/// Row for a reminder: title, when it's due, and who it notifies.
private struct ReminderRow: View {
    let reminder: Reminder
    let recipientsLabel: String
    var canDelete: Bool = true
    var locked: Bool = false
    let onOpenDetail: () -> Void
    let onDelete: () -> Void

    private var dateLabel: String {
        if reminder.fireDate < .now { return String(localized: "Already notified") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: reminder.fireDate, relativeTo: .now)
    }

    var body: some View {
        Button(action: onOpenDetail) {
            HStack(spacing: 12) {
                if locked {
                    ALIPremiumLockBadge()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    HStack(spacing: 6) {
                        Text(dateLabel)
                        Text("·")
                        Text(recipientsLabel)
                        if let name = reminder.createdByName, !name.isEmpty {
                            Text("·")
                            Text(name)
                        }
                    }
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
                }
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }
}
