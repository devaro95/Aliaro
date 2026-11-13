import SwiftUI
import SwiftData
import MapKit

/// "Places" feature: a real map (Apple Maps) with the places the family
/// saves — restaurants, parks, hotels… — each category with its own color
/// and icon, and the user's location (the map opens centered on it). Below
/// the map (a full-width horizontal strip), category tabs to filter and the
/// places as a list, nearest first. Tap a pin or a row to see it, get
/// directions, edit or delete it.
struct PlacesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager
    @State private var showPaywall = false
    /// The map is mounted just after the push animation, so the first-time MapKit
    /// setup doesn't freeze the navigation.
    @State private var mapReady = false
    /// Premium (`PremiumFeature.places`): when locked, a blurred sample map and list behind the banner.
    private var isLocked: Bool { premium.isLocked(.places) }

    @Query(sort: \FamilyPlace.name) private var places: [FamilyPlace]
    @Query(sort: \PlaceCustomCategory.createdAt) private var customCategories: [PlaceCustomCategory]

    /// nil = every category. A `FamilyPlace.category` value.
    @State private var selectedCategory: String?
    @State private var categoryToEdit: PlaceCustomCategory?
    @Environment(\.leaveFullScreen) private var leaveFullScreen
    /// Height of the list sheet over the map.
    @State private var sheetDetent: SheetDetent = .collapsed
    @GestureState private var sheetDrag: CGFloat = 0
    /// Place whose "Directions" app chooser is open.
    @State private var directionsPlace: FamilyPlace?
    @Environment(\.openURL) private var openURL
    @State private var selectedPlaceID: UUID?
    @State private var position: MapCameraPosition = .automatic
    /// Centered on the user once, on the first location fix.
    @State private var didCenterOnUser = false
    @StateObject private var location = PlacesLocation()
    @State private var showAddSheet = false
    @State private var placeToEdit: FamilyPlace?
    @State private var placePendingDelete: FamilyPlace?

    private func style(of place: FamilyPlace) -> PlaceCategoryStyle {
        PlaceCategoryStyle.resolve(place.category, customs: customCategories)
    }

    /// The selected tab, if it still has places.
    private var activeCategory: String? {
        guard let selectedCategory, usedCategories.contains(where: { $0.id == selectedCategory }) else { return nil }
        return selectedCategory
    }

    private var filteredPlaces: [FamilyPlace] {
        guard let activeCategory else { return places }
        return places.filter { style(of: $0).id == activeCategory }
    }

    /// Filtered places, nearest first (by name until we know where the user is).
    private var sortedPlaces: [FamilyPlace] {
        guard let here = location.current else { return filteredPlaces }
        return filteredPlaces.sorted { distance(to: $0, from: here) < distance(to: $1, from: here) }
    }

    private func distance(to place: FamilyPlace, from here: CLLocation) -> CLLocationDistance {
        here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private var selectedPlace: FamilyPlace? {
        guard let selectedPlaceID else { return nil }
        return filteredPlaces.first { $0.id == selectedPlaceID }
    }

    /// Categories that have at least one place, in canonical order.
    private var usedCategories: [PlaceCategoryStyle] {
        let used = Set(places.map { style(of: $0).id })
        return PlaceCategoryStyle.all(customs: customCategories).filter { used.contains($0.id) }
    }

    var body: some View {
        trackedBody.trackScreen("places")
    }

    @ViewBuilder
    private var trackedBody: some View {
        Group {
            if isLocked {
                lockedPreview
            } else {
                placesBody
            }
        }
        .task {
            guard !mapReady else { return }
            try? await Task.sleep(for: .milliseconds(350)) // push animation
            withAnimation(.easeIn(duration: 0.2)) { mapReady = true }
        }
    }

    /// Locked (premium): a sample map and list, blurred and inert, under the banner.
    private var lockedPreview: some View {
        ZStack(alignment: .top) {
            // Drawn map (not MapKit): shows instantly, it's only a blurred backdrop.
            SampleMapBackdrop()
                .aliPremiumPreview(true)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    Track.event("places_back")
                    leaveFullScreen()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ALIColors.ink)
                        .frame(width: 44, height: 44)
                        .background(ALIColors.surface)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                }
                .accessibilityLabel("Back")
                ALITopBar(title: "Places", accent: ALIColors.placesAccent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [ALIColors.background, ALIColors.background.opacity(0.85), ALIColors.background.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            VStack(spacing: 10) {
                Capsule()
                    .fill(ALIColors.outline)
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                VStack(spacing: 10) {
                    ForEach(PlaceSample.all) { sample in
                        PlaceRow(place: sample.place, style: PlaceCategoryStyle(sample.category), distance: sample.distance)
                    }
                }
                .padding(.horizontal, 20)
                .aliPremiumPreview(true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .background(ALIColors.background)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(ALIColors.background)
        .aliPremiumPreviewBanner(true, buttonTitle: "Unlock places", accent: ALIColors.placesAccent) {
            showPaywall = Track.paywall("places_banner")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var placesBody: some View {
        // Full-screen map; title, + and category chips float on top; the list is
        // a bottom sheet that snaps to three heights (like Apple/Google Maps).
        GeometryReader { geo in
            let height = geo.size.height
            let restTop = sheetTop(for: sheetDetent, height: height)
            let liveTop = min(max(restTop + sheetDrag, sheetTop(for: .medium, height: height)), sheetTop(for: .collapsed, height: height))
            ZStack(alignment: .top) {
                Group {
                    if mapReady { map } else { Color(hex: 0xEEF0E8) }
                }
                    // Visible part of the map: below the title/chips, above the sheet.
                    .safeAreaPadding(.top, 120)
                    // Fixed (not following the sheet) so the map doesn't move when it resizes.
                    .safeAreaPadding(.bottom, places.isEmpty ? 140 : max(0, height - sheetTop(for: .medium, height: height)))
                    .ignoresSafeArea()

                if !places.isEmpty {
                    Button {
                        Track.event("places_locate_me")
                        withAnimation { position = .userLocation(fallback: .automatic) }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ALIColors.ink)
                            .frame(width: 44, height: 44)
                            .background(ALIColors.surface)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    }
                    .accessibilityLabel("My location")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .offset(y: liveTop - 58)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        // No floating bar here: back to where we came from.
                        Button {
                            Track.event("places_back")
                            leaveFullScreen()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 44, height: 44)
                                .background(ALIColors.surface)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                        }
                        .accessibilityLabel("Back")
                    ALITopBar(title: "Places", accent: ALIColors.placesAccent) {
                        ALIFloatingButton(accent: ALIColors.placesAccent) {
                            Track.event("place_add_tap", ["places": places.count])
                            showAddSheet = true
                        }
                        .scaleEffect(0.72)
                        .frame(width: 44, height: 44)
                    }
                    }
                    .padding(.horizontal, 20)
                    if !usedCategories.isEmpty { categoryTabs }
                }
                .padding(.bottom, 10)
                .background(
                    LinearGradient(
                        colors: [ALIColors.background, ALIColors.background.opacity(0.85), ALIColors.background.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )

                if places.isEmpty {
                    emptyCard
                        .padding(.horizontal, 20)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                } else {
                    placesSheet(height: height)
                        .offset(y: liveTop)
                }
            }
        }
        .background(ALIColors.background)
        .confirmationDialog(
            "Directions",
            isPresented: Binding(get: { directionsPlace != nil }, set: { if !$0 { directionsPlace = nil } }),
            titleVisibility: .visible,
            presenting: directionsPlace
        ) { place in
            Button("Apple Maps") { openDirections(place, in: .apple) }
            Button("Google Maps") { openDirections(place, in: .google) }
            Button("Waze") { openDirections(place, in: .waze) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // Open already centered on the last known position (no wait for a fresh fix).
            if !didCenterOnUser, let here = location.current {
                didCenterOnUser = true
                position = .camera(MapCamera(centerCoordinate: here.coordinate, distance: 20_000))
            }
            location.start()
        }
        .onChange(of: location.current) { _, here in
            // Open centered on the user, zoomed out enough to see the area around (~20 km).
            guard let here, !didCenterOnUser, selectedPlaceID == nil else { return }
            didCenterOnUser = true
            withAnimation { position = .camera(MapCamera(centerCoordinate: here.coordinate, distance: 20_000)) }
        }
        .onDisappear { location.stop() }
        .animation(.easeInOut(duration: 0.2), value: selectedPlaceID)
        .sheet(isPresented: $showAddSheet) {
            AddPlaceSheet(placeToEdit: nil, near: location.current) { created in
                selectedCategory = nil
                selectedPlaceID = created.id
                position = .camera(MapCamera(centerCoordinate: created.coordinate, distance: 4000))
            }
        }
        .sheet(item: $placeToEdit) { place in
            AddPlaceSheet(placeToEdit: place, near: location.current) { _ in }
        }
        .sheet(item: $categoryToEdit) { category in
            PlaceCategoryEditorSheet(categoryToEdit: category)
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { placePendingDelete != nil }, set: { if !$0 { placePendingDelete = nil } }),
            itemName: placePendingDelete?.name ?? ""
        ) {
            if let place = placePendingDelete { delete(place) }
            placePendingDelete = nil
        }
    }

    // MARK: Bottom sheet

    private enum SheetDetent: CaseIterable { case collapsed, medium }

    /// Y of the sheet's top edge for each height.
    private func sheetTop(for detent: SheetDetent, height: CGFloat) -> CGFloat {
        switch detent {
        case .collapsed: return height - 150 // grabber + count + first row (no bottom bar here)
        case .medium: return height * 0.42
        }
    }

    private func placesSheet(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag handle area: grabber + count. Drag to resize, tap to toggle.
            VStack(spacing: 10) {
                Capsule()
                    .fill(ALIColors.outline)
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                HStack {
                    Text(filteredPlaces.count == 1 ? LocalizedStringKey("1 place") : LocalizedStringKey("\(filteredPlaces.count) places"))
                        .font(ALITypography.headlineMedium)
                        .foregroundStyle(ALIColors.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
            .gesture(sheetDragGesture(height: height))
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    sheetDetent = sheetDetent == .medium ? .collapsed : .medium
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 0).id("top")
                        if let place = selectedPlace {
                            PlaceCard(
                                place: place,
                                style: style(of: place),
                                onDirections: { directionsPlace = place },
                                onEdit: { placeToEdit = place },
                                onDelete: { placePendingDelete = place },
                                onClose: { selectedPlaceID = nil }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        placesList(scrollToTop: { withAnimation { proxy.scrollTo("top", anchor: .top) } })
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    // Room for the part of the sheet below the screen.
                    .padding(.bottom, 24 + sheetTop(for: sheetDetent, height: height) - sheetTop(for: .medium, height: height))
                }
                // Minimized: the list doesn't scroll (raise the sheet to browse).
                .scrollDisabled(sheetDetent == .collapsed)
                .onChange(of: selectedPlaceID) { _, id in
                    guard id != nil else { return }
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .frame(height: height - sheetTop(for: .medium, height: height) + 40, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(ALIColors.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
        .onChange(of: selectedPlaceID) { _, id in
            // Picking a pin while the sheet is down: raise it so the card shows.
            if id != nil, sheetDetent == .collapsed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sheetDetent = .medium }
            }
        }
    }

    private func sheetDragGesture(height: CGFloat) -> some Gesture {
        // Global coordinates: the handle moves with the sheet, so local ones would
        // feed the movement back into the drag and make it jitter.
        DragGesture(coordinateSpace: .global)
            .updating($sheetDrag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let current = sheetTop(for: sheetDetent, height: height)
                // Where it would land with a bit of momentum, then the nearest height.
                let projected = current + value.predictedEndTranslation.height
                let nearest = SheetDetent.allCases.min {
                    abs(sheetTop(for: $0, height: height) - projected) < abs(sheetTop(for: $1, height: height) - projected)
                } ?? .medium
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sheetDetent = nearest }
                Track.event("places_sheet", ["detent": "\(nearest)"])
            }
    }

    // MARK: Sections

    /// Capsule chips to filter by category (long press a family category to edit it).
    private var categoryTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PlaceCategoryChip(title: Text("All"), style: nil, count: places.count, isSelected: activeCategory == nil) {
                        select(nil)
                    }
                    .id("all")
                    ForEach(usedCategories) { category in
                        PlaceCategoryChip(
                            title: category.title, style: category,
                            count: places.filter { style(of: $0).id == category.id }.count,
                            isSelected: activeCategory == category.id
                        ) {
                            Track.event("places_filter", ["category": category.builtin?.rawValue ?? "custom"])
                            select(category.id)
                        }
                        .contextMenu {
                            if let custom = category.custom {
                                Button { categoryToEdit = custom } label: { Label("Edit", systemImage: "pencil") }
                            }
                        }
                        .id(category.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onChange(of: activeCategory) { _, category in
                withAnimation { proxy.scrollTo(category ?? "all", anchor: .center) }
            }
        }
    }

    private func select(_ category: String?) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = category }
        if let selectedPlace, let category, style(of: selectedPlace).id != category {
            selectedPlaceID = nil
        }
    }

    private var map: some View {
        Map(position: $position, selection: $selectedPlaceID) {
            UserAnnotation()
            ForEach(filteredPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    PlaceMarker(style: style(of: place), isSelected: place.id == selectedPlaceID)
                }
                .tag(place.id)
                .annotationTitles(place.id == selectedPlaceID ? .visible : .hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { }
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
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }

    /// The filtered places, nearest first, with their distance.
    private func placesList(scrollToTop: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sortedPlaces) { place in
                Button {
                    Track.event("place_open", ["source": "list"])
                    selectedPlaceID = place.id
                    position = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 4000))
                    scrollToTop()
                } label: {
                    PlaceRow(place: place, style: style(of: place), distance: location.current.map { distance(to: place, from: $0) })
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { directionsPlace = place } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    Button { placeToEdit = place } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { placePendingDelete = place } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: Actions

    private enum DirectionsApp: String { case apple, google, waze }

    /// Directions in Apple Maps, Google Maps or Waze (Google and Waze links open their app when installed, else the web).
    private func openDirections(_ place: FamilyPlace, in app: DirectionsApp) {
        Track.event("place_directions", ["category": place.category, "app": app.rawValue])
        let lat = place.coordinate.latitude
        let lng = place.coordinate.longitude
        switch app {
        case .apple:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        case .google:
            if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)") { openURL(url) }
        case .waze:
            if let url = URL(string: "https://waze.com/ul?ll=\(lat),\(lng)&navigate=yes") { openURL(url) }
        }
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
    let style: PlaceCategoryStyle
    var isSelected: Bool = false

    var body: some View {
        let size: CGFloat = isSelected ? 44 : 34
        VStack(spacing: -3) {
            Image(systemName: style.icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(style.color.gradient)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
            Triangle()
                .fill(style.color)
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

/// Category filter chip (capsule, like the rest of the app): icon + name + count,
/// filled with the category color when selected.
private struct PlaceCategoryChip: View {
    let title: Text
    let style: PlaceCategoryStyle?
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color { style?.color ?? ALIColors.placesAccent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let style {
                    Image(systemName: style.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? ALIColors.onAccent : style.color)
                }
                title
                    .font(ALITypography.labelLarge.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(verbatim: "\(count)")
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? tint : ALIColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 6, y: 2) // floats over the map
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// A place in the list.
private struct PlaceRow: View {
    let place: FamilyPlace
    let style: PlaceCategoryStyle
    /// Meters from the user, when known.
    var distance: CLLocationDistance? = nil

    private static let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 14) {
            PlaceMarker(style: style)
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
            if let distance {
                Text(Self.distanceFormatter.string(fromDistance: distance))
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .foregroundStyle(style.color)
                    .lineLimit(1)
            }
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
    let style: PlaceCategoryStyle
    let onDirections: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: style.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(style.color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(2)
                    style.title
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(style.color)
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
                        .background(style.color)
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

/// The user's location for the places map: asks for "when in use" permission
/// and keeps the last known position (to sort the list by distance).
@MainActor
final class PlacesLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var current: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        // Last known position right away, so the map opens centered without waiting.
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            current = manager.location
        }
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                Track.event("places_location_granted")
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.current = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Sample places (not saved anywhere) for the locked premium preview.
private struct PlaceSample: Identifiable {
    let id = UUID()
    let place: FamilyPlace
    let category: PlaceCategory
    let distance: CLLocationDistance

    static let all: [PlaceSample] = [
        PlaceSample(
            place: FamilyPlace(name: String(localized: "Grandma's favourite restaurant"), latitude: 40.4200, longitude: -3.7040),
            category: .restaurant, distance: 350
        ),
        PlaceSample(
            place: FamilyPlace(name: String(localized: "Park with swings"), latitude: 40.4150, longitude: -3.6850),
            category: .nature, distance: 1200
        ),
        PlaceSample(
            place: FamilyPlace(name: String(localized: "Sunday café"), latitude: 40.4250, longitude: -3.6950),
            category: .cafe, distance: 900
        ),
        PlaceSample(
            place: FamilyPlace(name: String(localized: "Science museum"), latitude: 40.4110, longitude: -3.7120),
            category: .culture, distance: 2100
        ),
    ]
}

/// Drawn stand-in for a map (roads, a park, water and sample pins) behind the
/// locked premium preview: no MapKit, so it appears instantly. Same as Android.
private struct SampleMapBackdrop: View {
    private let pins: [(x: CGFloat, y: CGFloat, category: PlaceCategory)] = [
        (0.38, 0.22, .restaurant), (0.22, 0.33, .shopping), (0.55, 0.15, .cafe),
        (0.76, 0.36, .nature), (0.62, 0.44, .culture),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xEEF0E8)))
                    context.fill(
                        Path(ellipseIn: CGRect(x: w * 0.53, y: h * 0.42 - w * 0.32, width: w * 0.64, height: w * 0.64)),
                        with: .color(Color(hex: 0xCFE8C4))
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: w * 0.1 - w * 0.45, y: h * 0.95 - w * 0.45, width: w * 0.9, height: w * 0.9)),
                        with: .color(Color(hex: 0xCFE3F2))
                    )
                    let roads: [(CGPoint, CGPoint, CGFloat)] = [
                        (CGPoint(x: -20, y: h * 0.30), CGPoint(x: w + 20, y: h * 0.25), 20),
                        (CGPoint(x: w * 0.35, y: -20), CGPoint(x: w * 0.45, y: h + 20), 16),
                        (CGPoint(x: -20, y: h * 0.60), CGPoint(x: w + 20, y: h * 0.55), 13),
                        (CGPoint(x: w * 0.7, y: -20), CGPoint(x: w * 0.8, y: h + 20), 10),
                    ]
                    for (from, to, width) in roads {
                        var road = Path()
                        road.move(to: from)
                        road.addLine(to: to)
                        context.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }
                ForEach(Array(pins.enumerated()), id: \.offset) { _, pin in
                    PlaceMarker(style: PlaceCategoryStyle(pin.category))
                        .position(x: w * pin.x, y: h * pin.y)
                }
            }
        }
    }
}
