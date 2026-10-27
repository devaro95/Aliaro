import SwiftUI
import SwiftData
import MapKit

/// Add or edit a place: search it (Apple Maps search) or tap the map to
/// drop the pin, pick a category and optionally add a note.
struct AddPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let placeToEdit: FamilyPlace?
    /// Called with the new place after creating it (the screen zooms to it).
    let onCreate: (FamilyPlace) -> Void

    @State private var name = ""
    @State private var category: PlaceCategory = .restaurant
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var notes = ""

    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var noResults = false
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?

    private var canSave: Bool { !name.trimmed.isEmpty && coordinate != nil }

    var body: some View {
        trackedBody.trackScreen("place_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    locationCard

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
                guard let place = placeToEdit else { return }
                name = place.name
                category = place.placeCategory
                coordinate = place.coordinate
                address = place.address
                notes = place.notes
                position = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 3000))
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Location

    private var locationCard: some View {
        ALICard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ALIColors.mutedInk)
                    TextField("Search a place or address", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit(search)
                        .foregroundStyle(ALIColors.ink)
                    if isSearching { ProgressView() }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(results.prefix(6).enumerated()), id: \.offset) { index, item in
                            Button { choose(item) } label: { resultRow(item) }
                                .buttonStyle(.plain)
                            if index < min(results.count, 6) - 1 { Divider().overlay(ALIColors.outline) }
                        }
                    }
                } else if noResults {
                    Text("No results. Try another search or tap the map.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate {
                            Annotation("", coordinate: coordinate, anchor: .bottom) {
                                PlaceMarker(category: category, isSelected: true)
                            }
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .including([.restaurant, .cafe, .park, .museum, .hotel, .store])))
                    .onMapCameraChange { context in visibleRegion = context.region }
                    .onTapGesture { point in
                        guard let tapped = proxy.convert(point, from: .local) else { return }
                        Track.event("place_pin_moved")
                        setLocation(tapped, reverseGeocode: true)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if coordinate == nil {
                    Text("Search above or tap the map to drop the pin.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                } else if !address.isEmpty {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(2)
                }
            }
        }
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "")
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(Self.address(of: item.placemark))
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Category")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(PlaceCategory.allCases) { option in
                        let isSelected = category == option
                        Button {
                            category = option
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: option.systemImage)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(option.color)
                                    .clipShape(Circle())
                                Text(option.label)
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
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func search() {
        let query = searchText.trimmed
        guard !query.isEmpty else { return }
        isSearching = true
        noResults = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let visibleRegion { request.region = visibleRegion }
        Track.event("place_search")
        MKLocalSearch(request: request).start { response, _ in
            isSearching = false
            results = response?.mapItems ?? []
            noResults = results.isEmpty
        }
    }

    private func choose(_ item: MKMapItem) {
        if name.trimmed.isEmpty, let itemName = item.name { name = String(itemName.prefix(FamilyPlace.maxNameLength)) }
        if let guess = Self.category(for: item.pointOfInterestCategory) { category = guess }
        address = Self.address(of: item.placemark)
        setLocation(item.placemark.coordinate, reverseGeocode: false)
        results = []
        searchText = ""
        Track.event("place_search_pick")
    }

    private func setLocation(_ new: CLLocationCoordinate2D, reverseGeocode: Bool) {
        coordinate = new
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: new, distance: visibleRegion.map { max($0.span.latitudeDelta * 111_000, 800) } ?? 3000))
        }
        guard reverseGeocode else { return }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: new.latitude, longitude: new.longitude)) { placemarks, _ in
            guard coordinate?.latitude == new.latitude, coordinate?.longitude == new.longitude,
                  let placemark = placemarks?.first else { return }
            address = Self.address(of: MKPlacemark(placemark: placemark))
        }
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
            existing.category = category.rawValue
            existing.latitude = coordinate.latitude
            existing.longitude = coordinate.longitude
            existing.address = address.trimmed
            existing.notes = notes.trimmed
            existing.updatedAt = .now
            place = existing
        } else {
            place = FamilyPlace(
                name: cleanName, category: category, latitude: coordinate.latitude, longitude: coordinate.longitude,
                address: address.trimmed, notes: notes.trimmed,
                createdByID: familySession.memberID, createdByName: actorName
            )
            modelContext.insert(place)
        }
        try? modelContext.save()
        dataSync.pushFamilyPlace(place, familyID: familyID)
        Track.event(placeToEdit == nil ? "place_new" : "place_edited", ["category": category.rawValue, "has_notes": !notes.trimmed.isEmpty])
        dataSync.logActivity(
            entityType: "place", entityName: String(cleanName.prefix(60)), action: placeToEdit == nil ? "created" : "updated",
            actorID: familySession.memberID, actorName: actorName, familyID: familyID, modelContext: modelContext
        )
        if placeToEdit == nil { onCreate(place) }
        dismiss()
    }
}
