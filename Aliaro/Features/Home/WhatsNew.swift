import SwiftUI

/// "What's new" shown once after updating the app, over the main tabs,
/// with what this release adds. People who install the app now (they
/// create or join a group on this version) don't see it: there's nothing
/// "new" for them.
///
/// For a new release: bump `release` and change `items`. The debug menu
/// can show it again any time.
@MainActor
final class WhatsNew: ObservableObject {
    static let shared = WhatsNew()

    /// Release this content belongs to (not the build number, so Dev builds show it too).
    static let release = "1.3.0"

    @Published var isPresented = false

    private static let seenKey = "aliaro.whatsNew.seenRelease"
    private let defaults = UserDefaults.standard

    /// Main tabs on screen: show it if this device hasn't seen this release's yet.
    func showIfNeeded() {
        guard defaults.string(forKey: Self.seenKey) != Self.release else { return }
        markSeen()
        Track.event("whats_new_shown", ["screen": "app_update", "release": Self.release])
        // A beat so it lands after the tabs appear.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            isPresented = true
        }
    }

    /// Group created or joined on this version: nothing to announce to them.
    func markSeen() {
        defaults.set(Self.release, forKey: Self.seenKey)
    }

    /// Debug menu: show it now (after the debug sheet closes).
    func debugShow() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            isPresented = true
        }
    }

    /// Every dot a different color.
    static let items: [ALIWhatsNewItem] = [
        ALIWhatsNewItem(
            systemImage: "slider.horizontal.3", title: "Home your way",
            text: "With the button next to your avatar, reorder or hide the Home sections and choose which “Today” cards you see.",
            color: ALIPalette.periwinkle
        ),
        ALIWhatsNewItem(
            systemImage: "calendar", title: "A new calendar",
            text: "We got the calendar colors wrong: they weren't the best way to organize your events. Now there are categories with your own colors, event names right in the month and each event's details with a tap.",
            color: ALIColors.familyAccent
        ),
        ALIWhatsNewItem(
            systemImage: "list.bullet.clipboard.fill", title: "Private lists, and lists for everything",
            text: "Create private lists only you can see. And lists for anything (shopping, pharmacy, gifts…) with quantities.",
            color: ALIColors.shoppingAccent
        ),
        ALIWhatsNewItem(
            systemImage: "wifi", title: "Family Wi-Fi",
            text: "Save your networks and show the password or a QR so guests connect in a second.",
            color: ALIColors.wifiAccent
        ),
        ALIWhatsNewItem(
            systemImage: "bell.badge.fill", title: "Alerts for events and tasks",
            text: "Get up to 2 alerts before an event or a task: 5 minutes, 1 hour, 1 day…",
            color: ALIColors.houseTasksAccent
        ),
        ALIWhatsNewItem(
            systemImage: "link", title: "Links in recipes",
            text: "Save where a recipe comes from (a website, a video…) and give each link a name.",
            color: ALIColors.recipesAccent
        ),
        ALIWhatsNewItem(
            systemImage: "character.bubble.fill", title: "Everything in your language",
            text: "We've fixed several translation mistakes: finance categories, the shopping list and other texts now show up properly.",
            color: ALIColors.economiaAccent
        ),
        ALIWhatsNewItem(
            systemImage: "exclamationmark.bubble.fill", title: "Send us bugs and ideas",
            text: "A new section to tell us about bugs or suggest improvements. Find it by tapping your avatar at the top right of Home.",
            color: ALIColors.peopleAccent
        ),
    ]
}

/// The sheet with this release's news.
struct WhatsNewSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    /// "New in Aliaro" with the logo's "Aliaro" (salmon-dot "i").
    private var title: Text {
        let size = ALIWhatsNewSheet.bigTitleSize
        let wordmark = Text(AliaroWordmark.inlineImage(size: size, colorScheme: colorScheme))
            .baselineOffset(AliaroWordmark.inlineBaselineOffset(size: size))
        return Text("New in \(wordmark)")
    }

    /// Closing line, also with the logo's "Aliaro".
    private var closing: Text {
        let size: CGFloat = 15
        let wordmark = Text(AliaroWordmark.inlineImage(size: size, colorScheme: colorScheme))
            .baselineOffset(AliaroWordmark.inlineBaselineOffset(size: size))
        return Text("We work every day to make \(wordmark) better.")
    }

    var body: some View {
        ALIWhatsNewSheet(
            title: "New in Aliaro",
            accent: ALIColors.primary,
            items: WhatsNew.items,
            titleText: title,
            showsBadge: false,
            closing: closing,
            showsColors: false,
            timeline: true
        )
        .trackScreen("whats_new_update")
    }
}
