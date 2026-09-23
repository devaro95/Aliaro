import SwiftUI
import SwiftData

/// Task detail: history of times it's been done, with the option to
/// add a record with a specific date, edit the task, or delete it.
struct HouseTaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let task: HouseTask
    let logs: [HouseTaskLog]

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var showEditSheet = false
    @State private var showDeleteTaskConfirm = false
    @State private var logPendingDelete: HouseTaskLog?
    @State private var showAddLog = false
    @State private var newLogDate = Date()
    @State private var newLogNote = ""

    private var sortedLogs: [HouseTaskLog] { logs.sorted { $0.completedAt > $1.completedAt } }
    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canEditTask: Bool { currentMember?.can(.tasksEdit) ?? true }
    private var canDeleteTask: Bool { currentMember?.can(.tasksDelete) ?? true }

    private var currentActorID: UUID? { familySession.memberID }
    private var currentActorName: String? {
        familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
    }

    var body: some View {
        trackedBody.trackScreen("house_task_detail")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ALIPrimaryButton(text: "Mark as done today", accent: ALIColors.houseTasksAccent) {
                    Track.event("house_task_done_today", ["task_name": task.name, "source": "detail"])
                    let log = HouseTaskLog(
                        taskID: task.id, taskName: task.name,
                        createdByID: familySession.memberID,
                        createdByName: currentActorName
                    )
                    modelContext.insert(log)
                    if let familyID = familySession.familyID {
                        dataSync.pushHouseTaskLog(log, familyID: familyID)
                        dataSync.logActivity(
                            entityType: "house_task_log", entityName: task.name, action: "created",
                            actorID: currentActorID, actorName: currentActorName,
                            familyID: familyID, modelContext: modelContext
                        )
                    }
                }
                ALITextButton(text: "Add with another date…", color: ALIColors.houseTasksAccent) {
                    newLogDate = .now
                    newLogNote = ""
                    Track.event("house_task_add_past_tap", ["task_name": task.name])
                    showAddLog = true
                }

                if sortedLogs.isEmpty {
                    ALIEmptyState(emoji: "🗓️", title: "No history", subtitle: "There's no record of this task yet.")
                    Spacer()
                } else {
                    ScrollView {
                        ALICard {
                            VStack(spacing: 0) {
                                ForEach(Array(sortedLogs.enumerated()), id: \.element.id) { index, log in
                                    LogRow(log: log, onDelete: { logPendingDelete = log })
                                    if index < sortedLogs.count - 1 {
                                        Divider().overlay(ALIColors.outline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle(task.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
                if canEditTask || canDeleteTask {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            if canEditTask {
                                Button("Edit task", systemImage: "pencil") {
                                    Track.event("house_task_edit_tap", ["task_name": task.name])
                                    showEditSheet = true
                                }
                            }
                            if canDeleteTask {
                                Button("Delete task", systemImage: "trash", role: .destructive) {
                                    Track.event("house_task_delete_tap", ["task_name": task.name, "logs": logs.count])
                                    showDeleteTaskConfirm = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                AddHouseTaskSheet(taskToEdit: task)
            }
            .sheet(isPresented: $showAddLog) {
                AddLogEntrySheet(date: $newLogDate, note: $newLogNote) {
                    Track.event("house_task_done_past", [
                        "task_name": task.name,
                        "days_ago": Calendar.current.dateComponents([.day], from: newLogDate, to: .now).day ?? 0,
                        "has_note": !newLogNote.trimmed.isEmpty
                    ])
                    let log = HouseTaskLog(
                        taskID: task.id, taskName: task.name, completedAt: newLogDate,
                        note: newLogNote.trimmed.isEmpty ? nil : newLogNote.trimmed,
                        createdByID: familySession.memberID,
                        createdByName: currentActorName
                    )
                    modelContext.insert(log)
                    if let familyID = familySession.familyID {
                        dataSync.pushHouseTaskLog(log, familyID: familyID)
                        dataSync.logActivity(
                            entityType: "house_task_log", entityName: task.name, action: "created",
                            actorID: currentActorID, actorName: currentActorName,
                            familyID: familyID, modelContext: modelContext
                        )
                    }
                }
            }
            .aliDeleteConfirmDialog(
                isPresented: Binding(get: { logPendingDelete != nil }, set: { if !$0 { logPendingDelete = nil } }),
                itemName: logPendingDelete.map { Self.dateFormatter.string(from: $0.completedAt) } ?? ""
            ) {
                if let log = logPendingDelete {
                    let logID = log.id
                    Track.event("house_task_log_delete", ["task_name": task.name])
                    modelContext.delete(log)
                    dataSync.deleteHouseTaskLog(id: logID)
                    if let familyID = familySession.familyID {
                        dataSync.logActivity(
                            entityType: "house_task_log", entityName: task.name, action: "deleted",
                            actorID: currentActorID, actorName: currentActorName,
                            familyID: familyID, modelContext: modelContext
                        )
                    }
                }
            }
            .alert("Delete \"\(task.name)\"?", isPresented: $showDeleteTaskConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    for log in logs {
                        let logID = log.id
                        modelContext.delete(log)
                        dataSync.deleteHouseTaskLog(id: logID)
                    }
                    let taskID = task.id
                    let taskName = task.name
                    modelContext.delete(task)
                    dataSync.deleteHouseTask(id: taskID)
                    if let familyID = familySession.familyID {
                        dataSync.logActivity(
                            entityType: "house_task", entityName: taskName, action: "deleted",
                            actorID: currentActorID, actorName: currentActorName,
                            familyID: familyID, modelContext: modelContext
                        )
                    }
                    dismiss()
                }
            } message: {
                Text("Its entire history will also be deleted. This action can't be undone.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

/// Small sheet to log a "done" with a custom date and note.
private struct AddLogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @Binding var note: String
    let onAdd: () -> Void

    var body: some View {
        trackedBody.trackScreen("house_task_log_new")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(ALIColors.houseTasksAccent)

                    ALITextField(placeholder: "Note (optional)", text: $note)

                    ALIPrimaryButton(text: "Add record", accent: ALIColors.houseTasksAccent) {
                        onAdd()
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("New record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct LogRow: View {
    let log: HouseTaskLog
    let onDelete: () -> Void

    private var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: log.completedAt).capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatted)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                }
                if let name = log.createdByName, !name.isEmpty {
                    Text("By \(name)")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}
