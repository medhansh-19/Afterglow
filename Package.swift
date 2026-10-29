// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Afterglow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Afterglow", targets: ["Afterglow"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "AfterglowCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "Afterglow", dependencies: ["AfterglowCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["AfterglowCore"], path: "Tests/AfterglowCoreTests"),
    ]
)
