import Foundation

/// A drink found by barcode, already converted to the app's units.
nonisolated struct ScannedProduct: Equatable, Sendable {
    var barcode: String
    var name: String
    var category: DrinkCategory
    /// Size of the whole package (bottle, can, keg), if known.
    var packageVolumeML: Double?
    /// What one logged drink should default to.
    var suggestedVolumeML: Double
    var alcoholPercent: Double?
    var nutrientsPer100ml: Nutrients
    /// Open Food Facts gave values per 100 g; they are used as per 100 ml (close for drinks).
    var valuesWerePer100g: Bool
    /// Set for powders (electrolytes, protein): grams per scoop. Then nutrients are
    /// per 100 g of powder and `suggestedVolumeML` is the liquid to mix with.
    var powderGrams: Double? = nil
}

/// Parsing of Open Food Facts product data (https://world.openfoodfacts.org).
/// Pure functions, so they can be tested with saved responses.
///
/// API docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
/// Nutrient fields ending in `_100g` are in grams (energy in kcal, alcohol in % vol).
nonisolated enum OpenFoodFacts {
    static let fields = "code,product_name,brands,quantity,product_quantity,product_quantity_unit,categories_tags,nutriments,nutrition_data_per,serving_size,serving_quantity"

    /// EAN-8, UPC-A (12), EAN-13 and GTIN-14: digits only.
    static func isValidBarcode(_ code: String) -> Bool {
        [8, 12, 13, 14].contains(code.count) && code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber)
    }

    static func url(for barcode: String) -> URL? {
        guard isValidBarcode(barcode) else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")
    }

    enum ParseError: Error { case invalidJSON }

    /// Returns `nil` when the product isn't in the database.
    static func parse(_ data: Data, barcode: String) throws -> ScannedProduct? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard number(root["status"]) == 1, let product = root["product"] as? [String: Any] else {
            return nil
        }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        var nutrients = Nutrients()
        for nutrient in Nutrient.allCases {
            if let grams = number(nutriments["\(key(for: nutrient))_100g"]) {
                nutrients[nutrient] = convert(grams, to: nutrient)
            }
        }
        let alcohol = number(nutriments["alcohol_100g"]).flatMap { $0 > 0 ? $0 : nil }

        let tags = product["categories_tags"] as? [String] ?? []
        let name = [product["product_name"] as? String, product["brands"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Scanned drink"

        // Powders: nutrients are per 100 g of powder; one drink is a scoop plus liquid.
        if let powder = powderCategory(name: name, tags: tags,
                                       unit: product["product_quantity_unit"] as? String ?? (product["quantity"] as? String)) {
            let scoop = scoopGrams(servingSize: product["serving_size"] as? String,
                                   servingQuantity: number(product["serving_quantity"])) ?? powder.typicalPowderGrams
            return ScannedProduct(
                barcode: barcode, name: name, category: powder,
                packageVolumeML: nil, suggestedVolumeML: powder.typicalLiquidML,
                alcoholPercent: nil, nutrientsPer100ml: nutrients,
                valuesWerePer100g: true, powderGrams: scoop
            )
        }

        var category = guessCategory(tags: tags, alcoholPercent: alcohol)
        // A ready-to-drink protein shake is often tagged as milk.
        if [.milk, .other, .sportsDrink, .softDrink].contains(category),
           ["protein", "whey", "eiweiss", "eiweiß"].contains(where: name.lowercased().contains) {
            category = .proteinDrink
        }
        let package = volumeML(quantity: product["quantity"] as? String,
                               productQuantity: number(product["product_quantity"]),
                               unit: product["product_quantity_unit"] as? String)

        return ScannedProduct(
            barcode: barcode,
            name: name,
            category: category,
            packageVolumeML: package,
            suggestedVolumeML: suggestedVolume(package: package, category: category),
            alcoholPercent: category.isAlcoholic ? alcohol : nil,
            nutrientsPer100ml: nutrients,
            valuesWerePer100g: (product["nutrition_data_per"] as? String) == "100g"
        )
    }

    /// Open Food Facts field name (without `_100g`) for each nutrient.
    static func key(for nutrient: Nutrient) -> String {
        switch nutrient {
        case .caffeine: "caffeine"
        case .energy: "energy-kcal"
        case .protein: "proteins"
        case .carbohydrates: "carbohydrates"
        case .sugar: "sugars"
        case .fiber: "fiber"
        case .fatTotal: "fat"
        case .fatSaturated: "saturated-fat"
        case .fatMonounsaturated: "monounsaturated-fat"
        case .fatPolyunsaturated: "polyunsaturated-fat"
        case .cholesterol: "cholesterol"
        case .sodium: "sodium"
        case .potassium: "potassium"
        case .calcium: "calcium"
        case .magnesium: "magnesium"
        case .iron: "iron"
        case .zinc: "zinc"
        case .phosphorus: "phosphorus"
        case .chloride: "chloride"
        case .copper: "copper"
        case .manganese: "manganese"
        case .selenium: "selenium"
        case .chromium: "chromium"
        case .molybdenum: "molybdenum"
        case .iodine: "iodine"
        case .vitaminA: "vitamin-a"
        case .vitaminB6: "vitamin-b6"
        case .vitaminB12: "vitamin-b12"
        case .vitaminC: "vitamin-c"
        case .vitaminD: "vitamin-d"
        case .vitaminE: "vitamin-e"
        case .vitaminK: "vitamin-k"
        case .thiamin: "vitamin-b1"
        case .riboflavin: "vitamin-b2"
        case .niacin: "vitamin-pp"
        case .folate: "vitamin-b9"
        case .biotin: "biotin"
        case .pantothenicAcid: "pantothenic-acid"
        }
    }

    /// `_100g` values are grams (energy is kcal); convert to the app's unit.
    static func convert(_ value: Double, to nutrient: Nutrient) -> Double {
        switch nutrient.unit {
        case "mg": value * 1_000
        case "µg": value * 1_000_000
        default: value  // g and kcal
        }
    }

    /// Package size in ml from the structured quantity, or parsed from text like "33 cl" or "0.5l".
    /// Grams are treated as millilitres (drinks are close to water).
    static func volumeML(quantity: String?, productQuantity: Double?, unit: String?) -> Double? {
        if let productQuantity, productQuantity > 0, let factor = unitFactor(unit) {
            return productQuantity * factor
        }
        guard let quantity else { return nil }
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(ml|cl|dl|l|g)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: quantity, range: NSRange(quantity.startIndex..., in: quantity)),
              let numberRange = Range(match.range(at: 1), in: quantity),
              let unitRange = Range(match.range(at: 2), in: quantity),
              let value = Double(quantity[numberRange].replacingOccurrences(of: ",", with: ".")),
              let factor = unitFactor(String(quantity[unitRange]))
        else { return nil }
        return value * factor
    }

    private static func unitFactor(_ unit: String?) -> Double? {
        switch unit?.lowercased() {
        case "ml", "g": 1
        case "cl": 10
        case "dl": 100
        case "l", "kg": 1000
        default: nil
        }
    }

    /// Default amount for one logged drink: the package if it's a single serving
    /// (up to 1 l), otherwise a typical glass.
    static func suggestedVolume(package: Double?, category: DrinkCategory) -> Double {
        if let package, package > 0, package <= 1000 { return package }
        return typicalServingML(category)
    }

    static func typicalServingML(_ category: DrinkCategory) -> Double {
        switch category {
        case .beer: 330
        case .wine: 150
        case .spirits: 40
        case .cocktail: 200
        default: 250
        }
    }

    static func guessCategory(tags: [String], alcoholPercent: Double?) -> DrinkCategory {
        let tags = Set(tags)
        func has(_ any: String...) -> Bool { any.contains { tags.contains("en:\($0)") } }

        if has("beers") { return .beer }
        if has("wines", "sparkling-wines") { return .wine }
        if has("cocktails") { return .cocktail }
        if has("spirits", "distilled-beverages", "liqueurs") { return .spirits }
        if has("energy-drinks") { return .energyDrink }
        if tags.contains(where: { $0.contains("protein") }) { return .proteinDrink }
        if has("coffees", "coffee-drinks", "iced-coffees") { return .coffee }
        if has("teas", "iced-teas", "tea-based-beverages") { return .tea }
        if has("sports-drinks") { return .sportsDrink }
        if has("milks", "dairy-drinks", "milk-drinks") { return .milk }
        if has("fruit-juices", "juices", "nectars") { return .juice }
        if has("waters", "mineral-waters", "spring-waters") {
            return has("carbonated-waters", "sparkling-waters") ? .sparklingWater : .water
        }
        if has("sodas", "soft-drinks", "carbonated-soft-drinks") { return .softDrink }
        if let alcoholPercent, alcoholPercent >= 0.5 {
            return alcoholPercent < 8 ? .beer : (alcoholPercent < 18 ? .wine : .spirits)
        }
        return .other
    }

    /// Detects powders from the name and categories (English and German words,
    /// since many Swiss products are labelled in German). Sold by weight, not volume.
    static func powderCategory(name: String, tags: [String], unit: String?) -> DrinkCategory? {
        let text = ([name] + tags).joined(separator: " ").lowercased()
        let soldByWeight = unit.map { $0.lowercased().contains("g") } ?? false
        let isPowder = text.contains("powder") || text.contains("pulver") || soldByWeight
        guard isPowder else { return nil }
        if ["protein", "whey", "casein", "eiweiss", "eiweiß"].contains(where: text.contains) { return .proteinShake }
        if ["electrolyt", "elektrolyt", "hydration", "isoton", "rehydrat"].contains(where: text.contains) { return .electrolytes }
        return nil
    }

    /// Grams per scoop from a serving size like "8 g" or "1 scoop (30 g)".
    static func scoopGrams(servingSize: String?, servingQuantity: Double?) -> Double? {
        guard let servingSize, servingSize.lowercased().contains("g") else { return nil }
        if let servingQuantity, servingQuantity > 0 { return servingQuantity }
        let pattern = #"(\d+(?:[.,]\d+)?)\s*g\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: servingSize, range: NSRange(servingSize.startIndex..., in: servingSize)),
              let range = Range(match.range(at: 1), in: servingSize) else { return nil }
        return Double(servingSize[range].replacingOccurrences(of: ",", with: "."))
    }

    /// Numbers sometimes arrive as strings.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }
}

/// Looks up barcodes on Open Food Facts. Only used when the user scans.
enum ProductLookup {
    enum LookupError: LocalizedError {
        case invalidBarcode
        case network

        var errorDescription: String? {
            switch self {
            case .invalidBarcode: "That doesn't look like a product barcode."
            case .network: "Couldn't reach Open Food Facts. Check your internet connection."
            }
        }
    }

    static func fetch(barcode: String) async throws -> ScannedProduct? {
        guard let url = OpenFoodFacts.url(for: barcode) else { throw LookupError.invalidBarcode }
        var request = URLRequest(url: url, timeoutInterval: 10)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("BeWaterMyFriend/0.1 (https://github.com/NotSchebs/BeWaterMyFriend)",
                         forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LookupError.network
        }
        do {
            return try OpenFoodFacts.parse(data, barcode: barcode)
        } catch {
            throw LookupError.network  // e.g. an HTML "temporarily unavailable" page
        }
    }
}
