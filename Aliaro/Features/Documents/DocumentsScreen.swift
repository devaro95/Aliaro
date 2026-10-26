import SwiftUI
import SwiftData
import QuickLook

/// "Documents" feature: the family's paperwork (receipts, invoices, the
/// vaccination card…) scanned with the camera, imported from Files or
/// picked from Photos, organized in categories the family creates.
/// Everything is shared with the whole group.
///
/// Premium (`PremiumFeature.documents`): when locked, the screen shows
/// blurred sample documents and the premium banner.
struct DocumentsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \FamilyDocument.createdAt, order: .reverse) private var documents: [FamilyDocument]
    @Query(sort: [SortDescriptor(\DocumentCategory.position), SortDescriptor(\DocumentCategory.createdAt)])
    private var categories: [DocumentCategory]

    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var showAddSheet = false
    @State private var documentToEdit: FamilyDocument?
    @State private var documentPendingDelete: FamilyDocument?
    @State private var showCategories = false
    @State private var showPaywall = false
    /// File being shown in Quick Look.
    @State private var previewURL: URL?
    /// Document whose file is being downloaded to open it.
    @State private var openingID: UUID?
    @State private var openFailed = false

    private var isLocked: Bool { premium.isLocked(.documents) }

    private var filteredDocuments: [FamilyDocument] {
        let query = searchText.trimmed
        return documents.filter { document in
            (selectedCategoryID.map { document.categoryID == $0 } ?? true)
                && (query.isEmpty || document.title.localizedCaseInsensitiveContains(query))
        }
    }

    private func category(of document: FamilyDocument) -> DocumentCategory? {
        guard let id = document.categoryID else { return nil }
        return categories.first { $0.id == id }
    }

    var body: some View {
        trackedBody.trackScreen("documents")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(alignment: .leading, spacing: 16) {
                ALITopBar(title: "Documents", accent: ALIColors.documentsAccent) {
                    ALIFloatingButton(accent: ALIColors.documentsAccent) {
                        Track.event("document_add_tap", ["documents": documents.count])
                        showAddSheet = true
                    }
                    .scaleEffect(0.72)
                    .aliPremiumPreview(isLocked)
                }

                if isLocked {
                    VStack(spacing: 10) {
                        ForEach(DocumentSample.all) { sample in
                            DocumentRow(
                                title: sample.title, subtitle: sample.subtitle, icon: sample.icon,
                                document: nil, isLoading: false, onTap: {}
                            )
                        }
                    }
                    .aliPremiumPreview(true)
                } else {
                    categoryChips

                    if documents.isEmpty {
                        ALIEmptyState(
                            icon: ALIIcon.archive,
                            title: "No documents yet",
                            subtitle: "Scan receipts, invoices or the vaccination card and keep them here for the whole family."
                        )
                    } else {
                        ALITextField(placeholder: "Search documents…", text: $searchText)

                        if filteredDocuments.isEmpty {
                            ALIEmptyState(icon: ALIIcon.search, title: "No results", subtitle: "Try another search or category.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredDocuments) { document in
                                    row(document)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .aliPremiumPreviewBanner(isLocked, buttonTitle: "Unlock documents") {
            showPaywall = Track.paywall("documents_banner")
        }
        .sheet(isPresented: $showAddSheet) {
            AddDocumentSheet(documentToEdit: nil, initialCategoryID: selectedCategoryID)
        }
        .sheet(item: $documentToEdit) { document in
            AddDocumentSheet(documentToEdit: document, initialCategoryID: nil)
        }
        .sheet(isPresented: $showCategories) {
            DocumentCategoriesSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .quickLookPreview($previewURL)
        .alert("Couldn't open the document", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { documentPendingDelete != nil }, set: { if !$0 { documentPendingDelete = nil } }),
            itemName: documentPendingDelete?.title ?? ""
        ) {
            if let document = documentPendingDelete { delete(document) }
            documentPendingDelete = nil
        }
    }

    /// "All", one chip per category, and a button to manage them.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DocumentChip(title: String(localized: "All"), icon: nil, isSelected: selectedCategoryID == nil) {
                    selectedCategoryID = nil
                }
                ForEach(categories) { category in
                    DocumentChip(title: category.displayName, icon: category.icon, isSelected: selectedCategoryID == category.id) {
                        Track.event("document_filter_category", ["is_default": category.isDefault])
                        selectedCategoryID = selectedCategoryID == category.id ? nil : category.id
                    }
                }
                Button {
                    showCategories = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ALIColors.ink)
                        .frame(width: 36, height: 34)
                        .background(ALIColors.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ALIColors.outline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Categories"))
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func row(_ document: FamilyDocument) -> some View {
        DocumentRow(
            title: document.title,
            subtitle: subtitle(for: document),
            icon: category(of: document)?.icon ?? ALIIcon.archive,
            document: document,
            isLoading: openingID == document.id,
            onTap: { open(document) }
        )
        .contextMenu {
            Button { open(document) } label: { Label("Open", systemImage: "doc.text") }
            Button { documentToEdit = document } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { documentPendingDelete = document } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// "Invoices · Ana · 3 pages"
    private func subtitle(for document: FamilyDocument) -> String {
        var parts: [String] = []
        if let category = category(of: document) { parts.append(category.displayName) }
        if let name = document.createdByName, !name.isEmpty { parts.append(name) }
        parts.append(document.createdAt.formatted(date: .abbreviated, time: .omitted))
        if document.type == .pdf, document.pageCount > 1 {
            parts.append(String(localized: "\(document.pageCount) pages"))
        }
        return parts.joined(separator: " · ")
    }

    private func open(_ document: FamilyDocument) {
        guard openingID == nil else { return }
        Track.event("document_open", ["type": document.fileType])
        openingID = document.id
        Task {
            let url = await dataSync.documentFile(document)
            openingID = nil
            if let url { previewURL = url } else { openFailed = true }
        }
    }

    private func delete(_ document: FamilyDocument) {
        let id = document.id
        let title = document.title
        let path = document.filePath
        modelContext.delete(document)
        try? modelContext.save()
        dataSync.deleteDocument(id: id, filePath: path)
        Track.event("document_deleted")
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "document", entityName: String(title.prefix(60)), action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
    }
}

/// Card for a document in the list: thumbnail (or category icon), title
/// and a meta line.
private struct DocumentRow: View {
    let title: String
    let subtitle: String
    let icon: String
    /// Real document (thumbnail); `nil` for the locked samples.
    let document: FamilyDocument?
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ALIColors.documentsAccent.opacity(0.25))
                    ALIIconView(icon: icon, size: 22, color: ALIColors.ink)
                    if let document { DocumentThumbnail(document: document) }
                }
                .frame(width: 52, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                }
            }
            .padding(12)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// First page / photo of a document, downloaded on demand. Shows nothing
/// (the category icon behind stays visible) until it's ready.
private struct DocumentThumbnail: View {
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    let document: FamilyDocument
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: 52, height: 64)
        .clipped()
        .task(id: document.filePath) {
            guard !document.filePath.isEmpty, let url = await dataSync.documentFile(document) else { return }
            image = DocumentFileCache.shared.thumbnail(
                for: url, path: document.filePath, type: document.type, size: CGSize(width: 104, height: 128)
            )
        }
    }
}

/// Category filter chip with its icon.
struct DocumentChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { ALIIconView(icon: icon, size: 14, color: isSelected ? ALIColors.onAccent : ALIColors.ink) }
                Text(title).font(ALITypography.labelLarge).lineLimit(1)
            }
            .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? ALIColors.documentsAccent : ALIColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder rows for the locked preview.
private struct DocumentSample: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String

    static let all: [DocumentSample] = [
        DocumentSample(title: String(localized: "Electricity bill"), subtitle: String(localized: "Invoices"), icon: ALIIcon.euro),
        DocumentSample(title: String(localized: "Vaccination card"), subtitle: String(localized: "Medical"), icon: ALIIcon.health),
        DocumentSample(title: String(localized: "Washing machine receipt"), subtitle: String(localized: "Receipts"), icon: ALIIcon.receipt),
        DocumentSample(title: String(localized: "Family book"), subtitle: String(localized: "Family documents"), icon: ALIIcon.user),
    ]
}
