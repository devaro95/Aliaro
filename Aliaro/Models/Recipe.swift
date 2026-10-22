import SwiftUI
import SwiftData

/// A family recipe: name, categories (several allowed), ingredients (name + quantity + unit),
/// how to make it (one step per line), servings, prep time and an optional photo.
///
/// A recipe is also a dish of the weekly menu: it always has a catalog
/// `Dish` with the **same id** (see `RecipeDishLink`), so choosing it for
/// lunch/dinner needs nothing special and a `MealPlanEntry.dishID` can
/// point back to the recipe.
///
/// The photo lives in Supabase Storage (`recipe-photos` bucket) at
/// `photoPath`; `photoData` is the local cached copy.
@Model
final class Recipe {
    var id: UUID
    var name: String
    /// `RecipeCategory.rawValue`s — a recipe can be in several.
    var categories: [String]
    var ingredients: [RecipeIngredient]
    var steps: String
    var servings: Int
    var prepMinutes: Int?
    var cookMinutes: Int?
    var photoPath: String?
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date
    var updatedAt: Date
    var createdByID: UUID?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        name: String,
        categories: [String] = [],
        ingredients: [RecipeIngredient] = [],
        steps: String = "",
        servings: Int = 2,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        photoPath: String? = nil,
        photoData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.ingredients = ingredients
        self.steps = steps
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.photoPath = photoPath
        self.photoData = photoData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }

    /// Known categories of this recipe, in canonical order.
    var recipeCategories: [RecipeCategory] {
        RecipeCategory.allCases.filter { categories.contains($0.rawValue) }
    }
}

/// One ingredient of a recipe. Stored as JSON (`recipes.ingredients` is
/// jsonb) — `unit` is kept as a raw string so an unknown value from a
/// newer app version never breaks decoding.
struct RecipeIngredient: Codable, Hashable {
    var name: String
    var quantity: Double?
    /// `IngredientUnit.rawValue`.
    var unit: String?

    init(name: String, quantity: Double? = nil, unit: IngredientUnit? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit?.rawValue
    }

    var ingredientUnit: IngredientUnit? { unit.flatMap(IngredientUnit.init(rawValue:)) }
}

/// Units for an ingredient's amount. Raw values are stored — never rename them.
enum IngredientUnit: String, CaseIterable, Identifiable {
    case grams = "g", kilograms = "kg", milliliters = "ml", liters = "l"
    case units = "unit", tablespoon = "tbsp", teaspoon = "tsp", cup = "cup", pinch = "pinch"
    case toTaste = "to_taste"

    var id: String { rawValue }

    /// Name shown in the unit picker.
    var label: LocalizedStringKey {
        switch self {
        case .grams: return "Grams (g)"
        case .kilograms: return "Kilograms (kg)"
        case .milliliters: return "Millilitres (ml)"
        case .liters: return "Litres (l)"
        case .units: return "Units"
        case .tablespoon: return "Tablespoons"
        case .teaspoon: return "Teaspoons"
        case .cup: return "Cups"
        case .pinch: return "Pinch"
        case .toTaste: return "To taste"
        }
    }

    /// Short form shown next to the amount ("200 g", "2 tbsp").
    var symbol: String {
        switch self {
        case .grams: return "g"
        case .kilograms: return "kg"
        case .milliliters: return "ml"
        case .liters: return "l"
        case .units: return String(localized: "pcs")
        case .tablespoon: return String(localized: "tbsp")
        case .teaspoon: return String(localized: "tsp")
        case .cup: return String(localized: "cup")
        case .pinch: return String(localized: "pinch")
        case .toTaste: return String(localized: "to taste")
        }
    }

    /// "To taste" has no amount.
    var needsQuantity: Bool { self != .toTaste }
}
