import SwiftUI
import SwiftData

/// Sheet to create or edit a family calendar event: title,
/// optional note, and start and end date/time.
struct AddFamilyEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let eventToEdit: FamilyEvent?
    var defaultDay: Date? = nil
    var canEdit: Bool = true

    @State private var title = ""
    @State private var note = ""
    @State private var emoji = "🎉"
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)

    private static let emojiOptions = ["🎉", "🎂", "✈️", "🏖️", "🎄", "🏥", "⚽️", "🎓", "❤️", "📅"]

    private var isEditing: Bool { eventToEdit != nil }
    private var isValid: Bool { !title.trimmed.isEmpty && endDate >= startDate }

    var body: some View {
        trackedBody.trackScreen("calendar_event_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !canEdit {
                        ALICard(containerColor: ALIColors.surfaceVariant) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(ALIColors.mutedInk)
                                Text("You don't have permission to edit calendar events")
                                    .font(ALITypography.bodyMedium)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                        }
                    }

                    ALITextField(placeholder: "What is it?", text: $title)
                    ALITextField(placeholder: "Note (optional)", text: $note)

                    emojiCard
                    datesCard

                    if canEdit {
                        ALIPrimaryButton(
                            text: isEditing ? "Save" : "Create event",
                            enabled: isValid,
                            accent: ALIColors.familyAccent
                        ) {
                            save()
                        }
                    }
                }
                .padding(20)
                .disabled(!canEdit)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadInitialValues)
        }
        .presentationDetents([.large])
    }

    private var emojiCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Icon")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                    ForEach(Self.emojiOptions, id: \.self) { option in
                        let isSelected = emoji == option
                        Button {
                            emoji = option
                        } label: {
                            Text(option)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(isSelected ? ALIColors.familyAccent.opacity(0.3) : ALIColors.surfaceVariant)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(isSelected ? ALIColors.familyAccent : .clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var datesCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("When?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Starts")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.ink)
                    DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: startDate) { _, newValue in
                            if endDate < newValue { endDate = newValue }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ends")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.ink)
                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }

                if endDate < startDate {
                    Text("The end date can't be before the start date.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.error)
                }
            }
        }
    }

    private func loadInitialValues() {
        if let event = eventToEdit {
            title = event.title
            note = event.note ?? ""
            emoji = event.emoji
            startDate = event.startDate
            endDate = event.endDate
        } else if let day = defaultDay {
            let calendar = Calendar.current
            startDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            endDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? startDate.addingTimeInterval(3600)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmed
        guard !trimmedTitle.isEmpty, endDate >= startDate else { return }
        let trimmedNote = note.trimmed
        let wasEditing = isEditing
        Track.event(wasEditing ? "calendar_event_edited" : "calendar_event_new", [
            "emoji": emoji,
            "has_note": !trimmedNote.isEmpty,
            "multi_day": !Calendar.current.isDate(startDate, inSameDayAs: endDate),
            "duration_hours": Int(endDate.timeIntervalSince(startDate) / 3600),
            "days_ahead": Calendar.current.dateComponents([.day], from: .now, to: startDate).day ?? 0
        ])

        let event: FamilyEvent
        if let existing = eventToEdit {
            existing.title = trimmedTitle
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote
            existing.emoji = emoji
            existing.startDate = startDate
            existing.endDate = endDate
            event = existing
        } else {
            event = FamilyEvent(
                title: trimmedTitle,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                startDate: startDate,
                endDate: endDate,
                emoji: emoji,
                createdByID: familySession.memberID,
                createdByName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
            )
            modelContext.insert(event)
        }
        if let familyID = familySession.familyID {
            dataSync.pushFamilyEvent(event, familyID: familyID)
            dataSync.logActivity(
                entityType: "family_event",
                entityName: trimmedTitle,
                action: wasEditing ? "updated" : "created",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID,
                modelContext: modelContext
            )
        }
        dismiss()
    }
}
