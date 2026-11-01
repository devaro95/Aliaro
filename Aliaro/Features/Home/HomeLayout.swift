import SwiftUI

/// A section of the Home screen that can be moved (and, except the
/// features grid, hidden) from "Customize Home".
enum HomeBlock: String, CaseIterable, Identifiable {
    case today
    case board
    case features

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .today: return "Today"
        case .board: return "Board"
        case .features: return "All features"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .board: return "pin.fill"
        case .features: return "square.grid.2x2.fill"
        }
    }

    var accent: Color {
        switch self {
        case .today: return ALIColors.sun
        case .board: return ALIColors.boardAccent
        case .features: return ALIColors.primary
        }
    }

    /// The grid is the only way to reach features that aren't in the bottom
    /// bar, so it can be moved but never hidden.
    var canHide: Bool { self != .features }
}

/// This member's Home layout on this device (not synced, like the feature
/// order): the order of the blocks, which ones are hidden, and which
/// "Today" cards show and in what order.
@MainActor
final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()

    /// Features that can have a "Today" card, in their default order.
    static let todayTabs: [AppTab] = [.houseTasks, .familyCalendar, .weeklyMenu, .shoppingList, .reminders, .economia]

    @Published private(set) var blockOrder: [String]
    @Published private(set) var hiddenBlocks: Set<String>
    /// `AppTab.settingsKey`s. Empty = follow the features grid order.
    @Published private(set) var todayOrder: [String]
    @Published private(set) var hiddenTodayCards: Set<String>

    private enum Keys {
        static let blockOrder = "aliaro.home.blockOrder"
        static let hiddenBlocks = "aliaro.home.hiddenBlocks"
        static let todayOrder = "aliaro.home.todayOrder"
        static let hiddenTodayCards = "aliaro.home.hiddenTodayCards"
    }

    private let defaults = UserDefaults.standard

    private init() {
        blockOrder = defaults.stringArray(forKey: Keys.blockOrder) ?? []
        hiddenBlocks = Set(defaults.stringArray(forKey: Keys.hiddenBlocks) ?? [])
        todayOrder = defaults.stringArray(forKey: Keys.todayOrder) ?? []
        hiddenTodayCards = Set(defaults.stringArray(forKey: Keys.hiddenTodayCards) ?? [])
    }

    /// Every block in this member's order (unknown/new ones keep their
    /// canonical place after the rest).
    var orderedBlocks: [HomeBlock] {
        let rank = Dictionary(blockOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return HomeBlock.allCases.enumerated()
            .sorted { (rank[$0.element.rawValue] ?? Int.max, $0.offset) < (rank[$1.element.rawValue] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    func isHidden(_ block: HomeBlock) -> Bool { block.canHide && hiddenBlocks.contains(block.rawValue) }

    /// "Today" features in this member's order: their own order if they set
    /// one, else the features grid order.
    func orderedTodayTabs(featureOrder: [AppTab]) -> [AppTab] {
        let base = featureOrder.filter { Self.todayTabs.contains($0) }
        guard !todayOrder.isEmpty else { return base }
        return AppTab.ordered(base, by: todayOrder)
    }

    func isHidden(todayCard tab: AppTab) -> Bool { hiddenTodayCards.contains(tab.settingsKey) }

    var isCustomized: Bool {
        !blockOrder.isEmpty || !hiddenBlocks.isEmpty || !todayOrder.isEmpty || !hiddenTodayCards.isEmpty
    }

    // MARK: Changes

    func setBlockOrder(_ blocks: [HomeBlock]) {
        blockOrder = blocks.map(\.rawValue)
        defaults.set(blockOrder, forKey: Keys.blockOrder)
    }

    func setHidden(_ block: HomeBlock, _ hidden: Bool) {
        guard block.canHide else { return }
        if hidden { hiddenBlocks.insert(block.rawValue) } else { hiddenBlocks.remove(block.rawValue) }
        defaults.set(Array(hiddenBlocks), forKey: Keys.hiddenBlocks)
    }

    func setTodayOrder(_ tabs: [AppTab]) {
        todayOrder = tabs.map(\.settingsKey)
        defaults.set(todayOrder, forKey: Keys.todayOrder)
    }

    func setHidden(todayCard tab: AppTab, _ hidden: Bool) {
        if hidden { hiddenTodayCards.insert(tab.settingsKey) } else { hiddenTodayCards.remove(tab.settingsKey) }
        defaults.set(Array(hiddenTodayCards), forKey: Keys.hiddenTodayCards)
    }

    /// Back to the default Home (the features grid order is reset separately).
    func reset() {
        blockOrder = []
        hiddenBlocks = []
        todayOrder = []
        hiddenTodayCards = []
        [Keys.blockOrder, Keys.hiddenBlocks, Keys.todayOrder, Keys.hiddenTodayCards].forEach(defaults.removeObject(forKey:))
    }
}
