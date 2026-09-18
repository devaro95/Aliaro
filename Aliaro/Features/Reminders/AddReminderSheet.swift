import SwiftUI
import SwiftData

/// Sheet to create or edit a reminder: what to remember, who to notify
/// (everyone or specific people), when — an exact date and time, or
/// within a certain time from now — and up to 2 additional advance
/// alerts. The actual delivery (push to all of the recipients' devices)
/// is done by the server; this sheet only saves the reminder's data.
struct AddReminderSheet: View {
    private enum ScheduleMode: String, CaseIterable, Identifiable {
        case exact = "Date and time"
        case relative = "Within..."
        var id: String { rawValue }
    }

    private enum RelativeUnit: String, CaseIterable, Identifiable {
        case minutes = "minutes", hours = "hours", days = "days"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .minutes: return 60
            case .hours: return 3600
            case .days: return 86400
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    let reminderToEdit: Reminder?

    @State private var title = ""
    @State private var note = ""
    @State private var notifyEveryone = true
    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var scheduleMode: ScheduleMode = .exact
    @State private var exactDate = Date().addingTimeInterval(3600)
    @State private var relativeAmount = 30
    @State private var relativeUnit: RelativeUnit = .minutes
    @State private var advanceNotices: [AdvanceNotice] = []

    private struct AdvanceNotice: Identifiable {
        let id = UUID()
        var amount: Int
        var unit: RelativeUnit
    }

    private static let maxAdvanceNotices = 2

    private var isEditing: Bool { reminderToEdit != nil }

    private var relativeAmountText: Binding<String> {
        Binding(
            get: { String(relativeAmount) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                if digits.isEmpty {
                    relativeAmount = 1
                } else if let parsed = Int(digits) {
                    relativeAmount = min(max(parsed, 1), 999)
                }
            }
        )
    }

    private var advanceNoticeSeconds: [Int] {
        advanceNotices.map { Int(TimeInterval($0.amount) * $0.unit.seconds) }
    }

    private var resolvedFireDate: Date {
        switch scheduleMode {
        case .exact: return exactDate
        case .relative: return Date().addingTimeInterval(TimeInterval(relativeAmount) * relativeUnit.seconds)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ALITextField(placeholder: "What needs remembering?", text: $title)
                    ALITextField(placeholder: "Note (optional)", text: $note)

                    recipientsCard
                    scheduleCard
                    advanceNoticeCard

                    ALIPrimaryButton(
                        text: isEditing ? "Save" : "Create reminder",
                        enabled: !title.trimmed.isEmpty,
                        accent: ALIColors.remindersAccent
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit reminder" : "New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadIfEditing)
        }
        .presentationDetents([.large])
    }

    private var recipientsCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Who to notify?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                Toggle(isOn: $notifyEveryone.animation()) {
                    Text("Everyone")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.remindersAccent)

                if !notifyEveryone {
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
            HStack(spacing: 6) {
                Text(member.name).lineLimit(1)
            }
            .font(ALITypography.bodyMedium)
            .foregroundStyle(ALIColors.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(isSelected ? ALIColors.remindersAccent.opacity(0.3) : ALIColors.surfaceVariant)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? ALIColors.remindersAccent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var scheduleCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("When?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                Picker("", selection: $scheduleMode) {
                    ForEach(ScheduleMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch scheduleMode {
                case .exact:
                    DatePicker("", selection: $exactDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                case .relative:
                    HStack(spacing: 12) {
                        Stepper(value: $relativeAmount, in: 1...999) {
                            TextField("", text: relativeAmountText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(ALITypography.titleLarge)
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 50)
                        }
                        Picker("", selection: $relativeUnit) {
                            ForEach(RelativeUnit.allCases) { unit in
                                Text(LocalizedStringKey(unit.rawValue)).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                    }
                }
            }
        }
    }

    private var advanceNoticeCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Also notify in advance (optional)")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                Text("The exact-time alert is always sent. You can add up to \(Self.maxAdvanceNotices) alerts before it.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)

                ForEach($advanceNotices) { $notice in
                    HStack(spacing: 12) {
                        TextField("", text: Binding(
                            get: { String(notice.amount) },
                            set: { newValue in
                                let digits = newValue.filter(\.isNumber)
                                notice.amount = digits.isEmpty ? 1 : min(max(Int(digits) ?? 1, 1), 999)
                            }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .frame(width: 50)

                        Picker("", selection: $notice.unit) {
                            ForEach(RelativeUnit.allCases) { unit in
                                Text(LocalizedStringKey(unit.rawValue)).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()

                        Text("before")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.mutedInk)

                        Spacer()

                        Button {
                            advanceNotices.removeAll { $0.id == notice.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if advanceNotices.count < Self.maxAdvanceNotices {
                    Button {
                        advanceNotices.append(AdvanceNotice(amount: 10, unit: .minutes))
                    } label: {
                        Text("+ Add alert")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.remindersAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Breaks seconds down into the largest unit that divides evenly (e.g.
    /// 7200 -> 2 hours instead of 120 minutes), to show it when editing.
    private static func amountAndUnit(fromSeconds seconds: Int) -> (Int, RelativeUnit) {
        if seconds > 0, seconds % 86400 == 0 { return (seconds / 86400, .days) }
        if seconds > 0, seconds % 3600 == 0 { return (seconds / 3600, .hours) }
        return (max(seconds / 60, 1), .minutes)
    }

    private func loadIfEditing() {
        guard let reminder = reminderToEdit else { return }
        title = reminder.title
        note = reminder.note ?? ""
        notifyEveryone = reminder.notifyEveryone
        selectedMemberIDs = Set(reminder.recipientIDs)
        scheduleMode = .exact
        exactDate = reminder.fireDate
        advanceNotices = reminder.advanceNoticeSeconds.map { seconds in
            let (amount, unit) = Self.amountAndUnit(fromSeconds: seconds)
            return AdvanceNotice(amount: amount, unit: unit)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmed
        guard !trimmedTitle.isEmpty else { return }
        let trimmedNote = note.trimmed
        let fireDate = resolvedFireDate
        let recipientIDs = notifyEveryone ? [] : Array(selectedMemberIDs)

        let noticeSeconds = advanceNoticeSeconds
        let wasEditing = reminderToEdit != nil

        let reminder: Reminder
        if let existing = reminderToEdit {
            existing.title = trimmedTitle
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote
            existing.fireDate = fireDate
            existing.notifyEveryone = notifyEveryone
            existing.recipientIDs = recipientIDs
            existing.advanceNoticeSeconds = noticeSeconds
            reminder = existing
        } else {
            reminder = Reminder(
                title: trimmedTitle,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                fireDate: fireDate,
                notifyEveryone: notifyEveryone,
                recipientIDs: recipientIDs,
                advanceNoticeSeconds: noticeSeconds,
                createdByID: familySession.memberID,
                createdByName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
            )
            modelContext.insert(reminder)
        }

        // Delivery (push at the exact time and at each advance alert, to
        // all of the recipients' devices) is handled by the server; here
        // we only need to save and sync the reminder.
        if let familyID = familySession.familyID {
            dataSync.pushReminder(reminder, familyID: familyID)
            dataSync.logActivity(
                entityType: "reminder",
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
