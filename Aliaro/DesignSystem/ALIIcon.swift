import SwiftUI

/// App-wide SVG icon set (Lucide, ISC) living in `Assets.xcassets/Icons`
/// as template vectors named `ali_<token>`.
///
/// Models keep their historical `emoji` field (it's the Supabase column name),
/// but it now stores an icon token such as `"cart"`. Rows written before the
/// switch still hold an emoji, so `token(for:)` maps those legacy values too.
enum ALIIcon {
    static let tag = "tag", cart = "cart", home = "home", bulb = "bulb", car = "car"
    static let dining = "dining", pill = "pill", film = "film", shopping = "shopping"
    static let book = "book", pet = "pet", plane = "plane", gift = "gift", laptop = "laptop"
    static let receipt = "receipt", gym = "gym", bookmark = "bookmark", coins = "coins"
    static let unknown = "unknown", party = "party", cake = "cake", beach = "beach"
    static let xmas = "xmas", health = "health", doctor = "doctor", sport = "sport"
    static let graduation = "graduation", heart = "heart", calendar = "calendar"
    static let school = "school", user = "user", sparkles = "sparkles", history = "history"
    static let wave = "wave", euro = "euro", search = "search", archive = "archive"
    static let cleaning = "cleaning", bell = "bell", check = "check"

    static let all: Set<String> = [
        tag, cart, home, bulb, car, dining, pill, film, shopping, book, pet, plane, gift,
        laptop, receipt, gym, bookmark, coins, unknown, party, cake, beach, xmas, health,
        doctor, sport, graduation, heart, calendar, school, user, sparkles, history, wave,
        euro, search, archive, cleaning, bell, check,
    ]

    /// Emoji stored before the SVG migration → icon token.
    private static let legacy: [String: String] = [
        "🏷": tag, "🛒": cart, "🏠": home, "🏡": home, "💡": bulb, "🚗": car, "🍽": dining,
        "💊": pill, "🎬": film, "🛍": shopping, "📚": book, "🐾": pet, "✈": plane, "🎁": gift,
        "💻": laptop, "🧾": receipt, "🏋": gym, "🔖": bookmark, "💰": coins, "❔": unknown,
        "🎉": party, "🎂": cake, "🏖": beach, "🎄": xmas, "🏥": health, "🦷": doctor,
        "⚽": sport, "🎓": graduation, "❤": heart, "📅": calendar, "🗓": calendar,
        "🏫": school, "🙂": user, "👤": user, "👩": user, "👨": user, "🧑": user, "👧": user,
        "✨": sparkles, "🕘": history, "👋": wave, "💶": euro, "🔍": search, "🗂": archive,
        "🧺": cleaning, "🔔": bell,
    ]

    /// Resolves a stored value (token or legacy emoji) to a known token.
    static func token(for value: String, fallback: String = tag) -> String {
        if all.contains(value) { return value }
        let stripped = value.unicodeScalars
            .filter { $0.value != 0xFE0F && !(0x1F3FB...0x1F3FF).contains($0.value) }
            .map(String.init).joined()
        return legacy[stripped] ?? fallback
    }

    static func assetName(for value: String, fallback: String = tag) -> String {
        "ali_" + token(for: value, fallback: fallback)
    }
}

/// Renders an `ALIIcon` token (or legacy emoji) as a tinted SVG.
struct ALIIconView: View {
    let icon: String
    var size: CGFloat = 22
    var color: Color = ALIColors.ink
    var fallback: String = ALIIcon.tag

    var body: some View {
        Image(ALIIcon.assetName(for: icon, fallback: fallback))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
