import AppIntents

/// Siri phrases that work out of the box, with no setup in the Shortcuts
/// app. Apple requires every phrase to include the app name. English
/// phrases here are the keys; the Spanish ones are in
/// `AppShortcuts.xcstrings` (Siri reads that table, not Localizable).
/// Only one `AppShortcutsProvider` per app: new Siri actions go here too.
struct AliaroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayDinnerIntent(),
            phrases: [
                "What's for dinner in \(.applicationName)?",
                "\(.applicationName), what's for dinner today?",
                "What's for dinner today in \(.applicationName)?"
            ],
            shortTitle: "Today's dinner",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: TodayLunchIntent(),
            phrases: [
                "What's for lunch in \(.applicationName)?",
                "\(.applicationName), what's for lunch today?",
                "What's for lunch today in \(.applicationName)?"
            ],
            shortTitle: "Today's lunch",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: TodayMenuIntent(),
            phrases: [
                "What's on the menu in \(.applicationName)?",
                "What's on today's menu in \(.applicationName)?",
                "\(.applicationName), what's on the menu today?"
            ],
            shortTitle: "Today's menu",
            systemImageName: "fork.knife"
        )
    }
}
