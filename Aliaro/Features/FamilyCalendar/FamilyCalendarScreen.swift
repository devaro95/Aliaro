import SwiftUI
import SwiftData

/// "Family" tab: birthdays, vacations and shared events, each with its
/// own start and end date/time.
struct FamilyCalendarScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    @Query(sort: \FamilyEvent.startDate) private var events: [FamilyEvent]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)
    @State private var showAddSheet = false
    @State private var selectedEvent: FamilyEvent?
    @State private var eventPendingDelete: FamilyEvent?

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
                    if canAdd {
                        ALIFloatingButton(accent: ALIColors.familyAccent) {
                            Track.event("calendar_event_add_tap", ["events": events.count])
                            showAddSheet = true
                        }
                            .scaleEffect(0.72)
                    }
                }

                FamilyCalendarMonthView(events: events, selectedDay: $selectedDay)

                if let selectedDay {
                    selectedDaySummary(for: selectedDay)
                }

                upcomingList
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddFamilyEventSheet(eventToEdit: nil, defaultDay: selectedDay)
        }
        .sheet(item: $selectedEvent) { event in
            AddFamilyEventSheet(eventToEdit: event, canEdit: canEdit)
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
                            EventRow(event: event, canDelete: canDelete, onTap: {
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
                                EventRow(event: event, canDelete: canDelete, onTap: {
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

/// Row for an event: icon, title, date range and note.
private struct EventRow: View {
    let event: FamilyEvent
    var canDelete: Bool = true
    let onTap: () -> Void
    let onDelete: () -> Void

    private var rangeLabel: String {
        let calendar = Calendar.current
        let sameDay = calendar.isDate(event.startDate, inSameDayAs: event.endDate)
        let formatter = DateFormatter()
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

    private func authorLabel(_ base: String) -> String {
        guard let name = event.createdByName, !name.isEmpty else { return base }
        return "\(base) · \(name)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(event.emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text(authorLabel(rangeLabel))
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
