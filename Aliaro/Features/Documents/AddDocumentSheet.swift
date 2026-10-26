import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Sheet to add a document (scan it, pick a photo or import a PDF, then
/// give it a title and a category) or to edit one (title and category;
/// the file itself never changes once saved).
struct AddDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query(sort: [SortDescriptor(\DocumentCategory.position), SortDescriptor(\DocumentCategory.createdAt)])
    private var categories: [DocumentCategory]

    let documentToEdit: FamilyDocument?
    /// Category preselected for a new document (the screen's current filter).
    let initialCategoryID: UUID?

    @State private var title = ""
    @State private var categoryID: UUID?
    @State private var draft: DocumentDraft?
    @State private var showScanner = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showNewCategory = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { documentToEdit != nil }

    private var canSave: Bool {
        !title.trimmed.isEmpty && (isEditing || draft != nil) && !isSaving
    }

    var body: some View {
        trackedBody.trackScreen("document_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !isEditing {
                        if let draft {
                            draftPreview(draft)
                        } else {
                            sourceButtons
                        }
                    }

                    ALITextField(placeholder: "Title (e.g. Electricity bill)", text: $title)
                        .onChange(of: title) { _, new in
                            if new.count > FamilyDocument.maxTitleLength { title = String(new.prefix(FamilyDocument.maxTitleLength)) }
                        }

                    categoryCard

                    ALIPrimaryButton(
                        text: isSaving ? "Saving…" : "Save",
                        enabled: canSave,
                        accent: ALIColors.documentsAccent
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit document" : "New document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                if let document = documentToEdit {
                    title = document.title
                    categoryID = document.categoryID
                } else if categoryID == nil {
                    categoryID = initialCategoryID
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        setDraft(DocumentImport.image(from: data), source: "library")
                    }
                    photoItem = nil
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                if case let .success(url) = result {
                    setDraft(DocumentImport.pdf(at: url), source: "files")
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { pages in
                    setDraft(DocumentImport.pdf(from: pages), source: "scanner")
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showNewCategory) {
                DocumentCategoryEditorSheet(categoryToEdit: nil) { created in
                    categoryID = created.id
                }
            }
            .alert("Couldn't save the document", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: Sections

    /// Where the document comes from.
    private var sourceButtons: some View {
        HStack(spacing: 10) {
            if DocumentScannerView.isAvailable {
                sourceButton(title: "Scan", systemImage: "doc.viewfinder") { showScanner = true }
            }
            sourceButton(title: "Photo", systemImage: "photo.on.rectangle") { showLibrary = true }
            sourceButton(title: "File", systemImage: "folder") { showFiles = true }
        }
    }

    private func sourceButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                Text(title)
                    .font(ALITypography.titleLarge)
            }
            .foregroundStyle(ALIColors.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(ALIColors.documentsAccent.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func draftPreview(_ draft: DocumentDraft) -> some View {
        ZStack {
            ALIColors.documentsAccent.opacity(0.2)
            if let preview = draft.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                self.draft = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(10)
            .disabled(isSaving)
        }
        .overlay(alignment: .bottomLeading) {
            if draft.type == .pdf, draft.pageCount > 1 {
                Text("\(draft.pageCount) pages")
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .foregroundStyle(ALIColors.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ALIColors.surface)
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
    }

    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Category")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                FlowChips(spacing: 8) {
                    ForEach(categories) { category in
                        DocumentChip(title: category.displayName, icon: category.icon, isSelected: categoryID == category.id) {
                            categoryID = categoryID == category.id ? nil : category.id
                        }
                    }
                    Button {
                        showNewCategory = true
                    } label: {
                        Label("New category", systemImage: "plus")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(Capsule().stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Actions

    private func setDraft(_ newDraft: DocumentDraft?, source: String) {
        guard let newDraft else {
            errorMessage = String(localized: "This file can't be read.")
            return
        }
        guard newDraft.data.count <= FamilyDocument.maxFileSize else {
            errorMessage = String(localized: "The file is too big (20 MB max).")
            return
        }
        draft = newDraft
        if title.trimmed.isEmpty, !newDraft.suggestedTitle.isEmpty {
            title = String(newDraft.suggestedTitle.prefix(FamilyDocument.maxTitleLength))
        }
        Track.event("document_source", ["source": source, "type": newDraft.type.rawValue, "pages": newDraft.pageCount])
    }

    private func save() {
        guard let familyID = familySession.familyID else { return }
        let trimmedTitle = title.trimmed
        guard !trimmedTitle.isEmpty else { return }
        let actorName = familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }

        if let document = documentToEdit {
            document.title = trimmedTitle
            document.categoryID = categoryID
            document.updatedAt = .now
            try? modelContext.save()
            dataSync.pushDocument(document, familyID: familyID)
            Track.event("document_edited")
            dataSync.logActivity(
                entityType: "document", entityName: String(trimmedTitle.prefix(60)), action: "updated",
                actorID: familySession.memberID, actorName: actorName, familyID: familyID, modelContext: modelContext
            )
            dismiss()
            return
        }

        guard let draft else { return }
        isSaving = true
        let document = FamilyDocument(
            title: trimmedTitle, categoryID: categoryID, fileType: draft.type, fileSize: draft.data.count,
            pageCount: draft.pageCount, createdByID: familySession.memberID, createdByName: actorName
        )
        Task {
            do {
                try await dataSync.uploadDocument(document, data: draft.data, familyID: familyID)
                // Realtime may have delivered the row already.
                let id = document.id
                let existing = try? modelContext.fetch(FetchDescriptor<FamilyDocument>(predicate: #Predicate { $0.id == id })).first
                if existing == nil { modelContext.insert(document) }
                try? modelContext.save()
                Track.event("document_new", ["type": draft.type.rawValue, "pages": draft.pageCount, "has_category": categoryID != nil])
                dataSync.logActivity(
                    entityType: "document", entityName: String(trimmedTitle.prefix(60)), action: "created",
                    actorID: familySession.memberID, actorName: actorName, familyID: familyID, modelContext: modelContext
                )
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = String(localized: "Check your connection and try again.")
            }
        }
    }
}
