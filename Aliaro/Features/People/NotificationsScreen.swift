import SwiftUI
import UIKit
import UserNotifications
import Supabase

/// Push notifications this person can turn off one by one (People →
/// Notifications). Stored server-side in `family_members.muted_notifications`
/// — every push function skips members who muted that kind — so it
/// applies on any device this account uses. Written through the
/// `update-notification-prefs` edge function (identity from the JWT).
enum NotificationKind: String, CaseIterable, Identifiable {
    // rawValue = key in Supabase; keep in sync with update-notification-prefs.
    case reminders
    case eventUpcoming = "event_upcoming"
    case taskDue = "task_due"
    case eventCreated = "event_created"
    case noteCreated = "note_created"
    case taskCreated = "task_created"
    case reminderAssigned = "reminder_assigned"
    case memberJoined = "member_joined"
    case memberLeft = "member_left"

    var id: String { rawValue }

    enum Section: CaseIterable {
        case scheduled, activity, group

        var title: LocalizedStringKey {
            switch self {
            case .scheduled: return "Alerts"
            case .activity: return "Family activity"
            case .group: return "Family group"
            }
        }

        var kinds: [NotificationKind] {
            NotificationKind.allCases.filter { $0.section == self }
        }
    }

    var section: Section {
        switch self {
        case .reminders, .eventUpcoming, .taskDue: return .scheduled
        case .eventCreated, .noteCreated, .taskCreated, .reminderAssigned: return .activity
        case .memberJoined, .memberLeft: return .group
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .reminders: return "Reminders"
        case .eventUpcoming: return "Upcoming events"
        case .taskDue: return "Household tasks due"
        case .eventCreated: return "New events"
        case .noteCreated: return "New board notes"
        case .taskCreated: return "New household tasks"
        case .reminderAssigned: return "Reminders added for you"
        case .memberJoined: return "Someone joins the group"
        case .memberLeft: return "Someone leaves the group"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .reminders: return "When a reminder you're in goes off"
        case .eventUpcoming: return "1 hour before, or at 9:00 for all-day events"
        case .taskDue: return "A daily summary of the tasks that are due"
        case .eventCreated: return "When someone adds an event for you"
        case .noteCreated: return "When someone leaves a note for you"
        case .taskCreated: return "When someone adds a new task"
        case .reminderAssigned: return "When someone adds a reminder for you"
        case .memberJoined: return "When a new member joins"
        case .memberLeft: return "When a member leaves or is removed"
        }
    }

    var icon: String {
        switch self {
        case .reminders: return "bell"
        case .eventUpcoming: return "calendar.badge.clock"
        case .taskDue: return "checklist"
        case .eventCreated: return "calendar.badge.plus"
        case .noteCreated: return "note.text"
        case .taskCreated: return "plus.circle"
        case .reminderAssigned: return "bell.badge"
        case .memberJoined: return "person.badge.plus"
        case .memberLeft: return "person.badge.minus"
        }
    }
}

struct NotificationsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var familySession: FamilySession

    @State private var muted: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var systemStatus: UNAuthorizationStatus = .authorized

    private var systemBlocked: Bool { systemStatus == .denied }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if systemBlocked {
                        systemOffCard
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(NotificationKind.Section.allCases, id: \.self) { section in
                            sectionCard(section)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.error)
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(ALIColors.ink)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: refresh the system permission state.
            if phase == .active { refreshSystemStatus() }
        }
        .trackScreen("notifications_settings")
    }

    private var systemOffCard: some View {
        ALICard(containerColor: ALIColors.surfaceVariant) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(ALIColors.error)
                    Text("Notifications are turned off for Aliaro in iOS Settings, so none of these will arrive.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.ink)
                }
                Button("Open Settings") {
                    Track.event("notifications_open_system_settings")
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.peopleAccent)
            }
        }
    }

    private func sectionCard(_ section: NotificationKind.Section) -> some View {
        ALICard {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.bottom, 6)
                ForEach(Array(section.kinds.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(ALIColors.outline) }
                    toggleRow(kind)
                }
            }
        }
        .opacity(systemBlocked ? 0.5 : 1)
    }

    private func toggleRow(_ kind: NotificationKind) -> some View {
        Toggle(isOn: binding(for: kind)) {
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALIColors.peopleAccent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text(kind.subtitle)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
        }
        .tint(ALIColors.peopleAccent)
        .padding(.vertical, 8)
    }

    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { !muted.contains(kind.rawValue) },
            set: { enabled in
                let previous = muted
                if enabled { muted.remove(kind.rawValue) } else { muted.insert(kind.rawValue) }
                Track.event("notification_pref_changed", ["kind": kind.rawValue, "enabled": enabled])
                save(revertTo: previous)
            }
        )
    }

    // MARK: - Data

    private struct Row: Decodable { let muted_notifications: [String]? }

    private func load() async {
        refreshSystemStatus()
        defer { isLoading = false }
        guard let memberID = familySession.memberID else { return }
        do {
            let row: Row = try await supabase
                .from("family_members")
                .select("muted_notifications")
                .eq("id", value: memberID)
                .single()
                .execute()
                .value
            muted = Set(row.muted_notifications ?? [])
        } catch {
            errorMessage = String(localized: "Couldn't load your notification settings.")
        }
    }

    /// Optimistic save: the toggle flips right away and reverts on error.
    private func save(revertTo previous: Set<String>) {
        guard let memberID = familySession.memberID else { return }
        let snapshot = muted
        errorMessage = nil
        Task {
            struct Body: Encodable { let memberId: UUID; let muted: [String] }
            struct Response: Decodable { let ok: Bool }
            do {
                let _: Response = try await invokeEdgeFunction(
                    "update-notification-prefs",
                    options: FunctionInvokeOptions(body: Body(memberId: memberID, muted: snapshot.sorted()))
                )
            } catch {
                if muted == snapshot { muted = previous }
                errorMessage = String(localized: "Couldn't save the change. Try again.")
            }
        }
    }

    private func refreshSystemStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { systemStatus = status }
        }
    }
}
