// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrushCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "BrushCore", targets: ["BrushCore"]),
    ],
    targets: [
        .target(
            name: "BrushCore",
            resources: [.copy("Resources/brush_model.json")]
        ),
        .testTarget(
            name: "BrushCoreTests",
            dependencies: ["BrushCore"],
            resources: [.copy("Golden")]
        ),
    ]
)
