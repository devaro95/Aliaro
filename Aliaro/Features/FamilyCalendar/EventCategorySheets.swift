import SwiftUI
import SwiftData

/// Category picker for an event (optional): "None", one chip per category
/// (color + name), a "+ New" chip and "Edit" to manage them.
struct EventCategoryPickerCard: View {
    @Query(sort: [SortDescriptor(\EventCategory.position), SortDescriptor(\EventCategory.createdAt)])
    private var categories: [EventCategory]

    @Binding var selection: UUID?
    var enabled: Bool = true

    @State private var showNew = false
    @State private var showManage = false

    var body: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Category")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                    Spacer()
                    if enabled {
                        Button("Edit") { showManage = true }
                            .font(ALITypography.labelLarge.weight(.semibold))
                            .foregroundStyle(ALIColors.ink)
                    }
                }
                ALIFlowLayout(spacing: 8) {
                    noneChip
                    ForEach(categories) { category in
                        chip(category)
                    }
                    if enabled {
                        Button {
                            showNew = true
                        } label: {
                            Label("New", systemImage: "plus")
                                .font(ALITypography.bodyMedium.weight(.semibold))
                                .foregroundStyle(ALIColors.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .overlay(Capsule().stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) {
            EventCategoryEditorSheet(category: nil) { created in selection = created.id }
        }
        .sheet(isPresented: $showManage) {
            EventCategoriesSheet()
        }
    }

    private var noneChip: some View {
        let isSelected = selection == nil || !categories.contains { $0.id == selection }
        return Button {
            selection = nil
        } label: {
            HStack(spacing: 6) {
                Circle().fill(EventCategory.noneColor).frame(width: 12, height: 12)
                Text("None")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isSelected ? ALIItemColors.soft(EventCategory.noneColor, 0.55) : ALIColors.surfaceVariant, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? EventCategory.noneColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func chip(_ category: EventCategory) -> some View {
        let isSelected = selection == category.id
        return Button {
            selection = isSelected ? nil : category.id
        } label: {
            HStack(spacing: 6) {
                Circle().fill(category.swiftUIColor).frame(width: 12, height: 12)
                Text(category.displayName)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isSelected ? ALIItemColors.soft(category.swiftUIColor, 0.55) : ALIColors.surfaceVariant, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? category.swiftUIColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Simple wrapping layout for chips.
struct ALIFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The family's calendar categories: tap one to rename it or change its
/// color; the family's own ones can also be deleted.
struct EventCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\EventCategory.position), SortDescriptor(\EventCategory.createdAt)])
    private var categories: [EventCategory]

    @State private var editing: EventCategory?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            editing = category
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(category.swiftUIColor).frame(width: 22, height: 22)
                                Text(category.displayName)
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(ALIColors.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                            }
                        }
                        .listRowBackground(ALIColors.surface)
                    }
                } footer: {
                    Text("Events take the color of their category. Changing it updates every event in that category.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ALIColors.background)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("New category"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { category in
                EventCategoryEditorSheet(category: category) { _ in }
            }
            .sheet(isPresented: $showNew) {
                EventCategoryEditorSheet(category: nil) { _ in }
            }
        }
        .trackScreen("event_categories")
    }
}

/// Create or edit a category: name and color. Changing the color repaints
/// the category's events; deleting one (default ones too) leaves its events
/// without a category (default color).
struct EventCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query private var categories: [EventCategory]
    @Query private var events: [FamilyEvent]

    let category: EventCategory?
    let onSave: (EventCategory) -> Void

    @State private var name = ""
    @State private var color: String? = ALIItemColors.palette.first
    @State private var confirmDelete = false

    private var canSave: Bool { !name.trimmed.isEmpty && color != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ALITextField(placeholder: "Category name", text: $name)
                    ALIColorPickerCard(selection: Binding(get: { color }, set: { if let new = $0 { color = new } }))

                    ALIPrimaryButton(text: category == nil ? "Create category" : "Save", enabled: canSave, accent: ALIColors.familyAccent) {
                        save()
                    }

                    if category != nil {
                        Button("Delete category", role: .destructive) { confirmDelete = true }
                            .font(ALITypography.bodyMedium.weight(.semibold))
                            .foregroundStyle(ALIColors.error)
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let category {
                    name = category.displayName
                    color = category.color
                } else {
                    // A color not used yet, if there's one.
                    let used = Set(categories.map(\.color))
                    color = ALIItemColors.palette.first { !used.contains($0) } ?? ALIItemColors.palette.first
                }
            }
            .alert("Delete category?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Its events will stay without a category.")
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard canSave, let color, let familyID = familySession.familyID else { return }
        let cleanName = String(name.trimmed.prefix(30))
        let saved: EventCategory
        if let category {
            // Keep the stored English name of a default category while it isn't renamed (so it stays translated).
            if !(category.isDefault && cleanName == category.displayName) { category.name = cleanName }
            let colorChanged = category.color != color
            category.color = color
            saved = category
            if colorChanged { repaintEvents(of: category, familyID: familyID) }
            Track.event("event_category_edited", ["is_default": category.isDefault, "color_changed": colorChanged])
        } else {
            saved = EventCategory(name: cleanName, color: color, position: (categories.map(\.position).max() ?? 0) + 1)
            modelContext.insert(saved)
            Track.event("event_category_created")
        }
        try? modelContext.save()
        dataSync.pushEventCategory(saved, familyID: familyID)
        onSave(saved)
        dismiss()
    }

    /// Events take their category's color (`family_events.color`, so every
    /// version of the app and the calendar ring show it).
    private func repaintEvents(of category: EventCategory, familyID: UUID) {
        for event in events where event.resolvedCategoryID(familyID: familyID) == category.id {
            event.categoryID = category.id
            event.color = category.color
            dataSync.pushFamilyEvent(event, familyID: familyID)
        }
    }

    private func delete() {
        guard let category, let familyID = familySession.familyID else { return }
        for event in events where event.resolvedCategoryID(familyID: familyID) == category.id {
            event.categoryID = nil
            event.color = nil
            event.emoji = EventCategory.noneIcon
            dataSync.pushFamilyEvent(event, familyID: familyID)
        }
        let id = category.id
        modelContext.delete(category)
        try? modelContext.save()
        dataSync.deleteEventCategory(id: id)
        Track.event("event_category_deleted", ["is_default": category.isDefault])
        dismiss()
    }
}
