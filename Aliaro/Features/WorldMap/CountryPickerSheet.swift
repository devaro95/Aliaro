import SwiftUI
import SwiftData

/// Every country with a search field: tap one to mark it as visited (or
/// unmark it) for this member. Includes the tiny ones the map can't draw.
struct CountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query private var visits: [VisitedCountry]

    @State private var searchText = ""

    /// (code, localized name), sorted by name.
    private let countries: [(code: String, name: String)] = WorldMapData.shared.allCodes
        .map { ($0, CountryInfo.name($0)) }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

    private var myCodes: Set<String> {
        guard let myID = familySession.memberID else { return [] }
        return Set(visits.filter { $0.memberID == myID }.map(\.countryCode))
    }

    private var filtered: [(code: String, name: String)] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil || $0.code.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    var body: some View {
        trackedBody.trackScreen("world_map_picker")
    }

    @ViewBuilder
    private var trackedBody: some View {
        let mine = myCodes
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ALITextField(placeholder: "Search country…", text: $searchText)
                        .padding(.bottom, 12)

                    Group {
                        if mine.count == 1 { Text("1 country visited") } else { Text("\(mine.count) countries visited") }
                    }
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    ForEach(filtered, id: \.code) { country in
                        let isVisited = mine.contains(country.code)
                        Button {
                            toggle(country.code)
                        } label: {
                            HStack(spacing: 12) {
                                Text(CountryInfo.flag(country.code)).font(.system(size: 24))
                                Text(country.name)
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(ALIColors.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: isVisited ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isVisited ? ALIColors.worldMapAccent : ALIColors.outline)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(ALIColors.outline)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(ALIColors.background)
            .navigationTitle("Countries visited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: visits.count)
    }

    private func toggle(_ code: String) {
        guard let myID = familySession.memberID, let familyID = familySession.familyID else { return }
        WorldMapActions.toggle(
            code: code, memberID: myID, familyID: familyID, visits: visits,
            modelContext: modelContext, dataSync: dataSync, source: "list"
        )
    }
}
