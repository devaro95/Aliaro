import SwiftUI
import SwiftData

extension BoardNote {
    /// Sticky-note colors a note can take (`colorIndex`).
    static let colors: [Color] = [
        ALIColors.sun, ALIColors.peopleAccent, ALIColors.familyAccent,
        ALIColors.remindersAccent, ALIColors.houseTasksAccent, ALIColors.boardAccent,
    ]

    var color: Color { Self.colors[max(0, colorIndex) % Self.colors.count] }
}

/// "Board" feature: short notes for the whole family that stay pinned —
/// here and on Home — until someone deletes them. Each note has a grip
/// (≡): press it to lift the note and drag to reorder. Home shows the
/// notes in the same order. Notes can be for everyone or for specific
/// people (see `BoardNote.isVisibleOnBoard`).
///
/// Premium (`PremiumFeature.board`): when locked, the screen shows blurred
/// sample notes and `BoardPremiumBanner`, which explains that the Board
/// puts messages on the family's Home screen.
struct BoardScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: [SortDescriptor(\BoardNote.position), SortDescriptor(\BoardNote.createdAt, order: .reverse)])
    private var allNotes: [BoardNote]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var showAddSheet = false
    @State private var selectedNote: BoardNote?
    @State private var notePendingDelete: BoardNote?
    @State private var showPaywall = false
    /// Placeholder notes shown blurred behind the premium banner.
    @State private var sampleNotes = BoardNote.samples()

    // Drag-to-reorder state (custom, so the lifted note keeps its own look
    // instead of the system's dark drag platter).
    /// Note being dragged, if any.
    @State private var draggingID: UUID?
    /// Working order while dragging; persisted on release.
    @State private var dragOrder: [UUID] = []
    /// Finger translation since the drag started.
    @State private var dragTranslation: CGFloat = 0
    /// Distance the dragged note has already moved by swapping slots, so
    /// its visual offset stays under the finger.
    @State private var dragShift: CGFloat = 0
    /// Measured height of each note card.
    @State private var heights: [UUID: CGFloat] = [:]

    private let spacing: CGFloat = 12

    private var isLocked: Bool { premium.isLocked(.board) }

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canAdd: Bool { currentMember?.can(.boardAdd) ?? true }
    private var canEdit: Bool { currentMember?.can(.boardEdit) ?? true }
    private var canDelete: Bool { currentMember?.can(.boardDelete) ?? true }

    /// Notes this member sees on the Board: addressed to them or pinned by them.
    private var notes: [BoardNote] {
        allNotes.filter { $0.isVisibleOnBoard(to: familySession.memberID) }
    }

    /// Notes in the order shown: the working order while dragging.
    private var displayedNotes: [BoardNote] {
        guard draggingID != nil else { return notes }
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return dragOrder.compactMap { byID[$0] }
    }

    var body: some View {
        trackedBody.trackScreen("board")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(alignment: .leading, spacing: 16) {
                ALITopBar(title: "Board", accent: ALIColors.boardAccent) {
                    if canAdd {
                        ALIFloatingButton(accent: ALIColors.boardAccent) {
                            Track.event("board_note_add_tap", ["notes": notes.count])
                            showAddSheet = true
                        }
                        .scaleEffect(0.72)
                        // Locked: blurred and inert like the rest of the preview.
                        .aliPremiumPreview(isLocked)
                    }
                }

                if isLocked {
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(sampleNotes) { note in
                            BoardNoteCard(note: note, recipientsLabel: nil, onTap: {})
                        }
                    }
                    .aliPremiumPreview(true)
                } else if notes.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.bookmark,
                        title: "The board is empty",
                        subtitle: "Pin anything the whole family should keep in mind. It stays here and on Home until someone deletes it."
                    )
                } else {
                    if notes.count > 1 {
                        Label {
                            Text("Drag a note by its handle to reorder it. Home shows them in this order.")
                        } icon: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                    }

                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(displayedNotes) { note in
                            noteRow(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .scrollDisabled(draggingID != nil)
        .safeAreaInset(edge: .bottom) {
            if isLocked {
                // Clears the floating bottom bar (56pt + its 8pt margin).
                BoardPremiumBanner { showPaywall = Track.paywall("board_banner") }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 72)
            }
        }
        .background(ALIColors.background)
        .sensoryFeedback(.impact(weight: .medium), trigger: draggingID) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: dragOrder)
        .sheet(isPresented: $showAddSheet) {
            AddBoardNoteSheet(noteToEdit: nil)
        }
        .sheet(item: $selectedNote) { note in
            AddBoardNoteSheet(noteToEdit: note)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { notePendingDelete != nil }, set: { if !$0 { notePendingDelete = nil } }),
            itemName: notePendingDelete.map { String($0.text.prefix(40)) } ?? ""
        ) {
            if let note = notePendingDelete { delete(note) }
            notePendingDelete = nil
        }
    }

    @ViewBuilder
    private func noteRow(_ note: BoardNote) -> some View {
        let isDragging = draggingID == note.id
        BoardNoteCard(
            note: note,
            recipientsLabel: recipientsLabel(for: note),
            onTap: { if canEdit { selectedNote = note } },
            onDelete: canDelete ? { notePendingDelete = note } : nil
        ) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isDragging ? ALIColors.ink : ALIColors.mutedInk)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .highPriorityGesture(reorderGesture(for: note.id))
                .accessibilityLabel(Text("Reorder"))
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { heights[note.id] = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in heights[note.id] = new }
            }
        )
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: Color.black.opacity(isDragging ? 0.18 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .offset(y: isDragging ? dragTranslation - dragShift : 0)
        .zIndex(isDragging ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
    }

    /// Press the grip to lift the note; move it over a neighbor's midpoint
    /// to swap places; release to save the order.
    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if draggingID == nil {
                    dragOrder = notes.map(\.id)
                    dragShift = 0
                    draggingID = id
                }
                guard draggingID == id else { return }
                dragTranslation = value.translation.height
                swapIfNeeded(id)
            }
            .onEnded { _ in
                guard draggingID == id else { return }
                let finalOrder = dragOrder
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    draggingID = nil
                    dragTranslation = 0
                    dragShift = 0
                }
                persist(order: finalOrder)
            }
    }

    private func swapIfNeeded(_ id: UUID) {
        while let index = dragOrder.firstIndex(of: id) {
            let offset = dragTranslation - dragShift
            if offset > 0, index + 1 < dragOrder.count {
                let step = (heights[dragOrder[index + 1]] ?? 0) + spacing
                guard offset > step / 2 else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    dragOrder.swapAt(index, index + 1)
                }
                dragShift += step
            } else if offset < 0, index > 0 {
                let step = (heights[dragOrder[index - 1]] ?? 0) + spacing
                guard -offset > step / 2 else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    dragOrder.swapAt(index, index - 1)
                }
                dragShift -= step
            } else {
                return
            }
        }
    }

    /// Saves the order as positions 0…n-1, pushing only the notes whose
    /// position actually changed.
    private func persist(order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let familyID = familySession.familyID
        var changed = 0
        for (index, id) in order.enumerated() {
            guard let note = byID[id], note.position != index else { continue }
            note.position = index
            changed += 1
            if let familyID { dataSync.pushBoardNote(note, familyID: familyID) }
        }
        guard changed > 0 else { return }
        try? modelContext.save()
        Track.event("board_note_reorder", ["notes": notes.count])
    }

    /// `nil` for everyone; otherwise the names it's addressed to.
    private func recipientsLabel(for note: BoardNote) -> String? {
        guard !note.forEveryone else { return nil }
        let names = members.filter { note.memberIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? String(localized: "No recipient") : names.joined(separator: ", ")
    }

    private func delete(_ note: BoardNote) {
        let id = note.id
        let text = note.text
        modelContext.delete(note)
        dataSync.deleteBoardNote(id: id)
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "board_note", entityName: String(text.prefix(60)), action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
    }
}

/// A sticky note: the text, who pinned it and when. Used on the Board
/// (with delete and a trailing accessory, the reorder grip) and, compact,
/// on Home.
struct BoardNoteCard<Accessory: View>: View {
    let note: BoardNote
    var compact: Bool = false
    /// "Ana, Luis" when the note isn't for everyone (Board only).
    var recipientsLabel: String? = nil
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    private var footer: String {
        let when = note.createdAt.formatted(.relative(presentation: .named))
        guard let name = note.createdByName, !name.isEmpty else { return when }
        return "\(name) · \(when)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ALIColors.onAccent)
                    .rotationEffect(.degrees(35))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(note.text)
                        .font(compact ? ALITypography.bodyLarge : ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(compact ? 2 : nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if compact { Spacer(minLength: 0) }
                    if let name = note.createdByName, !name.isEmpty, compact {
                        Text(name)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                    }
                    if !compact {
                        if let recipientsLabel {
                            Label(recipientsLabel, systemImage: "person.fill")
                                .font(ALITypography.labelLarge.weight(.semibold))
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                        }
                        Text(footer)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ALIColors.mutedInk.opacity(0.7))
                            .frame(width: 32, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                accessory()
            }
            .padding(compact ? 14 : 18)
            .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [note.color.opacity(0.55), note.color.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension BoardNoteCard where Accessory == EmptyView {
    init(note: BoardNote, compact: Bool = false, recipientsLabel: String? = nil, onTap: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.init(note: note, compact: compact, recipientsLabel: recipientsLabel, onTap: onTap, onDelete: onDelete, accessory: { EmptyView() })
    }
}

/// Paywall banner for the locked Board: a small Home-screen mockup with a
/// note pinned on it, so it's obvious at a glance that the Board puts
/// messages on everyone's Home.
private struct BoardPremiumBanner: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HomeMockup()

            VStack(spacing: 6) {
                Label("Premium feature", systemImage: "crown.fill")
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .foregroundStyle(ALIColors.mutedInk)
                Text("Messages on everyone's Home")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)
                    .multilineTextAlignment(.center)
                Text("Pin a note and it shows up on the Home screen of the whole family, or only of the people you choose, until someone deletes it.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ALIPrimaryButton(text: "Unlock the board", accent: ALIColors.boardAccent, action: action)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [ALIColors.boardAccent.opacity(0.25), ALIColors.surface],
                startPoint: .top,
                endPoint: .center
            )
        )
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }
}

/// Tiny phone showing Home with a pinned note between the other sections.
private struct HomeMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Top bar: accent dot + "Home" + avatar.
            HStack(spacing: 5) {
                Circle().fill(ALIColors.primary).frame(width: 6, height: 6)
                Text("Home")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.ink)
                Spacer()
                Circle().fill(ALIColors.peopleAccent.opacity(0.6)).frame(width: 14, height: 14)
            }
            // "Today" card placeholder.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ALIColors.surfaceVariant)
                .frame(height: 22)
            // The pinned note, highlighted.
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(35))
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().frame(width: 62, height: 4)
                    Capsule().frame(width: 40, height: 4)
                }
                .opacity(0.55)
            }
            .foregroundStyle(ALIColors.onAccent)
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALIColors.sun)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .rotationEffect(.degrees(-3))
            .shadow(color: ALIColors.sun.opacity(0.6), radius: 6, y: 2)
            // Feature grid placeholder.
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ALIColors.surfaceVariant)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ALIColors.surfaceVariant)
            }
            .frame(height: 18)
        }
        .padding(10)
        .frame(width: 124)
        .background(ALIColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ALIColors.ink.opacity(0.15), lineWidth: 3)
        )
        .accessibilityHidden(true)
    }
}

extension BoardNote {
    /// Placeholder notes (not inserted anywhere) for the locked previews
    /// on the Board and on Home.
    static func samples() -> [BoardNote] {
        [
            BoardNote(text: String(localized: "Wi-Fi: Home-5G · Password on the fridge"), colorIndex: 0, createdByName: String(localized: "Mum")),
            BoardNote(text: String(localized: "The plumber comes on Thursday morning"), colorIndex: 2, createdByName: String(localized: "Dad")),
            BoardNote(text: String(localized: "Grandma's birthday on Sunday! 🎂"), colorIndex: 1, createdByName: String(localized: "Mum")),
        ]
    }
}
