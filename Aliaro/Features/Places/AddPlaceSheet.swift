import SwiftUI
import SwiftData
import MapKit

/// Add or edit a place. First the address: as you type, Apple Maps suggests
/// places and addresses. Once one is picked, the name (prefilled), the
/// category and the notes show up. No map here.
struct AddPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let placeToEdit: FamilyPlace?
    /// Where the user is, to suggest nearby places first.
    var near: CLLocation? = nil
    /// Called with the new place after creating it (the screen zooms to it).
    let onCreate: (FamilyPlace) -> Void

    @State private var name = ""
    @Query(sort: \PlaceCustomCategory.createdAt) private var customCategories: [PlaceCustomCategory]
    /// `FamilyPlace.category` value: a fixed category or a family one.
    @State private var category: String = PlaceCategory.restaurant.rawValue
    @State private var showNewCategory = false
    @State private var categoryToEdit: PlaceCustomCategory?

    private var categoryStyle: PlaceCategoryStyle { PlaceCategoryStyle.resolve(category, customs: customCategories) }
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var notes = ""

    @State private var searchText = ""
    @StateObject private var completer = PlaceSearchCompleter()
    @State private var isResolving = false
    @FocusState private var searchFocused: Bool

    private var canSave: Bool { !name.trimmed.isEmpty && coordinate != nil }

    var body: some View {
        trackedBody.trackScreen("place_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if coordinate == nil {
                        searchCard
                    } else {
                        selectedLocationCard
                        if let coordinate { confirmMap(coordinate) }

                        ALITextField(placeholder: "Name (e.g. Casa Lucio)", text: $name)
                            .onChange(of: name) { _, new in
                                if new.count > FamilyPlace.maxNameLength { name = String(new.prefix(FamilyPlace.maxNameLength)) }
                            }

                        categoryCard

                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(16)
                            .foregroundStyle(ALIColors.ink)
                            .background(ALIColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(ALIColors.outline, lineWidth: 1)
                            )
                            .onChange(of: notes) { _, new in
                                if new.count > FamilyPlace.maxNotesLength { notes = String(new.prefix(FamilyPlace.maxNotesLength)) }
                            }

                        ALIPrimaryButton(text: "Save", enabled: canSave, accent: ALIColors.placesAccent) {
                            save()
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: coordinate == nil)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ALIColors.background)
            .navigationTitle(placeToEdit == nil ? "New place" : "Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                completer.near = near ?? CLLocationManager().location
                guard let place = placeToEdit else {
                    searchFocused = true
                    return
                }
                name = place.name
                category = place.category
                coordinate = place.coordinate
                address = place.address
                notes = place.notes
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showNewCategory) {
            PlaceCategoryEditorSheet(categoryToEdit: nil) { created in category = created }
        }
        .sheet(item: $categoryToEdit) { custom in
            PlaceCategoryEditorSheet(categoryToEdit: custom)
        }
    }

    // MARK: Location

    /// Step 1: type the address; suggestions update as you type.
    private var searchCard: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ALIColors.mutedInk)
                    TextField("Search a place or address", text: $searchText)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            if let first = completer.places.first { choose(first) }
                            else if let first = completer.results.first { choose(first) }
                        }
                        .foregroundStyle(ALIColors.ink)
                        .onChange(of: searchText) { _, new in completer.update(query: new) }
                    if isResolving { ProgressView() }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !completer.places.isEmpty || !completer.results.isEmpty {
                    VStack(spacing: 0) {
                        let places = Array(completer.places.prefix(6))
                        let addresses = Array(completer.results.prefix(max(0, 8 - places.count)))
                        ForEach(Array(places.enumerated()), id: \.offset) { index, item in
                            Button { choose(item) } label: {
                                resultRow(title: item.name ?? "", subtitle: Self.address(of: item.placemark), poi: item.pointOfInterestCategory)
                            }
                            .buttonStyle(.plain)
                            if index < places.count - 1 || !addresses.isEmpty { Divider().overlay(ALIColors.outline) }
                        }
                        ForEach(Array(addresses.enumerated()), id: \.offset) { index, completion in
                            Button { choose(completion) } label: {
                                resultRow(title: completion.title, subtitle: completion.subtitle, poi: nil)
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolving)
                            if index < addresses.count - 1 { Divider().overlay(ALIColors.outline) }
                        }
                    }
                } else if completer.noResults {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No results")
                            .font(ALITypography.labelLarge.weight(.semibold))
                            .foregroundStyle(ALIColors.ink)
                        Text("Try another search.")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
            }
        }
    }

    /// Step 2: the picked place, with a button to search again.
    private var selectedLocationCard: some View {
        Group {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(categoryStyle.color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(address.isEmpty ? name : address)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Change") {
                    Track.event("place_location_change")
                    coordinate = nil
                    searchText = ""
                    completer.update(query: "")
                    searchFocused = true
                }
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.placesAccent)
            }
        }
    }

    /// Small static map with the picked place, so the user can check it's the right one.
    private func confirmMap(_ coordinate: CLLocationCoordinate2D) -> some View {
        Map(
            initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 2500)),
            interactionModes: []
        ) {
            Annotation("", coordinate: coordinate, anchor: .bottom) {
                PlaceMarker(style: categoryStyle, isSelected: true)
            }
        }
        .id("\(coordinate.latitude),\(coordinate.longitude)")
        .frame(height: 180)
        .allowsHitTesting(false) // orientativo: no se mueve
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }

    /// A suggestion: a place (with its category icon) or an address (pin).
    private func resultRow(title: String, subtitle: String, poi: MKPointOfInterestCategory?) -> some View {
        let guess = Self.category(for: poi)
        return HStack(spacing: 10) {
            Image(systemName: guess?.systemImage ?? "mappin")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(guess?.color ?? ALIColors.placesAccent)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// Fixed and family categories, plus "New category" (long press a family one to edit it).
    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Category")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(PlaceCategoryStyle.all(customs: customCategories)) { option in
                        let isSelected = categoryStyle.id == option.id
                        Button {
                            category = option.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(option.color)
                                    .clipShape(Circle())
                                option.title
                                    .font(ALITypography.labelLarge)
                                    .foregroundStyle(ALIColors.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .background(isSelected ? option.color.opacity(0.22) : ALIColors.surfaceVariant)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? option.color : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let custom = option.custom {
                                Button { categoryToEdit = custom } label: { Label("Edit", systemImage: "pencil") }
                            }
                        }
                    }
                    Button {
                        Track.event("place_category_new_tap")
                        showNewCategory = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ALIColors.placesAccent)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(ALIColors.placesAccent, style: StrokeStyle(lineWidth: 1.5, dash: [3])))
                            Text("New category")
                                .font(ALITypography.labelLarge.weight(.semibold))
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .overlay(Capsule().stroke(ALIColors.outline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Actions

    /// Resolves the suggestion to a real place (coordinate, address, category).
    private func choose(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Track.event("place_search_pick")
        MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start { response, _ in
            isResolving = false
            guard let item = response?.mapItems.first else { return }
            apply(item, fallbackName: completion.title, fallbackAddress: completion.subtitle)
        }
    }

    private func choose(_ item: MKMapItem) {
        Track.event("place_search_pick")
        apply(item, fallbackName: item.name ?? "", fallbackAddress: "")
    }

    private func apply(_ item: MKMapItem, fallbackName: String, fallbackAddress: String) {
        let itemName = item.name ?? fallbackName
        if name.trimmed.isEmpty || placeToEdit == nil { name = String(itemName.prefix(FamilyPlace.maxNameLength)) }
        if let guess = Self.category(for: item.pointOfInterestCategory) { category = guess.rawValue }
        let resolved = Self.address(of: item.placemark)
        address = resolved.isEmpty ? String(fallbackAddress.prefix(200)) : resolved
        coordinate = item.placemark.coordinate
        searchFocused = false
    }

    /// "Calle Mayor 1, Madrid"
    static func address(of placemark: MKPlacemark) -> String {
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, placemark.locality, placemark.locality == nil ? placemark.administrativeArea : nil, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return String(parts.joined(separator: ", ").prefix(200))
    }

    /// Our category for an Apple Maps point of interest, when it's obvious.
    static func category(for poi: MKPointOfInterestCategory?) -> PlaceCategory? {
        guard let poi else { return nil }
        switch poi {
        case .restaurant, .bakery, .foodMarket: return .restaurant
        case .cafe, .brewery, .winery, .nightlife: return .cafe
        case .park, .nationalPark, .beach, .campground, .marina: return .nature
        case .museum, .library, .theater: return .culture
        case .store: return .shopping
        case .amusementPark, .aquarium, .zoo, .movieTheater, .stadium, .fitnessCenter: return .leisure
        case .hotel, .airport: return .travel
        default: return nil
        }
    }

    private func save() {
        guard let coordinate, let familyID = familySession.familyID else { return }
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { return }
        let actorName = familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
        let place: FamilyPlace
        if let existing = placeToEdit {
            existing.name = cleanName
            existing.category = categoryStyle.id
            existing.latitude = coordinate.latitude
            existing.longitude = coordinate.longitude
            existing.address = address.trimmed
            existing.notes = notes.trimmed
            existing.updatedAt = .now
            place = existing
        } else {
            place = FamilyPlace(
                name: cleanName, category: categoryStyle.id, latitude: coordinate.latitude, longitude: coordinate.longitude,
                address: address.trimmed, notes: notes.trimmed,
                createdByID: familySession.memberID, createdByName: actorName
            )
            modelContext.insert(place)
        }
        try? modelContext.save()
        dataSync.pushFamilyPlace(place, familyID: familyID)
        Track.event(placeToEdit == nil ? "place_new" : "place_edited", ["category": categoryStyle.builtin?.rawValue ?? "custom", "has_notes": !notes.trimmed.isEmpty])
        dataSync.logActivity(
            entityType: "place", entityName: String(cleanName.prefix(60)), action: placeToEdit == nil ? "created" : "updated",
            actorID: familySession.memberID, actorName: actorName, familyID: familyID, modelContext: modelContext
        )
        if placeToEdit == nil { onCreate(place) }
        dismiss()
    }
}

/// Live suggestions while typing: businesses and places (Apple Maps search,
/// near the user) first, then addresses (autocomplete).
@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var places: [MKMapItem] = []
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var noResults = false
    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var placesDone = false
    private var addressesDone = false

    /// Bias the suggestions around here (~30 km).
    var near: CLLocation? {
        didSet { if let region { completer.region = region } }
    }

    private var region: MKCoordinateRegion? {
        near.map { MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !clean.isEmpty else {
            completer.cancel()
            places = []
            results = []
            noResults = false
            return
        }
        placesDone = false
        addressesDone = false
        completer.queryFragment = clean
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = clean
            request.resultTypes = .pointOfInterest
            if let region = self.region { request.region = region }
            let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            guard !Task.isCancelled else { return }
            self.places = items
            self.placesDone = true
            self.refreshNoResults()
        }
    }

    private func refreshNoResults() {
        noResults = placesDone && addressesDone && places.isEmpty && results.isEmpty
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let new = completer.results
        let empty = completer.queryFragment.isEmpty
        Task { @MainActor in
            self.results = empty ? [] : new
            self.addressesDone = true
            self.refreshNoResults()
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
            self.addressesDone = true
            self.refreshNoResults()
        }
    }
}
