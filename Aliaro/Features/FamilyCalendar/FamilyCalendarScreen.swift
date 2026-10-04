import SwiftUI
import SwiftData

/// "Family" tab: birthdays, vacations and shared events, each with its
/// own start and end date/time.
struct FamilyCalendarScreen: View {
    private enum ViewMode {
        case month, people
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \FamilyEvent.startDate) private var events: [FamilyEvent]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)
    @State private var showAddSheet = false
    @State private var selectedEvent: FamilyEvent?
    @State private var eventPendingDelete: FamilyEvent?
    @State private var viewMode: ViewMode = .month
    @State private var showPaywall = false

    /// The "by person" view needs a subscription if `familyCalendarPeople`
    /// is currently premium — it still opens, as a preview with sample data.
    private var isPeopleViewLocked: Bool { premium.isLocked(.familyCalendarPeople) }
    private var isPeoplePreview: Bool { viewMode == .people && isPeopleViewLocked }

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canAdd: Bool { currentMember?.can(.calendarAdd) ?? true }
    private var canEdit: Bool { currentMember?.can(.calendarEdit) ?? true }
    private var canDelete: Bool { currentMember?.can(.calendarDelete) ?? true }

    private var calendar: Calendar { Calendar.current }

    private func events(on day: Date) -> [FamilyEvent] {
        events.filter { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            let target = calendar.startOfDay(for: day)
            return target >= start && target <= end
        }
    }

    var body: some View {
        trackedBody.trackScreen("calendar")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Family calendar", accent: ALIColors.familyAccent) {
                    HStack(spacing: 10) {
                        viewModeToggleButton
                        if canAdd {
                            ALIFloatingButton(accent: ALIColors.familyAccent) {
                                Track.event("calendar_event_add_tap", ["events": events.count])
                                showAddSheet = true
                            }
                            .scaleEffect(0.72)
                        }
                    }
                }

                switch viewMode {
                case .month:
                    FamilyCalendarMonthView(events: events, selectedDay: $selectedDay)

                    if let selectedDay {
                        selectedDaySummary(for: selectedDay)
                    }

                    upcomingList
                case .people:
                    if isPeopleViewLocked {
                        FamilyCalendarPeopleView(
                            events: FamilyCalendarPeopleDemoData.today,
                            members: FamilyCalendarPeopleDemoData.members,
                            selectedDay: .constant(nil),
                            isMock: true,
                            onSelect: { _ in }
                        )
                        .aliPremiumPreview(true)
                    } else {
                        FamilyCalendarPeopleView(events: events, members: members, selectedDay: $selectedDay) { event in
                            selectedEvent = event
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            // Extra room while the preview banner floats over the content.
            .padding(.bottom, isPeoplePreview ? 320 : 100)
        }
        .overlay(alignment: .bottom) {
            if isPeoplePreview {
                ALIPremiumPreviewBanner(
                    message: .peopleCalendar,
                    buttonTitle: "Unlock view"
                ) { showPaywall = Track.paywall("calendar_people_banner") }
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddFamilyEventSheet(eventToEdit: nil, defaultDay: selectedDay)
        }
        .sheet(item: $selectedEvent) { event in
            AddFamilyEventSheet(eventToEdit: event, canEdit: canEdit)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { eventPendingDelete != nil }, set: { if !$0 { eventPendingDelete = nil } }),
            itemName: eventPendingDelete?.title ?? ""
        ) {
            if let event = eventPendingDelete {
                let eventID = event.id
                let eventTitle = event.title
                modelContext.delete(event)
                dataSync.deleteFamilyEvent(id: eventID)
                if let familyID = familySession.familyID {
                    dataSync.logActivity(
                        entityType: "family_event", entityName: eventTitle, action: "deleted",
                        actorID: familySession.memberID,
                        actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                        familyID: familyID, modelContext: modelContext
                    )
                }
            }
            eventPendingDelete = nil
        }
    }

    /// Toggles between the month view and the "by person" matrix. If the
    /// matrix is locked it still switches, as a premium preview.
    private var viewModeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = (viewMode == .month) ? .people : .month
            }
            Track.event("calendar_view_mode", ["mode": viewMode == .month ? "month" : "people", "locked": isPeopleViewLocked])
        } label: {
            Image(systemName: viewMode == .month ? "person.3.fill" : "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
                .aliPremiumPreviewOverlay(viewMode == .month && isPeopleViewLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewMode == .month ? "View by person" : "View as month")
    }

    private func selectedDaySummary(for day: Date) -> some View {
        let dayEvents = events(on: day)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"
            return f
        }()

        return ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text(formatter.string(from: day).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)

                if dayEvents.isEmpty {
                    Text("No events on this day.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dayEvents.enumerated()), id: \.element.id) { index, event in
                            EventRow(event: event, attendees: event.attendeesLabel(members: members), canDelete: canDelete, onTap: {
                                Track.event("calendar_event_open", ["source": "selected_day"])
                                selectedEvent = event
                            }, onDelete: {
                                Track.event("calendar_event_delete_tap", ["source": "selected_day"])
                                eventPendingDelete = event
                            })
                            if index < dayEvents.count - 1 {
                                Divider().overlay(ALIColors.outline)
                            }
                        }
                    }
                }
            }
        }
    }

    private var upcomingList: some View {
        let upcoming = events.filter { $0.endDate >= .now }.sorted { $0.startDate < $1.startDate }
        return Group {
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Upcoming events")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)

                    ALICard {
                        VStack(spacing: 0) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                                EventRow(event: event, attendees: event.attendeesLabel(members: members), canDelete: canDelete, onTap: {
                                    Track.event("calendar_event_open", ["source": "upcoming"])
                                    selectedEvent = event
                                }, onDelete: {
                                    Track.event("calendar_event_delete_tap", ["source": "upcoming"])
                                    eventPendingDelete = event
                                })
                                if index < upcoming.count - 1 {
                                    Divider().overlay(ALIColors.outline)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Row for an event: icon, title, date range and who it's for.
private struct EventRow: View {
    let event: FamilyEvent
    let attendees: String
    var canDelete: Bool = true
    let onTap: () -> Void
    let onDelete: () -> Void

    private var rangeLabel: String {
        let calendar = Calendar.current
        let sameDay = calendar.isDate(event.startDate, inSameDayAs: event.endDate)
        let formatter = DateFormatter()
        if event.isAllDay {
            formatter.dateFormat = "d MMM"
            let allDay = String(localized: "All day")
            return sameDay
                ? "\(formatter.string(from: event.startDate)) · \(allDay)"
                : "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate)) · \(allDay)"
        }
        if sameDay {
            formatter.dateFormat = "d MMM, HH:mm"
            return "\(formatter.string(from: event.startDate)) – \(timeOnly(event.endDate))"
        } else {
            formatter.dateFormat = "d MMM"
            return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
        }
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }


    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ALIIconView(icon: event.emoji, size: 22, fallback: ALIIcon.calendar)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text("\(rangeLabel) · \(attendees)")
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
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }
}
