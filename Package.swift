// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CherryTools",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CherryTools", targets: ["CherryTools"])],
    targets: [
        .target(name: "CProcessMetrics", path: "Sources/CProcessMetrics", publicHeadersPath: "include"),
        .executableTarget(name: "CherryTools", dependencies: ["CProcessMetrics"], path: "Sources/CherryTools")
    ],
    swiftLanguageModes: [.v5]
)
