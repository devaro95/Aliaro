import SwiftUI
import SwiftData
import CoreLocation

/// A place saved by the family on the Places map (a restaurant they like,
/// a park for the kids, a hotel…). Shared with the whole group.
@Model
final class FamilyPlace {
    var id: UUID
    var name: String
    /// `PlaceCategory.rawValue`, or the id of a `PlaceCustomCategory`.
    var category: String
    var latitude: Double
    var longitude: Double
    var address: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var createdByID: UUID?
    var createdByName: String?

    static let maxNameLength = 80
    static let maxNotesLength = 500

    var placeCategory: PlaceCategory { PlaceCategory(rawValue: category) ?? .other }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(
        id: UUID = UUID(),
        name: String,
        category: String = PlaceCategory.other.rawValue,
        latitude: Double,
        longitude: Double,
        address: String = "",
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}

/// Fixed place categories, each with its own color and icon so they're
/// easy to tell apart on the map. Raw values are stored in Supabase —
/// never rename them.
enum PlaceCategory: String, CaseIterable, Identifiable {
    case restaurant, cafe, nature, culture, shopping, leisure, travel, other

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .restaurant: return "Restaurants"
        case .cafe: return "Cafés & bars"
        case .nature: return "Parks & nature"
        case .culture: return "Culture"
        case .shopping: return "Shops"
        case .leisure: return "Fun & kids"
        case .travel: return "Hotels & trips"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .nature: return "leaf.fill"
        case .culture: return "building.columns.fill"
        case .shopping: return "bag.fill"
        case .leisure: return "ticket.fill"
        case .travel: return "bed.double.fill"
        case .other: return "mappin"
        }
    }

    /// Marker color: stronger than the app's pastels so pins stand out on the map.
    var color: Color {
        switch self {
        case .restaurant: return Color(hex: 0xF27A5E)
        case .cafe: return Color(hex: 0xB9825A)
        case .nature: return Color(hex: 0x4FB477)
        case .culture: return Color(hex: 0x8E7CC3)
        case .shopping: return Color(hex: 0xE86A9E)
        case .leisure: return Color(hex: 0xF2B33D)
        case .travel: return Color(hex: 0x4A9FD8)
        case .other: return Color(hex: 0x7C7488)
        }
    }
}

/// A place category created by the family (name, icon and color of their
/// choice). Places point to it by its id in `FamilyPlace.category`.
@Model
final class PlaceCustomCategory {
    var id: UUID
    var name: String
    /// SF Symbol name, one of `PlaceCategoryOptions.icons`.
    var icon: String
    /// Hex without "#", one of `PlaceCategoryOptions.colors`.
    var color: String
    var createdAt: Date
    var updatedAt: Date
    var createdByID: UUID?
    var createdByName: String?

    static let maxNameLength = 30

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        color: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}

/// Icons and colors to pick from when creating a category (same lists on Android).
enum PlaceCategoryOptions {
    static let icons: [String] = [
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill", "cart.fill",
        "bag.fill", "gift.fill", "leaf.fill", "tree.fill", "mountain.2.fill",
        "beach.umbrella.fill", "sun.max.fill", "building.columns.fill", "building.2.fill", "house.fill",
        "books.vertical.fill", "theatermasks.fill", "music.note", "film.fill", "gamecontroller.fill",
        "ticket.fill", "figure.walk", "figure.run", "bicycle", "sportscourt.fill",
        "dumbbell.fill", "figure.pool.swim", "pawprint.fill", "heart.fill", "star.fill",
        "cross.case.fill", "stethoscope", "graduationcap.fill", "briefcase.fill", "car.fill",
        "airplane", "bed.double.fill", "tent.fill", "camera.fill", "mappin",
    ]

    static let colors: [String] = [
        "F27A5E", "E05555", "E86A9E", "8E7CC3", "5C6BC0", "4A9FD8",
        "2BB3A7", "4FB477", "8BC34A", "F2B33D", "B9825A", "7C7488",
    ]
}

/// How a category looks (fixed or created by the family): what the screens use.
struct PlaceCategoryStyle: Identifiable, Equatable {
    /// Value stored in `FamilyPlace.category`.
    let id: String
    let builtin: PlaceCategory?
    let custom: PlaceCustomCategory?
    let icon: String
    let color: Color

    var title: Text {
        if let builtin { return Text(builtin.label) }
        return Text(verbatim: custom?.name ?? "")
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    init(_ builtin: PlaceCategory) {
        id = builtin.rawValue
        self.builtin = builtin
        custom = nil
        icon = builtin.systemImage
        color = builtin.color
    }

    init(_ custom: PlaceCustomCategory) {
        id = custom.id.uuidString
        builtin = nil
        self.custom = custom
        icon = custom.icon
        color = Color(hex: UInt32(custom.color, radix: 16) ?? 0x7C7488)
    }

    /// The style for a stored value; unknown (e.g. a deleted category) → "Other".
    static func resolve(_ raw: String, customs: [PlaceCustomCategory]) -> PlaceCategoryStyle {
        if let builtin = PlaceCategory(rawValue: raw) { return PlaceCategoryStyle(builtin) }
        if let custom = customs.first(where: { $0.id.uuidString == raw }) { return PlaceCategoryStyle(custom) }
        return PlaceCategoryStyle(.other)
    }

    /// Fixed categories ("Other" last) and then the family's, oldest first.
    static func all(customs: [PlaceCustomCategory]) -> [PlaceCategoryStyle] {
        let fixed = PlaceCategory.allCases.filter { $0 != .other }.map(PlaceCategoryStyle.init)
        let own = customs.sorted { $0.createdAt < $1.createdAt }.map(PlaceCategoryStyle.init)
        return fixed + own + [PlaceCategoryStyle(.other)]
    }
}
