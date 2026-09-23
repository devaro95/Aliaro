import SwiftUI
import SwiftData

/// Sheet to create or edit a house task: name and, optionally, how
/// often it should be repeated.
struct AddHouseTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let taskToEdit: HouseTask?

    @State private var name: String = ""
    @State private var reminderEnabled = false
    @State private var intervalMonths = 0
    @State private var intervalDaysPart = 7

    private var isEditing: Bool { taskToEdit != nil }

    private var totalIntervalDays: Int {
        max(1, intervalMonths * 30 + intervalDaysPart)
    }

    var body: some View {
        trackedBody.trackScreen("house_task_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ALITextField(placeholder: "Task name", text: $name)

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

                Spacer()

                ALIPrimaryButton(text: isEditing ? "Save" : "Create task", enabled: !name.trimmed.isEmpty, accent: ALIColors.houseTasksAccent) {
                    save()
                }
            }
            .padding(20)
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
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }
        let task: HouseTask
        let wasEditing = isEditing
        Track.event(wasEditing ? "house_task_edited" : "house_task_new", [
            "task_name": trimmedName,
            "has_interval": reminderEnabled,
            "interval_days": reminderEnabled ? totalIntervalDays : nil
        ])
        if let existing = taskToEdit {
            existing.name = trimmedName
            existing.intervalDays = reminderEnabled ? totalIntervalDays : nil
            task = existing
        } else {
            task = HouseTask(
                name: trimmedName,
                intervalDays: reminderEnabled ? totalIntervalDays : nil,
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
