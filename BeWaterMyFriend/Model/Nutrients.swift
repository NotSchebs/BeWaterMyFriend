import Foundation

/// Nutrient values **per 100 ml**, one optional field per nutrient.
/// `nil` means "unknown", which is different from 0.
/// The set and units follow Apple Health's dietary data types so that Phase 2
/// can write them without conversion. Fluid volume itself lives on the entry.
nonisolated struct Nutrients: Codable, Hashable, Sendable {
    // Energy and macronutrients
    var energyKcal: Double?
    var proteinG: Double?
    var carbohydratesG: Double?
    var sugarG: Double?
    var fiberG: Double?
    var fatTotalG: Double?
    var fatSaturatedG: Double?
    var fatMonounsaturatedG: Double?
    var fatPolyunsaturatedG: Double?
    var cholesterolMg: Double?

    // Minerals
    var sodiumMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var magnesiumMg: Double?
    var ironMg: Double?
    var zincMg: Double?
    var phosphorusMg: Double?
    var chlorideMg: Double?
    var copperMg: Double?
    var manganeseMg: Double?
    var seleniumMcg: Double?
    var chromiumMcg: Double?
    var molybdenumMcg: Double?
    var iodineMcg: Double?

    // Vitamins
    var vitaminAMcg: Double?
    var vitaminB6Mg: Double?
    var vitaminB12Mcg: Double?
    var vitaminCMg: Double?
    var vitaminDMcg: Double?
    var vitaminEMg: Double?
    var vitaminKMcg: Double?
    var thiaminMg: Double?
    var riboflavinMg: Double?
    var niacinMg: Double?
    var folateMcg: Double?
    var biotinMcg: Double?
    var pantothenicAcidMg: Double?

    // Stimulants
    var caffeineMg: Double?

    init() {}

    subscript(nutrient: Nutrient) -> Double? {
        get { self[keyPath: nutrient.keyPath] }
        set { self[keyPath: nutrient.keyPath] = newValue }
    }

    /// True when no nutrient is known.
    var isEmpty: Bool {
        Nutrient.allCases.allSatisfy { self[$0] == nil }
    }
}

/// Describes each field of `Nutrients` so views and calculations can loop over
/// all nutrients instead of naming 38 fields by hand.
nonisolated enum Nutrient: String, CaseIterable, Identifiable, Sendable {
    case caffeine
    case energy, protein, carbohydrates, sugar, fiber
    case fatTotal, fatSaturated, fatMonounsaturated, fatPolyunsaturated, cholesterol
    case sodium, potassium, calcium, magnesium, iron, zinc, phosphorus, chloride
    case copper, manganese, selenium, chromium, molybdenum, iodine
    case vitaminA, vitaminB6, vitaminB12, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, folate, biotin, pantothenicAcid

    var id: String { rawValue }

    enum Group: String, CaseIterable, Sendable {
        case stimulants = "Caffeine"
        case macros = "Energy & macronutrients"
        case minerals = "Minerals"
        case vitamins = "Vitamins"
    }

    var group: Group {
        switch self {
        case .caffeine: .stimulants
        case .energy, .protein, .carbohydrates, .sugar, .fiber,
             .fatTotal, .fatSaturated, .fatMonounsaturated, .fatPolyunsaturated, .cholesterol: .macros
        case .sodium, .potassium, .calcium, .magnesium, .iron, .zinc, .phosphorus, .chloride,
             .copper, .manganese, .selenium, .chromium, .molybdenum, .iodine: .minerals
        default: .vitamins
        }
    }

    var unit: String {
        switch self {
        case .energy: "kcal"
        case .protein, .carbohydrates, .sugar, .fiber,
             .fatTotal, .fatSaturated, .fatMonounsaturated, .fatPolyunsaturated: "g"
        case .selenium, .chromium, .molybdenum, .iodine,
             .vitaminA, .vitaminB12, .vitaminD, .vitaminK, .folate, .biotin: "µg"
        default: "mg"
        }
    }

    var displayName: String {
        switch self {
        case .caffeine: "Caffeine"
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .sugar: "Sugar"
        case .fiber: "Fibre"
        case .fatTotal: "Fat"
        case .fatSaturated: "Saturated fat"
        case .fatMonounsaturated: "Monounsaturated fat"
        case .fatPolyunsaturated: "Polyunsaturated fat"
        case .cholesterol: "Cholesterol"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .magnesium: "Magnesium"
        case .iron: "Iron"
        case .zinc: "Zinc"
        case .phosphorus: "Phosphorus"
        case .chloride: "Chloride"
        case .copper: "Copper"
        case .manganese: "Manganese"
        case .selenium: "Selenium"
        case .chromium: "Chromium"
        case .molybdenum: "Molybdenum"
        case .iodine: "Iodine"
        case .vitaminA: "Vitamin A"
        case .vitaminB6: "Vitamin B6"
        case .vitaminB12: "Vitamin B12"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .thiamin: "Thiamin (B1)"
        case .riboflavin: "Riboflavin (B2)"
        case .niacin: "Niacin (B3)"
        case .folate: "Folate"
        case .biotin: "Biotin"
        case .pantothenicAcid: "Pantothenic acid"
        }
    }

    var keyPath: WritableKeyPath<Nutrients, Double?> {
        switch self {
        case .caffeine: \.caffeineMg
        case .energy: \.energyKcal
        case .protein: \.proteinG
        case .carbohydrates: \.carbohydratesG
        case .sugar: \.sugarG
        case .fiber: \.fiberG
        case .fatTotal: \.fatTotalG
        case .fatSaturated: \.fatSaturatedG
        case .fatMonounsaturated: \.fatMonounsaturatedG
        case .fatPolyunsaturated: \.fatPolyunsaturatedG
        case .cholesterol: \.cholesterolMg
        case .sodium: \.sodiumMg
        case .potassium: \.potassiumMg
        case .calcium: \.calciumMg
        case .magnesium: \.magnesiumMg
        case .iron: \.ironMg
        case .zinc: \.zincMg
        case .phosphorus: \.phosphorusMg
        case .chloride: \.chlorideMg
        case .copper: \.copperMg
        case .manganese: \.manganeseMg
        case .selenium: \.seleniumMcg
        case .chromium: \.chromiumMcg
        case .molybdenum: \.molybdenumMcg
        case .iodine: \.iodineMcg
        case .vitaminA: \.vitaminAMcg
        case .vitaminB6: \.vitaminB6Mg
        case .vitaminB12: \.vitaminB12Mcg
        case .vitaminC: \.vitaminCMg
        case .vitaminD: \.vitaminDMcg
        case .vitaminE: \.vitaminEMg
        case .vitaminK: \.vitaminKMcg
        case .thiamin: \.thiaminMg
        case .riboflavin: \.riboflavinMg
        case .niacin: \.niacinMg
        case .folate: \.folateMcg
        case .biotin: \.biotinMcg
        case .pantothenicAcid: \.pantothenicAcidMg
        }
    }
}
