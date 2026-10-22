import SwiftUI
import SwiftData
import UIKit

/// Fixed recipe categories; a recipe can be in several. Raw values are
/// stored in Supabase — never rename them.
enum RecipeCategory: String, CaseIterable, Identifiable {
    case favorites, quick, breakfast, main, drink, dessert

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .favorites: return "Favorites"
        case .quick: return "Quick"
        case .breakfast: return "Breakfast"
        case .main: return "Mains"
        case .drink: return "Drinks"
        case .dessert: return "Desserts"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites: return "heart.fill"
        case .quick: return "bolt.fill"
        case .breakfast: return "cup.and.saucer.fill"
        case .main: return "fork.knife"
        case .drink: return "wineglass.fill"
        case .dessert: return "birthday.cake.fill"
        }
    }
}

extension Recipe {
    /// Prep + cooking time, or nil when neither is set.
    var totalMinutes: Int? {
        let total = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return total > 0 ? total : nil
    }

    /// "45 min · 4 servings" (total time, only when set).
    var metaLabel: String {
        var parts: [String] = []
        if let totalMinutes { parts.append(RecipeFormatting.duration(totalMinutes)) }
        parts.append(servings == 1 ? String(localized: "1 serving") : String(localized: "\(servings) servings"))
        return parts.joined(separator: " · ")
    }

    var image: UIImage? { photoData.flatMap(UIImage.init(data:)) }
}

enum RecipeFormatting {
    /// "200 g", "1,5 kg", "to taste" — or nil when there's nothing to show.
    static func amount(of ingredient: RecipeIngredient) -> String? {
        let unit = ingredient.ingredientUnit
        if unit == .toTaste { return unit?.symbol }
        guard let quantity = ingredient.quantity, quantity > 0 else { return nil }
        let number = quantityText(quantity)
        guard let unit else { return number }
        return "\(number) \(unit.symbol)"
    }

    /// Common kitchen fractions, shown as "1/2" instead of "0,5".
    private static let fractions: [(value: Double, text: String)] = [
        (1.0 / 8, "1/8"), (1.0 / 4, "1/4"), (1.0 / 3, "1/3"), (1.0 / 2, "1/2"), (2.0 / 3, "2/3"), (3.0 / 4, "3/4"),
    ]

    private static let unicodeFractions: [Character: String] = [
        "⅛": "1/8", "¼": "1/4", "⅓": "1/3", "½": "1/2", "⅔": "2/3", "¾": "3/4",
    ]

    /// Parses what the user typed in the amount field: "200", "1,5",
    /// "1.5", "1/2", "1 1/2" or "½".
    static func quantity(from text: String) -> Double? {
        var normalized = ""
        for character in text.trimmed {
            if let fraction = unicodeFractions[character] {
                normalized += " \(fraction)"
            } else {
                normalized.append(character == "," ? "." : character)
            }
        }
        let parts = normalized.split(separator: " ")
        guard !parts.isEmpty, parts.count <= 2 else { return nil }
        var total = 0.0
        for part in parts {
            if part.contains("/") {
                let pieces = part.split(separator: "/")
                guard pieces.count == 2, let numerator = Double(pieces[0]),
                      let denominator = Double(pieces[1]), denominator > 0 else { return nil }
                total += numerator / denominator
            } else {
                guard let value = Double(part) else { return nil }
                total += value
            }
        }
        return total > 0 ? total : nil
    }

    /// Amount as text: whole numbers plain ("2"), common fractions as
    /// fractions ("1/2", "1 1/2"), anything else as a short decimal ("0,15").
    static func quantityText(_ quantity: Double?) -> String {
        guard let quantity, quantity > 0 else { return "" }
        let whole = quantity.rounded(.down)
        let remainder = quantity - whole
        let wholeText = whole > 0 ? Int(whole).formatted(.number.grouping(.never)) : ""
        if remainder < 0.001 { return wholeText }
        if let fraction = fractions.first(where: { abs($0.value - remainder) < 0.01 }) {
            return wholeText.isEmpty ? fraction.text : "\(wholeText) \(fraction.text)"
        }
        return quantity.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// "45 min" / "1 h" / "1 h 30 min".
    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return String(localized: "\(minutes) min") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }

    /// Downscales and JPEG-encodes a picked photo for upload (max 1280 px side).
    static func compressedJPEG(from data: Data, maxSide: CGFloat = 1280) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// Keeps each recipe's twin `Dish` (same id) in the menu catalog, so any
/// recipe can be chosen for lunch/dinner in the weekly menu.
enum RecipeDishLink {
    /// Creates the twin dish, or renames it (and the menu entries that
    /// copied its name) when the recipe name changed.
    @MainActor
    static func sync(_ recipe: Recipe, modelContext: ModelContext, dataSync: AppDataSyncCoordinator, familyID: UUID?) {
        let recipeID = recipe.id
        let name = recipe.name
        let dishDescriptor = FetchDescriptor<Dish>(predicate: #Predicate { $0.id == recipeID })
        if let dish = try? modelContext.fetch(dishDescriptor).first {
            guard dish.name != name else { return }
            dish.name = name
            if let familyID { dataSync.pushDish(dish, familyID: familyID) }
            let entriesDescriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.dishID == recipeID })
            for entry in (try? modelContext.fetch(entriesDescriptor)) ?? [] {
                entry.dishName = name
                entry.updatedAt = .now
                if let familyID { dataSync.pushMealPlanEntry(entry, familyID: familyID) }
            }
        } else {
            let dish = Dish(id: recipeID, name: name)
            modelContext.insert(dish)
            if let familyID { dataSync.pushDish(dish, familyID: familyID) }
        }
    }

    /// Removes the twin dish from the catalog. Menu entries keep their
    /// copied name, like with any deleted dish.
    @MainActor
    static func remove(recipeID: UUID, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        let descriptor = FetchDescriptor<Dish>(predicate: #Predicate { $0.id == recipeID })
        if let dish = try? modelContext.fetch(descriptor).first {
            modelContext.delete(dish)
        }
        dataSync.deleteDish(id: recipeID)
    }
}

/// Square photo (or category placeholder) for a recipe.
struct RecipeThumbnail: View {
    let recipe: Recipe
    var size: CGFloat = 64
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let image = recipe.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    ALIColors.recipesAccent.opacity(0.35)
                    Image(systemName: recipe.recipeCategories.first(where: { $0 != .favorites && $0 != .quick })?.systemImage ?? "fork.knife")
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(ALIColors.onAccent.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Selectable capsule used for category filters and pickers.
struct RecipeChip: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                }
                Text(title).font(ALITypography.labelLarge)
            }
            .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? ALIColors.recipesAccent : ALIColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Lays out chips left to right, wrapping onto new lines when they don't fit.
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
