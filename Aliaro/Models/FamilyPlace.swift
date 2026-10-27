import SwiftUI
import SwiftData
import CoreLocation

/// A place saved by the family on the Places map (a restaurant they like,
/// a park for the kids, a hotel…). Shared with the whole group.
@Model
final class FamilyPlace {
    var id: UUID
    var name: String
    /// `PlaceCategory.rawValue`.
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
        category: PlaceCategory = .other,
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
        self.category = category.rawValue
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
