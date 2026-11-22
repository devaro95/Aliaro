import SwiftUI
import SwiftData

/// "World map" feature: a globe you spin with the finger. Each member marks
/// the countries they've visited (searching them with +) and they fill in.
/// "Everyone" shows the whole family in one color; each member's chip shows
/// just theirs, in their own color (long press your chip to change yours).
/// The list button opens every visited country, with its own member filter.
struct WorldMapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var familyService: FamilyService

    @Query private var visits: [VisitedCountry]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    /// `nil` = everyone.
    @State private var selectedMemberID: UUID?
    @State private var showPicker = false
    @State private var showList = false
    @State private var showColorPicker = false
    /// Number shown in the stats: counts up the first time, then jumps straight to new values.
    @State private var shownCount: Double = 0
    @State private var countedUp = false

    private var myID: UUID? { familySession.memberID }

    var body: some View {
        trackedBody.trackScreen("world_map")
    }

    @ViewBuilder
    private var trackedBody: some View {
        let visitors = WorldMapVisitors.byCountry(visits, member: selectedMemberID)
        let selectedColor = members.first(where: { $0.id == selectedMemberID }).map { MapColors.color(of: $0, in: members) } ?? MapColors.everyone
        VStack(alignment: .leading, spacing: 16) {
            ALITopBar(title: "World map", accent: ALIColors.worldMapAccent) {
                HStack(spacing: 10) {
                    if !visits.isEmpty {
                        Button {
                            Track.event("world_map_list_open")
                            showList = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 40, height: 40)
                                .background(ALIColors.surfaceVariant)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Visited countries")
                    }
                    if myID != nil {
                        ALIFloatingButton(accent: ALIColors.worldMapAccent) {
                            Track.event("world_map_picker_open")
                            showPicker = true
                        }
                        .scaleEffect(0.72)
                    }
                }
            }
            .padding(.horizontal, 20)

            WorldMapMemberChips(members: members, selectedID: selectedMemberID, myID: myID, onLongPressMe: { showColorPicker = true }) { id in
                if let id { Track.event("world_map_filter_member", ["is_me": id == myID]) }
                selectedMemberID = selectedMemberID == id ? nil : id
            }

            statsCard(count: shownCount)
                .padding(.horizontal, 20)
                .onAppear { updateCount(visitors.count) }
                .onChange(of: visitors.count) { _, new in updateCount(new) }

            WorldGlobe(
                colorFor: { code in (visitors[code]?.isEmpty ?? true) ? nil : selectedColor },
                filter: selectedMemberID?.uuidString,
                years: WorldMapVisitors.years(visits, member: selectedMemberID)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALIColors.background)
        .sheet(isPresented: $showPicker) {
            CountryPickerSheet()
        }
        .sheet(isPresented: $showList) {
            VisitedCountriesSheet(visits: visits, members: members, initialMemberID: selectedMemberID)
        }
        .sheet(isPresented: $showColorPicker) {
            if let me = members.first(where: { $0.id == myID }) {
                MapColorSheet(selection: MapColors.hex(of: me, in: members)) { hex in
                    Task { try? await familyService.updateMyMapColor(hex, modelContext: modelContext) }
                }
            }
        }
    }

    private func updateCount(_ count: Int) {
        if !countedUp && count > 0 {
            countedUp = true
            withAnimation(.easeOut(duration: 0.9)) { shownCount = Double(count) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shownCount = Double(count) }
        }
    }

    private func statsCard(count shown: Double) -> some View {
        let count = Int(shown.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            CountingText(value: shown)
                .font(ALITypography.displayMedium)
                .foregroundStyle(ALIColors.ink)
            Text(count == 1 ? LocalizedStringKey("country") : LocalizedStringKey("countries"))
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            PercentText(value: shown)
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.mutedInk)
        }
    }
}

/// A number that counts up digit by digit when its value is animated.
private struct CountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(verbatim: "\(Int(value.rounded()))") }
}

/// "12% of the world", following the animated count.
private struct PercentText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        let percent = min(100, Int((value / Double(CountryInfo.worldCount) * 100).rounded()))
        Text("\(percent)% of the world")
    }
}

/// World map colors: one for "Everyone", and the defaults members get until they pick their own.
enum MapColors {
    static let everyone = ALIPalette.coral
    static let defaults = ["FF8FA3", "5DADE2", "F8B259", "6BCB77", "A78BFA", "4ECDC4", "F67280", "F4A261"]

    /// "RRGGBB" of a member: their own pick, else a default by their position in the group.
    static func hex(of member: FamilyMember, in members: [FamilyMember]) -> String {
        member.mapColor ?? defaults[max(members.firstIndex(where: { $0.id == member.id }) ?? 0, 0) % defaults.count]
    }

    static func color(of member: FamilyMember, in members: [FamilyMember]) -> Color {
        ALIItemColors.color(hex(of: member, in: members), fallback: everyone)
    }
}

/// Picks your own World map color (the app's 30 tag colors).
private struct MapColorSheet: View {
    @State var selection: String?
    let onChange: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ALIColorPickerCard(selection: $selection).padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Color")
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
        }
        .presentationDetents([.medium])
        .onChange(of: selection) { _, new in onChange(new) }
    }
}

enum WorldMapVisitors {
    /// Code → year of the visit, for one member (none for everyone: each may have gone in a different year).
    static func years(_ visits: [VisitedCountry], member: UUID?) -> [String: Int] {
        guard let member else { return [:] }
        return visits.reduce(into: [:]) { result, visit in
            if visit.memberID == member, let year = visit.year { result[visit.countryCode] = year }
        }
    }

    /// Code → ids of the members who've been there (`member` nil = everyone).
    static func byCountry(_ visits: [VisitedCountry], member: UUID?) -> [String: Set<UUID>] {
        visits.filter { member == nil || $0.memberID == member }
            .reduce(into: [:]) { $0[$1.countryCode, default: []].insert($1.memberID) }
    }
}

/// Everyone / one chip per member.
struct WorldMapMemberChips: View {
    let members: [FamilyMember]
    let selectedID: UUID?
    var myID: UUID? = nil
    /// Long press on your own chip (changes your color).
    var onLongPressMe: (() -> Void)? = nil
    let onSelect: (UUID?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "Everyone"), color: MapColors.everyone, showsDot: false, isSelected: selectedID == nil) { onSelect(nil) }
                ForEach(members) { member in
                    chip(
                        title: member.name, color: MapColors.color(of: member, in: members), showsDot: true,
                        isSelected: selectedID == member.id,
                        onLongPress: member.id == myID ? onLongPressMe : nil
                    ) { onSelect(member.id) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// A capsule in the member's map color: a dot, or filled when selected.
    private func chip(
        title: String, color: Color, showsDot: Bool, isSelected: Bool,
        onLongPress: (() -> Void)? = nil, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            if showsDot && !isSelected {
                Circle().fill(color).frame(width: 10, height: 10)
            }
            Text(title).font(ALITypography.labelLarge).lineLimit(1)
        }
        .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? color : ALIColors.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 0.4) { onLongPress?() }
        .accessibilityAddTraits(.isButton)
    }
}

/// Every visited country, with its own member filter (starts on the screen's).
struct VisitedCountriesSheet: View {
    let visits: [VisitedCountry]
    let members: [FamilyMember]
    @State private var memberID: UUID?
    @State private var yearTarget: VisitYearTarget?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    init(visits: [VisitedCountry], members: [FamilyMember], initialMemberID: UUID?) {
        self.visits = visits
        self.members = members
        _memberID = State(initialValue: initialMemberID)
    }

    var body: some View {
        let visitors = WorldMapVisitors.byCountry(visits, member: memberID)
        let codes = visitors.keys.sorted { CountryInfo.name($0).localizedCompare(CountryInfo.name($1)) == .orderedAscending }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    WorldMapMemberChips(members: members, selectedID: memberID) { id in
                        memberID = memberID == id ? nil : id
                    }

                    Group {
                        if codes.count == 1 { Text("1 country visited") } else { Text("\(codes.count) countries visited") }
                    }
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.horizontal, 20)

                    if codes.contains(where: { myVisit($0) != nil }) {
                        Text("Tap your countries to add the year you went.")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .padding(.horizontal, 20)
                    }

                    if !codes.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(codes.enumerated()), id: \.element) { index, code in
                                HStack(spacing: 12) {
                                    Text(CountryInfo.flag(code)).font(.system(size: 24))
                                    Text(CountryInfo.name(code))
                                        .font(ALITypography.bodyLarge)
                                        .foregroundStyle(ALIColors.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(verbatim: detail(of: code, visitors: visitors[code] ?? []))
                                        .font(ALITypography.labelLarge)
                                        .foregroundStyle(ALIColors.mutedInk)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard myVisit(code) != nil else { return }
                                    yearTarget = VisitYearTarget(code: code)
                                }
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
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }
            .background(ALIColors.background)
            .navigationTitle("Visited countries")
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $yearTarget) { target in
            if let visit = myVisit(target.code), let familyID = familySession.familyID {
                VisitYearSheet(code: target.code, initialYear: visit.year) { year in
                    WorldMapActions.setYear(year, of: visit, familyID: familyID, modelContext: modelContext, dataSync: dataSync)
                }
            }
        }
        .trackScreen("world_map_list")
    }

    /// My own visit to a country (the only one whose year I can set).
    private func myVisit(_ code: String) -> VisitedCountry? {
        guard let myID = familySession.memberID else { return nil }
        return visits.first { $0.memberID == myID && $0.countryCode == code }
    }

    private func year(of member: UUID, in code: String) -> Int? {
        visits.first { $0.memberID == member && $0.countryCode == code }?.year
    }

    /// Everyone: "Ana (2019), Luis" (members in group order). One member: their year.
    private func detail(of code: String, visitors ids: Set<UUID>) -> String {
        if let memberID { return year(of: memberID, in: code).map { "\($0)" } ?? "" }
        return members.filter { ids.contains($0.id) }
            .map { member in year(of: member.id, in: code).map { "\(member.name) (\($0))" } ?? member.name }
            .joined(separator: ", ")
    }
}

/// Mark / unmark a country for a member, shared by the map and the picker.
enum WorldMapActions {
    /// Last country marked on this device and when: only that one spins into view on the globe.
    private static var lastMarked: (code: String, at: Date)?

    /// Whether `code` was just marked here (not by another member, arriving in real time).
    static func markedHereRecently(_ code: String) -> Bool {
        guard let lastMarked else { return false }
        return lastMarked.code == code && Date().timeIntervalSince(lastMarked.at) < 5
    }

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
        lastMarked = (code, Date())
        let visit = VisitedCountry(memberID: memberID, countryCode: code)
        modelContext.insert(visit)
        try? modelContext.save()
        dataSync.pushVisitedCountry(visit, familyID: familyID)
        Track.event("world_map_country_added", ["source": source, "country": code])
        return true
    }

    /// Sets (or clears, with nil) the year of a visit.
    @MainActor
    static func setYear(
        _ year: Int?, of visit: VisitedCountry, familyID: UUID,
        modelContext: ModelContext, dataSync: AppDataSyncCoordinator
    ) {
        guard visit.year != year else { return }
        visit.year = year
        try? modelContext.save()
        dataSync.pushVisitedCountry(visit, familyID: familyID)
        Track.event("world_map_year_set", ["has_year": year != nil])
    }
}

/// A country whose visit year is being set.
struct VisitYearTarget: Identifiable {
    let code: String
    var id: String { code }
}

/// Year wheel for a visited country (from this year back to 1940).
/// The secondary button skips it, or removes a year already set.
struct VisitYearSheet: View {
    let code: String
    let initialYear: Int?
    let onSave: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    private static let thisYear = Calendar.current.component(.year, from: .now)
    private static let years = Array((1940...thisYear).reversed())

    init(code: String, initialYear: Int?, onSave: @escaping (Int?) -> Void) {
        self.code = code
        self.initialYear = initialYear
        self.onSave = onSave
        _year = State(initialValue: initialYear ?? Self.thisYear)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("When did you go?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                Picker("Year", selection: $year) {
                    ForEach(Self.years, id: \.self) { value in
                        Text(verbatim: "\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    ALISecondaryButton(text: initialYear == nil ? "Skip" : "Remove year") {
                        if initialYear != nil { onSave(nil) }
                        dismiss()
                    }
                    ALIPrimaryButton(text: "Save", accent: ALIColors.worldMapAccent) {
                        onSave(year)
                        dismiss()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .background(ALIColors.background)
            .navigationTitle(Text(verbatim: "\(CountryInfo.flag(code)) \(CountryInfo.name(code))"))
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
        }
        .presentationDetents([.height(380)])
        .trackScreen("world_map_year")
    }
}
