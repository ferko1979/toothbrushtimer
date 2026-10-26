import Foundation

/// Water-waste estimate (water_report.py). Sources are listed in the Python module.
public struct WaterLocale: Equatable, Codable {
    public var id: String
    public var flowLPerMin: Double
    public var pricePerLitre: Double
    public var currency: String
    public var dailyUsePerPersonL: Double
    public var glassL: Double
    public var glassName: String
    public var imperial: Bool

    public static let litresPerGallon = 3.785411784
    public static let hu = WaterLocale(id: "hu", flowLPerMin: 8.0, pricePerLitre: 0.653, currency: "Ft",
                                       dailyUsePerPersonL: 105, glassL: 0.25, glassName: "pohár (2,5 dl)", imperial: false)
    public static let us = WaterLocale(id: "us", flowLPerMin: 2.2 * litresPerGallon,
                                       pricePerLitre: 0.0125 / litresPerGallon, currency: "$",
                                       dailyUsePerPersonL: 82 * litresPerGallon, glassL: 0.2366,
                                       glassName: "8 oz glass", imperial: true)

    public static func named(_ id: String) -> WaterLocale { id == "us" ? .us : .hu }

    public func withFlow(_ lPerMin: Double?) -> WaterLocale {
        guard let f = lPerMin else { return self }
        var c = self
        c.flowLPerMin = f
        return c
    }
}

public struct WaterReport: Equatable {
    public let seconds: Double
    public let litres: Double
    public let gallons: Double
    public let cost: Double
    public let glasses: Double
    public let pctDailyUse: Double
    public let pctDrinking: Double
    public let litresPerYear: Double
    public let costPerYear: Double

    public init(seconds: Double, locale: WaterLocale = .hu) {
        self.seconds = seconds
        litres = seconds / 60 * locale.flowLPerMin
        gallons = litres / WaterLocale.litresPerGallon
        cost = litres * locale.pricePerLitre
        glasses = litres / locale.glassL
        pctDailyUse = 100 * litres / locale.dailyUsePerPersonL
        pctDrinking = 100 * litres / 2.0
        litresPerYear = litres * 2 * 365
        costPerYear = litresPerYear * locale.pricePerLitre
    }
}

/// End-of-session water message (Hungarian or US English).
public func waterMessage(brushingS: Double, waterRunningS: Double, locale: WaterLocale) -> (title: String, lines: [String], wasted: Bool) {
    let wasted = waterRunningS >= 5
    if locale.imperial {
        if wasted {
            let r = WaterReport(seconds: waterRunningS, locale: locale)
            return ("⚠️ Water waste: the tap ran for \(Int(waterRunningS)) s", [
                String(format: "About %.1f gallons (%.1f L, ~%.0f glasses), about $%.3f.", r.gallons, r.litres, r.glasses, r.cost),
                String(format: "That's ~%.0f%% of an average American's daily home water use.", r.pctDailyUse),
                String(format: "Twice a day for a year: ~%.0f gallons (~$%.0f).", r.litresPerYear / WaterLocale.litresPerGallon, r.costPerYear),
                "Tip: turn the tap off after wetting your brush and back on only to rinse.",
            ], true)
        }
        let r = WaterReport(seconds: brushingS, locale: locale)
        return ("💧 Nice, you kept the tap off!", [
            String(format: "A running tap would have wasted ~%.1f gallons (~%.0f gallons a year).", r.gallons, r.litresPerYear / WaterLocale.litresPerGallon),
        ], false)
    }
    if wasted {
        let r = WaterReport(seconds: waterRunningS, locale: locale)
        return ("⚠️ Vízpazarlás: a csap \(Int(waterRunningS)) másodpercig folyt", [
            "Ez kb. \(Formatting.hu(r.litres)) liter víz (~\(Formatting.hu(r.glasses, digits: 0)) \(locale.glassName)), kb. \(Formatting.hu(r.cost)) \(locale.currency).",
            "Egy ember napi vízfogyasztásának kb. \(Formatting.hu(r.pctDailyUse, digits: 0))%-a, a napi ajánlott ivóvíz \(Formatting.hu(r.pctDrinking, digits: 0))%-a.",
            "Ha minden reggel és este így mosol fogat: évente kb. \(Formatting.hu(r.litresPerYear / 1000)) m³ (~\(Formatting.hu(r.costPerYear, digits: 0)) \(locale.currency)).",
            "Tipp: a fogkefe benedvesítése után zárd el a csapot, és csak öblítéskor nyisd meg újra.",
        ], true)
    }
    let r = WaterReport(seconds: brushingS, locale: locale)
    return ("💧 Szép munka, elzártad a csapot!", [
        "Ha folyt volna, kb. \(Formatting.hu(r.litres)) liter (~\(Formatting.hu(r.glasses, digits: 0)) pohár) víz folyt volna el feleslegesen, évente kb. \(Formatting.hu(r.litresPerYear / 1000)) m³.",
    ], false)
}
