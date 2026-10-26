import SwiftUI
import SwiftData

/// Manage the family's document categories: add, rename / change icon and
/// delete (its documents stay, uncategorized).
struct DocumentCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @Query(sort: [SortDescriptor(\DocumentCategory.position), SortDescriptor(\DocumentCategory.createdAt)])
    private var categories: [DocumentCategory]
    @Query private var documents: [FamilyDocument]

    @State private var showNew = false
    @State private var categoryToEdit: DocumentCategory?
    @State private var categoryPendingDelete: DocumentCategory?

    var body: some View {
        trackedBody.trackScreen("document_categories")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(categories) { category in
                        row(category)
                    }

                    Button {
                        showNew = true
                    } label: {
                        Label("New category", systemImage: "plus")
                            .font(ALITypography.titleLarge)
                            .foregroundStyle(ALIColors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showNew) {
                DocumentCategoryEditorSheet(categoryToEdit: nil)
            }
            .sheet(item: $categoryToEdit) { category in
                DocumentCategoryEditorSheet(categoryToEdit: category)
            }
            .aliDeleteConfirmDialog(
                isPresented: Binding(get: { categoryPendingDelete != nil }, set: { if !$0 { categoryPendingDelete = nil } }),
                itemName: categoryPendingDelete?.displayName ?? ""
            ) {
                if let category = categoryPendingDelete { delete(category) }
                categoryPendingDelete = nil
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ category: DocumentCategory) -> some View {
        let count = documents.filter { $0.categoryID == category.id }.count
        return HStack(spacing: 14) {
            Button {
                categoryToEdit = category
            } label: {
                HStack(spacing: 14) {
                    ALIIconView(icon: category.icon, size: 20)
                        .frame(width: 42, height: 42)
                        .background(ALIColors.documentsAccent.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName)
                            .font(ALITypography.titleLarge)
                            .foregroundStyle(ALIColors.ink)
                            .lineLimit(1)
                        Text(count == 1 ? String(localized: "1 document") : String(localized: "\(count) documents"))
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                categoryPendingDelete = category
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk.opacity(0.7))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }

    private func delete(_ category: DocumentCategory) {
        let id = category.id
        // Postgres sets their category to null too (ON DELETE SET NULL).
        for document in documents where document.categoryID == id { document.categoryID = nil }
        modelContext.delete(category)
        try? modelContext.save()
        dataSync.deleteDocumentCategory(id: id)
        Track.event("document_category_deleted")
    }
}

/// Create or edit a document category: name and icon.
struct DocumentCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query private var categories: [DocumentCategory]

    let categoryToEdit: DocumentCategory?
    var onCreate: (DocumentCategory) -> Void = { _ in }

    @State private var name = ""
    @State private var icon = ALIIcon.archive

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ALITextField(placeholder: "Name (e.g. Car)", text: $name)
                        .onChange(of: name) { _, new in
                            if new.count > DocumentCategory.maxNameLength { name = String(new.prefix(DocumentCategory.maxNameLength)) }
                        }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(DocumentCategory.iconOptions, id: \.self) { option in
                            iconButton(option)
                        }
                    }

                    ALIPrimaryButton(text: "Save", enabled: !name.trimmed.isEmpty, accent: ALIColors.documentsAccent) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(categoryToEdit == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let category = categoryToEdit {
                    name = category.displayName
                    icon = category.icon
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func iconButton(_ option: String) -> some View {
        let isSelected = icon == option
        return Button {
            icon = option
        } label: {
            ALIIconView(icon: option, size: 22)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isSelected ? ALIColors.documentsAccent.opacity(0.35) : ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? ALIColors.documentsAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, let familyID = familySession.familyID else { return }
        if let category = categoryToEdit {
            // A renamed default category keeps the name as typed.
            if trimmed != category.displayName {
                category.name = trimmed
                category.isDefault = false
            }
            category.icon = icon
            try? modelContext.save()
            dataSync.pushDocumentCategory(category, familyID: familyID)
            Track.event("document_category_edited")
        } else {
            let position = (categories.map(\.position).max() ?? -1) + 1
            let category = DocumentCategory(name: trimmed, icon: icon, position: position)
            modelContext.insert(category)
            try? modelContext.save()
            dataSync.pushDocumentCategory(category, familyID: familyID)
            Track.event("document_category_created", ["icon": icon])
            onCreate(category)
        }
        dismiss()
    }
}
