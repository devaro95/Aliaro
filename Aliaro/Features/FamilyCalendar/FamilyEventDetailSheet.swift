import SwiftUI
import SwiftData

/// Read-only detail of a calendar event (from the "by person" view): what
/// it is, when, who it's for, category, repetition, alerts and note, with
/// Edit and Delete at the bottom.
struct FamilyEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query private var categories: [EventCategory]

    /// The tapped occurrence (repetitions are copies with their own dates).
    let event: FamilyEvent
    var canEdit: Bool = true
    var canDelete: Bool = true
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var category: EventCategory? {
        guard let familyID = familySession.familyID, let id = event.resolvedCategoryID(familyID: familyID) else { return nil }
        return categories.first { $0.id == id }
    }

    private var color: Color { ALIItemColors.color(event.color, fallback: EventCategory.noneColor) }

    private var whenLabel: String {
        let calendar = Calendar.current
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let sameDay = calendar.isDate(event.startDate, inSameDayAs: event.endDate)
        if event.isAllDay {
            return sameDay
                ? day.string(from: event.startDate).capitalized + " · " + String(localized: "All day")
                : day.string(from: event.startDate).capitalized + " – " + day.string(from: event.endDate)
        }
        if sameDay {
            return day.string(from: event.startDate).capitalized + " · " + time.string(from: event.startDate) + " – " + time.string(from: event.endDate)
        }
        return day.string(from: event.startDate).capitalized + " " + time.string(from: event.startDate)
            + " – " + day.string(from: event.endDate) + " " + time.string(from: event.endDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Capsule().fill(color).frame(width: 5, height: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            if let category {
                                Text(category.displayName.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                            Text(event.title)
                                .font(ALITypography.headlineMedium)
                                .foregroundStyle(ALIColors.ink)
                        }
                    }

                    ALICard {
                        VStack(alignment: .leading, spacing: 14) {
                            row("calendar", whenLabel)
                            if event.isRepeating {
                                row("repeat", event.repeatUnitValue.everyLabel(event.repeatInterval))
                            }
                            row("person.2.fill", event.attendeesLabel(members: members))
                            row("bell.fill", ALIAlerts.summary(event.effectiveAlertOffsets, isAllDay: event.isAllDay))
                            if let name = event.createdByName, !name.isEmpty {
                                row("person.crop.circle", String(localized: "Added by \(name)"))
                            }
                        }
                    }

                    if let note = event.note, !note.isEmpty {
                        ALICard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Note")
                                    .font(ALITypography.labelLarge)
                                    .foregroundStyle(ALIColors.mutedInk)
                                Text(note)
                                    .font(ALITypography.bodyMedium)
                                    .foregroundStyle(ALIColors.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if canEdit {
                        ALIPrimaryButton(text: "Edit", accent: ALIColors.familyAccent) {
                            Track.event("calendar_event_detail_edit")
                            onEdit()
                        }
                    }
                    if canDelete {
                        Button(role: .destructive) {
                            Track.event("calendar_event_detail_delete")
                            onDelete()
                        } label: {
                            Text("Delete")
                                .font(ALITypography.bodyLarge.weight(.semibold))
                                .foregroundStyle(ALIColors.error)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .trackScreen("calendar_event_detail")
    }

    private func row(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ALIColors.mutedInk)
                .frame(width: 20)
            Text(text)
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
