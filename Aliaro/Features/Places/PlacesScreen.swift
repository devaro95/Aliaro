import SwiftUI
import SwiftData
import MapKit

/// "Places" feature: a real map (Apple Maps) with the places the family
/// saves — restaurants, parks, hotels… — each category with its own color
/// and icon. Filter by category with the chips, tap a pin to see it, get
/// directions, edit or delete it. Also available as a list.
struct PlacesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    @Query(sort: \FamilyPlace.name) private var places: [FamilyPlace]

    /// Empty = every category.
    @State private var selectedCategories: Set<PlaceCategory> = []
    @State private var showList = false
    @State private var selectedPlaceID: UUID?
    @State private var position: MapCameraPosition = .automatic
    @State private var showAddSheet = false
    @State private var placeToEdit: FamilyPlace?
    @State private var placePendingDelete: FamilyPlace?

    private var filteredPlaces: [FamilyPlace] {
        guard !selectedCategories.isEmpty else { return places }
        return places.filter { selectedCategories.contains($0.placeCategory) }
    }

    private var selectedPlace: FamilyPlace? {
        guard let selectedPlaceID else { return nil }
        return filteredPlaces.first { $0.id == selectedPlaceID }
    }

    /// Categories that have at least one place, in canonical order.
    private var usedCategories: [PlaceCategory] {
        let used = Set(places.map(\.placeCategory))
        return PlaceCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        trackedBody.trackScreen("places")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ALITopBar(title: "Places", accent: ALIColors.placesAccent) {
                HStack(spacing: 10) {
                    if !places.isEmpty { modeToggle }
                    ALIFloatingButton(accent: ALIColors.placesAccent) {
                        Track.event("place_add_tap", ["places": places.count])
                        showAddSheet = true
                    }
                    .scaleEffect(0.72)
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 20)

            if !usedCategories.isEmpty { categoryChips }

            if showList {
                placesList
            } else {
                map
                    .padding(.horizontal, 20)
                    .padding(.bottom, 84) // clears the floating bottom bar
            }
        }
        .background(ALIColors.background)
        .animation(.easeInOut(duration: 0.2), value: selectedPlaceID)
        .sheet(isPresented: $showAddSheet) {
            AddPlaceSheet(placeToEdit: nil) { created in
                selectedCategories = []
                showList = false
                selectedPlaceID = created.id
                position = .camera(MapCamera(centerCoordinate: created.coordinate, distance: 4000))
            }
        }
        .sheet(item: $placeToEdit) { place in
            AddPlaceSheet(placeToEdit: place) { _ in }
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { placePendingDelete != nil }, set: { if !$0 { placePendingDelete = nil } }),
            itemName: placePendingDelete?.name ?? ""
        ) {
            if let place = placePendingDelete { delete(place) }
            placePendingDelete = nil
        }
    }

    // MARK: Sections

    /// Map / list switch.
    private var modeToggle: some View {
        Button {
            Track.event("places_mode", ["mode": showList ? "map" : "list"])
            withAnimation(.easeInOut(duration: 0.2)) { showList.toggle() }
        } label: {
            Image(systemName: showList ? "map.fill" : "list.bullet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 42, height: 42)
                .background(ALIColors.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showList ? Text("Map") : Text("List"))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PlaceFilterChip(title: "All", category: nil, count: places.count, isSelected: selectedCategories.isEmpty) {
                    selectedCategories = []
                }
                ForEach(usedCategories) { category in
                    PlaceFilterChip(
                        title: category.label, category: category,
                        count: places.filter { $0.placeCategory == category }.count,
                        isSelected: selectedCategories.contains(category)
                    ) {
                        Track.event("places_filter", ["category": category.rawValue])
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                        if let selectedPlace, !selectedCategories.isEmpty, !selectedCategories.contains(selectedPlace.placeCategory) {
                            selectedPlaceID = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var map: some View {
        Map(position: $position, selection: $selectedPlaceID) {
            ForEach(filteredPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    PlaceMarker(category: place.placeCategory, isSelected: place.id == selectedPlaceID)
                }
                .tag(place.id)
                .annotationTitles(place.id == selectedPlaceID ? .visible : .hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let place = selectedPlace {
                PlaceCard(
                    place: place,
                    onDirections: { openInMaps(place) },
                    onEdit: { placeToEdit = place },
                    onDelete: { placePendingDelete = place },
                    onClose: { selectedPlaceID = nil }
                )
                .padding(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if places.isEmpty {
                emptyCard.padding(10)
            }
        }
        .onChange(of: selectedPlaceID) { _, id in
            if id != nil { Track.event("place_open", ["source": "map"]) }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Text("No places yet")
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            Text("Save the restaurants, parks and spots your family loves, and find them here on the map.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var placesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(PlaceCategory.allCases) { category in
                    let items = filteredPlaces.filter { $0.placeCategory == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label { Text(category.label) } icon: { Image(systemName: category.systemImage) }
                                .font(ALITypography.labelLarge.weight(.semibold))
                                .foregroundStyle(category.color)
                            VStack(spacing: 10) {
                                ForEach(items) { place in
                                    Button {
                                        Track.event("place_open", ["source": "list"])
                                        showList = false
                                        selectedPlaceID = place.id
                                        position = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 4000))
                                    } label: {
                                        PlaceRow(place: place)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { openInMaps(place) } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                                        Button { placeToEdit = place } label: { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive) { placePendingDelete = place } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: Actions

    private func openInMaps(_ place: FamilyPlace) {
        Track.event("place_directions", ["category": place.category])
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func delete(_ place: FamilyPlace) {
        let id = place.id
        let name = place.name
        if selectedPlaceID == id { selectedPlaceID = nil }
        modelContext.delete(place)
        try? modelContext.save()
        dataSync.deleteFamilyPlace(id: id)
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "place", entityName: String(name.prefix(60)), action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
    }
}

/// Map pin: a colored drop with the category icon and a small tail.
struct PlaceMarker: View {
    let category: PlaceCategory
    var isSelected: Bool = false

    var body: some View {
        let size: CGFloat = isSelected ? 44 : 34
        VStack(spacing: -3) {
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(category.color.gradient)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
            Triangle()
                .fill(category.color)
                .frame(width: 12, height: 8)
        }
        .shadow(color: .black.opacity(0.25), radius: isSelected ? 6 : 3, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// Category filter chip with a colored icon and how many places it has.
private struct PlaceFilterChip: View {
    let title: LocalizedStringKey
    let category: PlaceCategory?
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color { category?.color ?? ALIColors.ink }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let category {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(isSelected ? Color.white.opacity(0.3) : category.color)
                        .clipShape(Circle())
                }
                Text(title).font(ALITypography.labelLarge).lineLimit(1)
                Text(verbatim: "\(count)")
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(isSelected ? .white : ALIColors.ink)
            .padding(.leading, category == nil ? 12 : 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .background(isSelected ? tint : ALIColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A place in the list.
private struct PlaceRow: View {
    let place: FamilyPlace

    var body: some View {
        HStack(spacing: 14) {
            PlaceMarker(category: place.placeCategory)
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
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
}

/// Card shown over the map for the selected place.
private struct PlaceCard: View {
    let place: FamilyPlace
    let onDirections: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: place.placeCategory.systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(place.placeCategory.color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(2)
                    Text(place.placeCategory.label)
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(place.placeCategory.color)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(width: 28, height: 28)
                        .background(ALIColors.surfaceVariant)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            if !place.address.isEmpty {
                Label(place.address, systemImage: "mappin.and.ellipse")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(2)
            }
            if !place.notes.isEmpty {
                Text(place.notes)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(3)
            }
            if let name = place.createdByName, !name.isEmpty {
                Text("Added by \(name)")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
            }
            HStack(spacing: 8) {
                Button(action: onDirections) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(place.placeCategory.color)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                iconButton("pencil", label: "Edit", action: onEdit)
                iconButton("trash", label: "Delete", action: onDelete)
            }
        }
        .padding(14)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 4)
    }

    private func iconButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
