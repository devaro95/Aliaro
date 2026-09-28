import SwiftUI
import SwiftData

/// Sheet to pin a new note on the Board, or edit one: free text (up to
/// `BoardNote.maxLength`), who it's for (everyone by default, or specific
/// people — only they see it) and a sticky-note color.
struct AddBoardNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    let noteToEdit: BoardNote?

    @State private var text = ""
    @State private var colorIndex = 0
    @State private var forEveryone = true
    @State private var selectedMemberIDs: Set<UUID> = []
    @FocusState private var focused: Bool

    private var isEditing: Bool { noteToEdit != nil }

    private var canSave: Bool {
        !text.trimmed.isEmpty && (forEveryone || !selectedMemberIDs.isEmpty)
    }

    var body: some View {
        trackedBody.trackScreen("board_note_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField("What should everyone remember?", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(4...10)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                        .padding(16)
                        .background(BoardNote.colors[colorIndex].opacity(0.35))
                        .background(ALIColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ALIColors.outline, lineWidth: 1)
                        )
                        .onChange(of: text) { _, new in
                            if new.count > BoardNote.maxLength { text = String(new.prefix(BoardNote.maxLength)) }
                        }

                    HStack(spacing: 12) {
                        ForEach(BoardNote.colors.indices, id: \.self) { index in
                            Button {
                                colorIndex = index
                            } label: {
                                Circle()
                                    .fill(BoardNote.colors[index])
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().stroke(ALIColors.ink, lineWidth: colorIndex == index ? 2 : 0)
                                            .padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    recipientsCard

                    ALIPrimaryButton(
                        text: isEditing ? "Save" : "Pin to board",
                        enabled: canSave,
                        accent: ALIColors.boardAccent
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit note" : "New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let note = noteToEdit {
                    text = note.text
                    colorIndex = max(0, note.colorIndex) % BoardNote.colors.count
                    forEveryone = note.forEveryone
                    selectedMemberIDs = Set(note.memberIDs)
                } else {
                    focused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var recipientsCard: some View {
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
                .tint(ALIColors.boardAccent)

                if !forEveryone {
                    Text("Only the people you choose will see it on their Board and Home.")
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
                .background(isSelected ? ALIColors.boardAccent.opacity(0.3) : ALIColors.surfaceVariant)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? ALIColors.boardAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let clean = text.trimmed
        guard canSave, let familyID = familySession.familyID else { return }
        // Keep only people still in the group.
        let recipients = members.map(\.id).filter { selectedMemberIDs.contains($0) }
        let actorName = familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }

        let note: BoardNote
        if let existing = noteToEdit {
            existing.text = clean
            existing.colorIndex = colorIndex
            existing.forEveryone = forEveryone
            existing.memberIDs = forEveryone ? [] : recipients
            existing.updatedAt = .now
            note = existing
        } else {
            // New notes go on top of the Board's manual order.
            let topPosition = ((try? modelContext.fetch(FetchDescriptor<BoardNote>())) ?? []).map(\.position).min() ?? 0
            note = BoardNote(
                text: clean, colorIndex: colorIndex, position: topPosition - 1,
                forEveryone: forEveryone, memberIDs: forEveryone ? [] : recipients,
                createdByID: familySession.memberID, createdByName: actorName
            )
            modelContext.insert(note)
        }
        try? modelContext.save()
        dataSync.pushBoardNote(note, familyID: familyID)
        dataSync.logActivity(
            entityType: "board_note", entityName: String(clean.prefix(60)),
            action: isEditing ? "updated" : "created",
            actorID: familySession.memberID, actorName: actorName,
            familyID: familyID, modelContext: modelContext
        )
        dismiss()
    }
}
