// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeOSShellCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeOSShellCore", targets: ["MeOSShellCore"])],
    targets: [
        .target(
            name: "MeOSShellCore",
            path: "MeOS",
            exclude: [
                "App/MeOSApp.swift",
                "DesignSystem",
                "Game",
                "Resources",
                "Views"
            ],
            sources: [
                "Models/AppModels.swift",
                "Models/LaboratoryWorld.swift",
                "Simulation/SimulationModels.swift",
                "Simulation/SimulationEngine.swift",
                "Missions/MissionModels.swift",
                "Missions/MissionEngine.swift",
                "App/ShellStore.swift",
                "App/AppModel.swift"
            ]
        ),
        .testTarget(
            name: "MeOSShellCoreTests",
            dependencies: ["MeOSShellCore"],
            path: "MeOSTests",
            exclude: ["LaboratoryScenePerformanceTests.swift"]
        )
    ]
)

