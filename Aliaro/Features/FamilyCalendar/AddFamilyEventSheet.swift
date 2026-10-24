import SwiftUI
import SwiftData

/// Sheet to create or edit a family calendar event: title,
/// optional note, who it's for (everyone or specific people), and
/// start and end date/time — or just days, for an all-day event.
struct AddFamilyEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    let eventToEdit: FamilyEvent?
    var defaultDay: Date? = nil
    var canEdit: Bool = true

    @State private var title = ""
    @State private var note = ""
    @State private var emoji = ALIIcon.party
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var forEveryone = true
    @State private var isAllDay = false
    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var repeats = false
    @State private var repeatEvery = 1
    @State private var repeatUnit: FamilyEventRepeatUnit = .week
    @State private var color: String?
    @State private var hasUntil = false
    @State private var repeatUntil = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now

    private static let emojiOptions = [
        ALIIcon.party, ALIIcon.cake, ALIIcon.plane, ALIIcon.beach, ALIIcon.xmas,
        ALIIcon.health, ALIIcon.sport, ALIIcon.graduation, ALIIcon.heart, ALIIcon.calendar,
    ]

    private var isEditing: Bool { eventToEdit != nil }
    private var isValid: Bool { !title.trimmed.isEmpty && endDate >= minEndDate && (forEveryone || !selectedMemberIDs.isEmpty) }

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

                    attendeesCard
                    emojiCard
                    ALIColorPickerCard(selection: $color, enabled: canEdit)
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

    private var attendeesCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Who is it for?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                Toggle(isOn: $forEveryone.animation()) {
                    Text("Everyone")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.familyAccent)

                if !forEveryone {
                    if members.isEmpty {
                        Text("There's no one in the family group yet.")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.mutedInk)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                            ForEach(members) { member in
                                memberChip(member)
                            }
                        }
                    }
                }
            }
        }
    }

    private func memberChip(_ member: FamilyMember) -> some View {
        let isSelected = selectedMemberIDs.contains(member.id)
        return Button {
            if isSelected {
                selectedMemberIDs.remove(member.id)
            } else {
                selectedMemberIDs.insert(member.id)
            }
        } label: {
            Text(member.name)
                .lineLimit(1)
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(isSelected ? ALIColors.familyAccent.opacity(0.3) : ALIColors.surfaceVariant)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? ALIColors.familyAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
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
                            ALIIconView(icon: option, size: 20)
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

                Toggle(isOn: $isAllDay.animation()) {
                    Text("All day")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.familyAccent)

                Toggle(isOn: Binding(get: { repeats }, set: { value in
                    withAnimation { repeats = value }
                    if value { keepEndOnStartDay() }
                })) {
                    Text("Repeat")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.familyAccent)

                if repeats {
                    HStack(spacing: 10) {
                        Text("Every")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                        Stepper(value: $repeatEvery, in: 1...99) {
                            Text("\(repeatEvery)")
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(ALIColors.ink)
                                .monospacedDigit()
                        }
                        .fixedSize()
                        Picker("", selection: $repeatUnit) {
                            ForEach(FamilyEventRepeatUnit.allCases) { unit in
                                Text(unit.pickerLabel).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(ALIColors.ink)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    Toggle(isOn: $hasUntil.animation()) {
                        Text("Until a date")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                    }
                    .tint(ALIColors.familyAccent)
                    if hasUntil {
                        DatePicker("", selection: $repeatUntil, in: Calendar.current.startOfDay(for: startDate)..., displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                    Text(repeatSummary)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                Divider().overlay(ALIColors.outline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Starts")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.ink)
                    DatePicker("", selection: $startDate, displayedComponents: pickerComponents)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: startDate) { _, newValue in
                            if repeats { keepEndOnStartDay() }
                            if endDate < newValue { endDate = newValue }
                            if repeatUntil < newValue { repeatUntil = newValue }
                        }
                }

                // Repetitions last a single day: only the end time is chosen
                // (nothing for all-day ones); the series end goes below.
                if !(repeats && isAllDay) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ends")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                        DatePicker("", selection: $endDate, in: minEndDate..., displayedComponents: repeats ? [.hourAndMinute] : pickerComponents)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                }

                if !isAllDay && endDate < startDate {
                    Text("The end date can't be before the start date.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.error)
                }
            }
        }
    }

    /// "Every 5 days · until 24 Nov" / "Every week".
    private var repeatSummary: String {
        let every = repeatUnit.everyLabel(repeatEvery)
        guard hasUntil else { return every }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(every) · " + String(localized: "until \(f.string(from: repeatUntil))")
    }

    /// Moves the end to the start's day, keeping its time (a repetition
    /// lasts a single day); at least an hour after the start.
    private func keepEndOnStartDay() {
        let calendar = Calendar.current
        let t = calendar.dateComponents([.hour, .minute], from: endDate)
        let sameDay = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: startDate) ?? endDate
        endDate = sameDay > startDate ? sameDay : startDate.addingTimeInterval(3600)
    }

    private var pickerComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// All-day: the end can be any time on the start day (only the day counts).
    private var minEndDate: Date {
        isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
    }

    private func loadInitialValues() {
        if let event = eventToEdit {
            title = event.title
            note = event.note ?? ""
            emoji = ALIIcon.token(for: event.emoji, fallback: ALIIcon.calendar)
            startDate = event.startDate
            endDate = event.endDate
            forEveryone = event.forEveryone
            selectedMemberIDs = Set(event.memberIDs)
            isAllDay = event.isAllDay
            repeats = event.isRepeating
            repeatEvery = max(event.repeatInterval, 1)
            repeatUnit = event.repeatUnitValue
            color = event.color
            hasUntil = event.repeatUntil != nil
            if let until = event.repeatUntil { repeatUntil = until }
        } else if let day = defaultDay {
            let calendar = Calendar.current
            startDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            endDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? startDate.addingTimeInterval(3600)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmed
        guard isValid else { return }
        let trimmedNote = note.trimmed
        let memberIDs = forEveryone ? [] : Array(selectedMemberIDs)
        let wasEditing = isEditing
        // All-day: first day 00:00 → last day 23:59:59 (local time).
        let calendar = Calendar.current
        let finalStart = isAllDay ? calendar.startOfDay(for: startDate) : startDate
        var finalEnd = isAllDay
            ? calendar.startOfDay(for: max(endDate, startDate)).addingTimeInterval(86_399)
            : endDate
        if repeats {
            // A repetition lasts a single day: same day as the start.
            if isAllDay {
                finalEnd = calendar.startOfDay(for: startDate).addingTimeInterval(86_399)
            } else {
                let t = calendar.dateComponents([.hour, .minute], from: endDate)
                let sameDay = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: finalStart) ?? finalStart
                finalEnd = sameDay > finalStart ? sameDay : finalStart.addingTimeInterval(3600)
            }
        }
        let finalUntil: Date? = repeats && hasUntil ? calendar.startOfDay(for: max(repeatUntil, finalStart)) : nil
        Track.event(wasEditing ? "calendar_event_edited" : "calendar_event_new", [
            "emoji": emoji,
            "has_note": !trimmedNote.isEmpty,
            "for_everyone": forEveryone,
            "attendees": memberIDs.count,
            "all_day": isAllDay,
            "repeat": repeats ? "\(repeatEvery)_\(repeatUnit.rawValue)" : "none",
            "multi_day": !Calendar.current.isDate(startDate, inSameDayAs: endDate),
            "duration_hours": Int(endDate.timeIntervalSince(startDate) / 3600),
            "days_ahead": Calendar.current.dateComponents([.day], from: .now, to: startDate).day ?? 0
        ])

        let event: FamilyEvent
        if let existing = eventToEdit {
            existing.title = trimmedTitle
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote
            existing.emoji = emoji
            existing.startDate = finalStart
            existing.endDate = finalEnd
            existing.forEveryone = forEveryone
            existing.memberIDs = memberIDs
            existing.isAllDay = isAllDay
            existing.repeatInterval = repeats ? repeatEvery : 0
            existing.repeatUnit = repeatUnit.rawValue
            existing.color = color
            existing.repeatUntil = finalUntil
            event = existing
        } else {
            event = FamilyEvent(
                title: trimmedTitle,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                startDate: finalStart,
                endDate: finalEnd,
                emoji: emoji,
                createdByID: familySession.memberID,
                createdByName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                forEveryone: forEveryone,
                memberIDs: memberIDs,
                isAllDay: isAllDay,
                repeatInterval: repeats ? repeatEvery : 0,
                repeatUnit: repeatUnit.rawValue,
                color: color,
                repeatUntil: finalUntil
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
