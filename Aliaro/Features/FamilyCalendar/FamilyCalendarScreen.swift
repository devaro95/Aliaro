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
    @Query(sort: [SortDescriptor(\EventCategory.position), SortDescriptor(\EventCategory.createdAt)])
    private var categories: [EventCategory]
    /// Month shown in the month view (for the legend).
    @State private var displayedMonth = Calendar.current.startOfDay(for: .now)
    /// Legend chip tapped: only that category's events (category id, or "none").
    @State private var legendFilter: String?
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)
    @State private var showAddSheet = false
    @State private var selectedEvent: FamilyEvent?
    /// Event tapped in the "by person" view: its detail first (then edit/delete).
    @State private var detailEvent: FamilyEvent?
    /// Edit or delete chosen from the detail, applied once it has closed.
    @State private var afterDetail: (() -> Void)?
    /// The tapped occurrence (for repeating events, a display copy with its own dates).
    @State private var eventPendingDelete: FamilyEvent?
    @State private var viewMode: ViewMode = .month
    @State private var showPaywall = false
    @State private var showWhatsNew = false

    /// The "by person" view needs a subscription if `familyCalendarPeople`
    /// is currently premium — it still opens, as a preview with sample data.
    private var isPeopleViewLocked: Bool { premium.isLocked(.familyCalendarPeople) }
    private var isPeoplePreview: Bool { viewMode == .people && isPeopleViewLocked }

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canAdd: Bool { currentMember?.can(.calendarAdd) ?? true }
    private var canEdit: Bool { currentMember?.can(.calendarEdit) ?? true }
    private var canDelete: Bool { currentMember?.can(.calendarDelete) ?? true }

    private var calendar: Calendar { Calendar.current }

    /// Events (and repetitions) that touch that day.
    private func events(on day: Date) -> [FamilyEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return shownEvents.expanded(in: DateInterval(start: start, end: end.addingTimeInterval(-1)))
    }

    // MARK: Legend

    /// Legend key of an event: its (existing) category id, or "none".
    private func legendKey(_ event: FamilyEvent) -> String {
        guard let familyID = familySession.familyID,
              let id = event.resolvedCategoryID(familyID: familyID),
              categories.contains(where: { $0.id == id }) else { return "none" }
        return id.uuidString
    }

    /// Events after the legend filter.
    private var shownEvents: [FamilyEvent] {
        guard let legendFilter else { return events }
        return events.filter { legendKey($0) == legendFilter }
    }

    struct LegendItem: Identifiable {
        let key: String
        let name: String
        let color: Color
        var id: String { key }
    }

    /// Categories with events in the month on screen (in category order), plus "No category" if any.
    private var monthLegend: [LegendItem] {
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let monthEvents = events.expanded(in: month)
        var keys = Set<String>()
        for event in monthEvents { keys.insert(legendKey(event)) }
        var items: [LegendItem] = []
        for category in categories where keys.contains(category.id.uuidString) {
            items.append(LegendItem(key: category.id.uuidString, name: category.displayName, color: category.swiftUIColor))
        }
        if keys.contains("none") {
            items.append(LegendItem(key: "none", name: String(localized: "No category"), color: EventCategory.noneColor))
        }
        return items
    }

    /// Chips under the month with the categories used in it; tap one to see only its events.
    private var legendStrip: some View {
        let items = monthLegend
        let filterVisible = legendFilter == nil || items.contains(where: { $0.key == legendFilter })
        return Group {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            let isOn = legendFilter == item.key
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { legendFilter = isOn ? nil : item.key }
                                Track.event("calendar_legend_filter", ["on": !isOn])
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(item.color).frame(width: 9, height: 9)
                                    Text(item.name)
                                        .font(ALITypography.labelLarge.weight(isOn ? .semibold : .regular))
                                        .foregroundStyle(isOn ? ALIColors.onAccent : ALIColors.ink)
                                    if isOn {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(ALIColors.onAccent)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(isOn ? ALIItemColors.soft(item.color, 0.6) : ALIColors.surface, in: Capsule())
                                .overlay(Capsule().stroke(isOn ? item.color : ALIColors.outline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
                .opacity(filterVisible ? 1 : 0.6)
            }
        }
    }

    /// Repetitions are display copies: map them back to the stored event.
    private func original(_ event: FamilyEvent) -> FamilyEvent {
        events.first { $0.id == event.id } ?? event
    }

    var body: some View {
        trackedBody.trackScreen("calendar")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Calendar", accent: ALIColors.familyAccent) {
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
                    FamilyCalendarMonthView(events: shownEvents, selectedDay: $selectedDay, displayedMonth: $displayedMonth)
                    legendStrip

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
                            Track.event("calendar_event_detail_open", ["source": "people_view"])
                            detailEvent = event
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
        .sheet(item: $detailEvent, onDismiss: {
            // Open the editor / delete dialog only once the detail is gone.
            afterDetail?()
            afterDetail = nil
        }) { event in
            FamilyEventDetailSheet(
                event: event, canEdit: canEdit, canDelete: canDelete,
                onEdit: {
                    afterDetail = { selectedEvent = original(event) }
                    detailEvent = nil
                },
                onDelete: {
                    afterDetail = { eventPendingDelete = event }
                    detailEvent = nil
                }
            )
        }
        .sheet(isPresented: $showWhatsNew) {
            ALIWhatsNewSheet(
                title: "New in the Family calendar",
                accent: ALIColors.familyAccent,
                items: [
                    ALIWhatsNewItem(systemImage: "repeat", title: "Repeating events", text: "Repeat any event every few days, weeks, months or years."),
                    ALIWhatsNewItem(systemImage: "paintpalette.fill", title: "Colors", text: "Pick from 30 colors so each event stands out on the calendar.")
                ],
                tip: "Tip: open your existing events and edit them to add a color or a repetition."
            )
        }
        .onAppear {
            if ALIShowOnce.consume("whats_new_calendar_repeat_colors_v1") {
                Track.event("whats_new_shown", ["screen": "calendar"])
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(
                get: { eventPendingDelete.map { !$0.isRepeating } ?? false },
                set: { if !$0 { eventPendingDelete = nil } }
            ),
            itemName: eventPendingDelete?.title ?? ""
        ) {
            if let event = eventPendingDelete { deleteSeries(original(event)) }
            eventPendingDelete = nil
        }
        // Repeating events: only this one, or the whole series.
        .confirmationDialog(
            eventPendingDelete?.title ?? "",
            isPresented: Binding(
                get: { eventPendingDelete?.isRepeating ?? false },
                set: { if !$0 { eventPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete only this event", role: .destructive) {
                if let event = eventPendingDelete { deleteOccurrence(event) }
                eventPendingDelete = nil
            }
            Button("Delete the whole series", role: .destructive) {
                if let event = eventPendingDelete { deleteSeries(original(event)) }
                eventPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { eventPendingDelete = nil }
        } message: {
            Text("This is a repeating event. Deleting the whole series can't be undone.")
        }
    }

    private func logEventActivity(_ title: String, action: String) {
        guard let familyID = familySession.familyID else { return }
        dataSync.logActivity(
            entityType: "family_event", entityName: title, action: action,
            actorID: familySession.memberID,
            actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
            familyID: familyID, modelContext: modelContext
        )
    }

    private func deleteSeries(_ event: FamilyEvent) {
        let eventID = event.id
        let eventTitle = event.title
        Track.event("calendar_event_deleted", ["scope": event.isRepeating ? "series" : "single"])
        modelContext.delete(event)
        dataSync.deleteFamilyEvent(id: eventID)
        logEventActivity(eventTitle, action: "deleted")
    }

    /// Hides just that repetition (stored as an excluded day on the series).
    private func deleteOccurrence(_ occurrence: FamilyEvent) {
        let event = original(occurrence)
        let key = FamilyEvent.dayKey(occurrence.startDate)
        guard !event.excludedDates.contains(key) else { return }
        Track.event("calendar_event_deleted", ["scope": "occurrence"])
        event.excludedDates.append(key)
        if let familyID = familySession.familyID {
            dataSync.pushFamilyEvent(event, familyID: familyID)
        }
        logEventActivity(event.title, action: "updated")
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
                                selectedEvent = original(event)
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
        // Next occurrence of each event (repeating ones show only the next one)
        // that starts within the next 7 days (or is happening now).
        let limit = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)) ?? .now
        let upcoming = shownEvents
            .compactMap { event in event.nextOccurrence().map { event.occurrenceCopy(start: $0.start, end: $0.end) } }
            .filter { $0.startDate < limit }
            .sorted { $0.startDate < $1.startDate }
        return Group {
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next 7 days")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)

                    ALICard {
                        VStack(spacing: 0) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                                EventRow(event: event, attendees: event.attendeesLabel(members: members), canDelete: canDelete, onTap: {
                                    Track.event("calendar_event_open", ["source": "upcoming"])
                                    selectedEvent = original(event)
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
    @EnvironmentObject private var familySession: FamilySession
    @Query private var categories: [EventCategory]
    let event: FamilyEvent

    private var category: EventCategory? {
        guard let familyID = familySession.familyID else { return nil }
        let id = event.resolvedCategoryID(familyID: familyID)
        return categories.first { $0.id == id }
    }
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
                // The event's (category) color as a bar on the left, like a calendar.
                Capsule()
                    .fill(ALIItemColors.color(event.color, fallback: ALIColors.familyAccent))
                    .frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    if let category {
                        Text(category.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    HStack(spacing: 5) {
                        Text(event.title)
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                        if event.isRepeating { ALIRepeatIcon() }
                    }
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
