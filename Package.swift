// swift-tools-version: 6.0
import PackageDescription

var packageDependencies: [Package.Dependency] = [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")]
var appDependencies: [Target.Dependency] = ["AfterglowCore"]
#if os(macOS)
packageDependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"))
appDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
#endif

let package = Package(
    name: "Afterglow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Afterglow", targets: ["Afterglow"]),
        .executable(name: "afterglow-lyrics", targets: ["AfterglowLyricsService"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(name: "AfterglowCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "Afterglow", dependencies: appDependencies, linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS])),
        ]),
        .executableTarget(name: "AfterglowLyricsService", dependencies: ["AfterglowCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["AfterglowCore"], path: "Tests/AfterglowCoreTests"),
    ]
)
