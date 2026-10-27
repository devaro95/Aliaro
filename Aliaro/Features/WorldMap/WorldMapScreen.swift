import SwiftUI
import SwiftData

/// "World map" feature: a map of the world with only the countries'
/// outlines. Each member marks the countries they've visited (tapping them
/// on the map or from the list) and they fill in. "Everyone" shows the
/// whole family — the more members who've been there, the stronger the
/// color — and each member's chip shows just theirs.
struct WorldMapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    @Query private var visits: [VisitedCountry]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    /// `nil` = everyone.
    @State private var selectedMemberID: UUID?
    @State private var showPicker = false
    @State private var showFullScreen = false
    /// Last country toggled from the map, shown for a moment.
    @State private var toast: Toast?

    struct Toast: Equatable {
        let code: String
        let added: Bool
    }

    private var myID: UUID? { familySession.memberID }

    /// Visits shown with the current filter.
    private var shownVisits: [VisitedCountry] {
        guard let selectedMemberID else { return visits }
        return visits.filter { $0.memberID == selectedMemberID }
    }

    /// Code → ids of the members who've been there (current filter).
    private var visitorsByCountry: [String: Set<UUID>] {
        shownVisits.reduce(into: [:]) { $0[$1.countryCode, default: []].insert($1.memberID) }
    }

    /// Only my own countries can be changed: on "Everyone" or my own chip.
    private var canEdit: Bool { myID != nil && (selectedMemberID == nil || selectedMemberID == myID) }

    var body: some View {
        trackedBody.trackScreen("world_map")
    }

    @ViewBuilder
    private var trackedBody: some View {
        let visitors = visitorsByCountry
        let memberCount = max(selectedMemberID == nil ? members.count : 1, 1)
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(alignment: .leading, spacing: 16) {
                ALITopBar(title: "World map", accent: ALIColors.worldMapAccent) {
                    if myID != nil {
                        ALIFloatingButton(accent: ALIColors.worldMapAccent) {
                            Track.event("world_map_picker_open")
                            showPicker = true
                        }
                        .scaleEffect(0.72)
                    }
                }

                memberChips

                statsCard(count: visitors.count)

                mapCard(visitors: visitors, memberCount: memberCount)

                if visitors.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.plane,
                        title: "No countries yet",
                        subtitle: "Mark the countries you've visited and watch the family map fill up."
                    )
                } else {
                    visitedList(visitors: visitors)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sensoryFeedback(.selection, trigger: toast)
        .sheet(isPresented: $showPicker) {
            CountryPickerSheet()
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            WorldMapFullScreen(
                fill: { fillAmount(visitors[$0]?.count ?? 0, of: memberCount) },
                canEdit: canEdit,
                onTap: toggle
            )
        }
    }

    private func fillAmount(_ count: Int, of total: Int) -> Double {
        count == 0 ? 0 : Double(count) / Double(total)
    }

    // MARK: Sections

    private var memberChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "Everyone"), icon: nil, isSelected: selectedMemberID == nil) {
                    selectedMemberID = nil
                }
                ForEach(members) { member in
                    chip(title: member.name, icon: member.emoji, isSelected: selectedMemberID == member.id) {
                        Track.event("world_map_filter_member", ["is_me": member.id == myID])
                        selectedMemberID = selectedMemberID == member.id ? nil : member.id
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func chip(title: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { ALIIconView(icon: icon, size: 14, color: isSelected ? ALIColors.onAccent : ALIColors.ink, fallback: ALIIcon.user) }
                Text(title).font(ALITypography.labelLarge).lineLimit(1)
            }
            .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? ALIColors.worldMapAccent : ALIColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statsCard(count: Int) -> some View {
        let percent = min(100, Int((Double(count) / Double(CountryInfo.worldCount) * 100).rounded()))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(count)")
                .font(ALITypography.displayMedium)
                .foregroundStyle(ALIColors.ink)
            Text(count == 1 ? LocalizedStringKey("country") : LocalizedStringKey("countries"))
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            Text("\(percent)% of the world")
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.mutedInk)
        }
    }

    private func mapCard(visitors: [String: Set<UUID>], memberCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let data = WorldMapData.shared
                WorldMapCanvas(
                    fill: { fillAmount(visitors[$0]?.count ?? 0, of: memberCount) },
                    highlighted: toast?.code
                )
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let scale = data.size.width / proxy.size.width
                    if let code = data.country(at: CGPoint(x: location.x * scale, y: location.y * scale)) {
                        toggle(code)
                    }
                }
            }
            .aspectRatio(WorldMapData.shared.size.width / WorldMapData.shared.size.height, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Button {
                    Track.event("world_map_fullscreen")
                    showFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ALIColors.ink)
                        .frame(width: 32, height: 32)
                        .background(ALIColors.surface.opacity(0.9))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ALIColors.outline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Expand map"))
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastLabel(toast: toast)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Group {
                if canEdit {
                    Text("Tap a country to mark it as visited.")
                } else {
                    Text("Showing \(memberName(selectedMemberID))'s countries.")
                }
            }
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
        }
        .padding(12)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }

    private func visitedList(visitors: [String: Set<UUID>]) -> some View {
        let codes = visitors.keys.sorted { CountryInfo.name($0).localizedCompare(CountryInfo.name($1)) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Visited countries")
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            VStack(spacing: 0) {
                ForEach(Array(codes.enumerated()), id: \.element) { index, code in
                    HStack(spacing: 12) {
                        Text(CountryInfo.flag(code)).font(.system(size: 24))
                        Text(CountryInfo.name(code))
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if selectedMemberID == nil {
                            Text(names(of: visitors[code] ?? []))
                                .font(ALITypography.labelLarge)
                                .foregroundStyle(ALIColors.mutedInk)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < codes.count - 1 {
                        Divider().overlay(ALIColors.outline).padding(.leading, 52)
                    }
                }
            }
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
        }
    }

    private func memberName(_ id: UUID?) -> String {
        members.first { $0.id == id }?.name ?? ""
    }

    /// "Ana, Luis" (members in group order).
    private func names(of ids: Set<UUID>) -> String {
        members.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
    }

    // MARK: Actions

    private func toggle(_ code: String) {
        guard canEdit, let myID, let familyID = familySession.familyID else { return }
        let added = WorldMapActions.toggle(code: code, memberID: myID, familyID: familyID, visits: visits, modelContext: modelContext, dataSync: dataSync, source: "map")
        withAnimation(.easeOut(duration: 0.2)) { toast = Toast(code: code, added: added) }
        let shown = toast
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == shown { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        }
    }
}

/// "🇪🇸 Spain ✓" pill shown after tapping a country.
private struct ToastLabel: View {
    let toast: WorldMapScreen.Toast

    var body: some View {
        HStack(spacing: 6) {
            Text(CountryInfo.flag(toast.code))
            Text(CountryInfo.name(toast.code)).font(ALITypography.labelLarge.weight(.semibold))
            Image(systemName: toast.added ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(ALIColors.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(ALIColors.surface)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

/// Mark / unmark a country for a member, shared by the map and the picker.
enum WorldMapActions {
    /// Returns whether the country is now visited.
    @MainActor
    @discardableResult
    static func toggle(
        code: String, memberID: UUID, familyID: UUID, visits: [VisitedCountry],
        modelContext: ModelContext, dataSync: AppDataSyncCoordinator, source: String
    ) -> Bool {
        let id = VisitedCountry.id(for: memberID, code: code)
        if let existing = visits.first(where: { $0.id == id }) {
            modelContext.delete(existing)
            try? modelContext.save()
            dataSync.deleteVisitedCountry(id: id)
            Track.event("world_map_country_removed", ["source": source])
            return false
        }
        let visit = VisitedCountry(memberID: memberID, countryCode: code)
        modelContext.insert(visit)
        try? modelContext.save()
        dataSync.pushVisitedCountry(visit, familyID: familyID)
        Track.event("world_map_country_added", ["source": source, "country": code])
        return true
    }
}

/// The map full screen, with pinch to zoom and drag to move.
private struct WorldMapFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    let fill: (String) -> Double
    let canEdit: Bool
    let onTap: (String) -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let data = WorldMapData.shared
            let fitted = CGSize(width: proxy.size.width, height: proxy.size.width * data.size.height / data.size.width)
            ZStack {
                ALIColors.background.ignoresSafeArea()
                WorldMapCanvas(fill: fill, zoom: zoom)
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in zoom = min(max(lastZoom * value, 1), 12) }
                    .onEnded { _ in
                        lastZoom = zoom
                        clampOffset(fitted: fitted, container: proxy.size)
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in clampOffset(fitted: fitted, container: proxy.size) }
                    )
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    zoom = zoom > 1 ? 1 : 3
                    lastZoom = zoom
                    if zoom == 1 { offset = .zero; lastOffset = .zero }
                }
            }
            .onTapGesture { location in
                guard canEdit else { return }
                // Screen point → map coordinates (undo offset and zoom around the center).
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let local = CGPoint(
                    x: (location.x - center.x - offset.width) / zoom + fitted.width / 2,
                    y: (location.y - center.y - offset.height) / zoom + fitted.height / 2
                )
                let scale = data.size.width / fitted.width
                if let code = data.country(at: CGPoint(x: local.x * scale, y: local.y * scale)) { onTap(code) }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ALIColors.ink)
                    .frame(width: 40, height: 40)
                    .background(ALIColors.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ALIColors.outline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel(Text("Close"))
        }
        .overlay(alignment: .bottom) {
            Text(canEdit ? LocalizedStringKey("Pinch to zoom. Tap a country to mark it as visited.") : LocalizedStringKey("Pinch to zoom."))
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .padding(.bottom, 24)
        }
    }

    private func clampOffset(fitted: CGSize, container: CGSize) {
        let maxX = max(0, (fitted.width * zoom - container.width) / 2)
        let maxY = max(0, (fitted.height * zoom - container.height) / 2)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            offset = CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
        }
        lastOffset = offset
    }
}
