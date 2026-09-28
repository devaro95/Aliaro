import SwiftUI
import SwiftData

/// Sheet to create or edit a house task: name, optionally a moment to do it
/// (date and time), who it's for (everyone by default, or specific people —
/// only they get its notifications) and, optionally, how often it repeats.
struct AddHouseTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    let taskToEdit: HouseTask?

    @State private var name: String = ""
    @State private var scheduleEnabled = false
    @State private var scheduledAt = AddHouseTaskSheet.defaultScheduleDate()
    @State private var forEveryone = true
    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var reminderEnabled = false
    @State private var intervalMonths = 0
    @State private var intervalDaysPart = 7

    private var isEditing: Bool { taskToEdit != nil }

    private var totalIntervalDays: Int {
        max(1, intervalMonths * 30 + intervalDaysPart)
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && (forEveryone || !selectedMemberIDs.isEmpty)
    }

    /// Tomorrow at 20:00 — a sensible default for chores.
    private static func defaultScheduleDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        trackedBody.trackScreen("house_task_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ALITextField(placeholder: "Task name", text: $name)

                    scheduleCard
                    assigneesCard
                    intervalCard

                    ALIPrimaryButton(text: isEditing ? "Save" : "Create task", enabled: canSave, accent: ALIColors.houseTasksAccent) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let task = taskToEdit {
                    name = task.name
                    reminderEnabled = task.intervalDays != nil
                    let days = task.intervalDays ?? 7
                    intervalMonths = days / 30
                    intervalDaysPart = days % 30
                    scheduleEnabled = task.scheduledAt != nil
                    if let date = task.scheduledAt { scheduledAt = date }
                    forEveryone = task.forEveryone
                    selectedMemberIDs = Set(task.memberIDs)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var scheduleCard: some View {
        ALICard {
            VStack(spacing: 14) {
                Toggle(isOn: $scheduleEnabled.animation()) {
                    Text("Schedule for a specific time")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.houseTasksAccent)

                if scheduleEnabled {
                    DatePicker("When", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .tint(ALIColors.houseTasksAccent)
                    Text("We'll notify them at that time.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var assigneesCard: some View {
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
                .tint(ALIColors.houseTasksAccent)

                if !forEveryone {
                    Text("Only the people you choose will get its notifications.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
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
                .background(isSelected ? ALIColors.houseTasksAccent.opacity(0.3) : ALIColors.surfaceVariant)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? ALIColors.houseTasksAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var intervalCard: some View {
        ALICard {
            VStack(spacing: 14) {
                Toggle(isOn: $reminderEnabled.animation()) {
                    Text("Remind every so often")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                }
                .tint(ALIColors.houseTasksAccent)

                if reminderEnabled {
                    VStack(spacing: 6) {
                        Text("Every")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 0) {
                            Picker("Months", selection: $intervalMonths) {
                                ForEach(0..<25) { m in
                                    Text(m == 1 ? String(localized: "\(m) month") : String(localized: "\(m) months")).tag(m)
                                }
                            }
                            .pickerStyle(.wheel)

                            Picker("Days", selection: $intervalDaysPart) {
                                ForEach(0..<30) { d in
                                    Text(d == 1 ? String(localized: "\(d) day") : String(localized: "\(d) days")).tag(d)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                        .frame(height: 110)
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmed
        guard canSave else { return }
        let task: HouseTask
        let wasEditing = isEditing
        // Keep only people still in the group.
        let assignees = forEveryone ? [] : members.map(\.id).filter { selectedMemberIDs.contains($0) }
        let schedule: Date? = scheduleEnabled ? scheduledAt : nil
        Track.event(wasEditing ? "house_task_edited" : "house_task_new", [
            "task_name": trimmedName,
            "has_interval": reminderEnabled,
            "interval_days": reminderEnabled ? totalIntervalDays : nil,
            "scheduled": scheduleEnabled,
            "assignees": forEveryone ? 0 : assignees.count
        ])
        if let existing = taskToEdit {
            existing.name = trimmedName
            existing.intervalDays = reminderEnabled ? totalIntervalDays : nil
            existing.scheduledAt = schedule
            existing.forEveryone = forEveryone
            existing.memberIDs = assignees
            task = existing
        } else {
            task = HouseTask(
                name: trimmedName,
                intervalDays: reminderEnabled ? totalIntervalDays : nil,
                scheduledAt: schedule,
                forEveryone: forEveryone,
                memberIDs: assignees,
                createdByID: familySession.memberID,
                createdByName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
            )
            modelContext.insert(task)
        }
        if let familyID = familySession.familyID {
            dataSync.pushHouseTask(task, familyID: familyID)
            dataSync.logActivity(
                entityType: "house_task",
                entityName: trimmedName,
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
