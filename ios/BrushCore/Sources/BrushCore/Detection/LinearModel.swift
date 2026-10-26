import Foundation

/// Logistic-regression head trained in Python (analysis/train.py).
public struct LinearModel: Codable {
    public let mean: [Double]
    public let scale: [Double]
    public let coef: [Double]
    public let intercept: Double

    public func predict(_ x: [Double]) -> Double {
        var z = intercept
        for i in 0..<coef.count {
            z += (x[i] - mean[i]) / scale[i] * coef[i]
        }
        return 1.0 / (1.0 + exp(-z))
    }
}

/// The two heads sharing the same features: brushing and running water.
public struct ModelHeads {
    public let brush: LinearModel
    public let water: LinearModel

    struct File: Codable {
        let feature_version: Int
        let heads: [String: LinearModel]
    }

    public static let featureVersion = 1

    public enum LoadError: Error { case missing(String), version(Int) }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.feature_version == ModelHeads.featureVersion else { throw LoadError.version(file.feature_version) }
        guard let b = file.heads["brush"] else { throw LoadError.missing("brush") }
        guard let w = file.heads["water"] else { throw LoadError.missing("water") }
        brush = b
        water = w
    }

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// The model shipped with the app (trained on real recordings).
    public static func bundled() throws -> ModelHeads {
        guard let url = Bundle.module.url(forResource: "brush_model", withExtension: "json") else {
            throw LoadError.missing("brush_model.json")
        }
        return try ModelHeads(url: url)
    }
}
