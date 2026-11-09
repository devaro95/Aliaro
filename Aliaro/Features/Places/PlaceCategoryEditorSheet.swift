import SwiftUI
import SwiftData

/// Create or edit a family place category: name, one of 40 icons and a color.
/// Deleting it moves its places to "Other".
struct PlaceCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let categoryToEdit: PlaceCustomCategory?
    /// Called with the stored value (`FamilyPlace.category`) of the new category.
    var onCreate: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var icon = PlaceCategoryOptions.icons[0]
    @State private var color = PlaceCategoryOptions.colors[0]
    @State private var confirmDelete = false

    private var tint: Color { Color(hex: UInt32(color, radix: 16) ?? 0x7C7488) }
    private var canSave: Bool { !name.trimmed.isEmpty }

    var body: some View {
        trackedBody.trackScreen("place_category_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(tint.gradient)
                            .clipShape(Circle())
                        ALITextField(placeholder: "Category name", text: $name)
                            .onChange(of: name) { _, new in
                                if new.count > PlaceCustomCategory.maxNameLength { name = String(new.prefix(PlaceCustomCategory.maxNameLength)) }
                            }
                    }

                    section("Color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(PlaceCategoryOptions.colors, id: \.self) { hex in
                                let c = Color(hex: UInt32(hex, radix: 16) ?? 0)
                                Button { color = hex } label: {
                                    Circle()
                                        .fill(c)
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                                .opacity(color == hex ? 1 : 0)
                                        )
                                        .overlay(Circle().stroke(ALIColors.ink.opacity(color == hex ? 0.35 : 0), lineWidth: 2).padding(-4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(PlaceCategoryOptions.icons, id: \.self) { symbol in
                                let isSelected = icon == symbol
                                Button { icon = symbol } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : ALIColors.ink)
                                        .frame(width: 44, height: 44)
                                        .background(isSelected ? tint : ALIColors.surfaceVariant)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ALIPrimaryButton(text: "Save", enabled: canSave, accent: ALIColors.placesAccent) { save() }

                    if categoryToEdit != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("Delete category")
                                .font(ALITypography.labelLarge.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(ALIColors.error)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ALIColors.background)
            .navigationTitle(categoryToEdit == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete \"\(name)\"?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its places will move to \"Other\".")
            }
            .onAppear {
                guard let category = categoryToEdit else { return }
                name = category.name
                icon = category.icon
                color = category.color
            }
        }
        .presentationDetents([.large])
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            content()
        }
    }

    private func save() {
        guard let familyID = familySession.familyID else { return }
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { return }
        let category: PlaceCustomCategory
        if let existing = categoryToEdit {
            existing.name = cleanName
            existing.icon = icon
            existing.color = color
            existing.updatedAt = .now
            category = existing
        } else {
            category = PlaceCustomCategory(
                name: cleanName, icon: icon, color: color,
                createdByID: familySession.memberID,
                createdByName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
            )
            modelContext.insert(category)
        }
        try? modelContext.save()
        dataSync.pushPlaceCategory(category, familyID: familyID)
        Track.event(categoryToEdit == nil ? "place_category_new" : "place_category_edited", ["icon": icon])
        if categoryToEdit == nil { onCreate(category.id.uuidString) }
        dismiss()
    }

    private func delete() {
        guard let category = categoryToEdit, let familyID = familySession.familyID else { return }
        let raw = category.id.uuidString
        let places = (try? modelContext.fetch(FetchDescriptor<FamilyPlace>())) ?? []
        for place in places where place.category == raw {
            place.category = PlaceCategory.other.rawValue
            place.updatedAt = .now
            dataSync.pushFamilyPlace(place, familyID: familyID)
        }
        let id = category.id
        modelContext.delete(category)
        try? modelContext.save()
        dataSync.deletePlaceCategory(id: id)
        Track.event("place_category_deleted")
        dismiss()
    }
}
