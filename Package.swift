// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mapofagents",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .executable(name: "mapofagents", targets: ["MapofAgentsApp"]),
        .library(name: "MapofAgentsCore", targets: ["MapofAgentsCore"]),
        .library(name: "MapofAgentsUI", targets: ["MapofAgentsUI"]),
    ],
    targets: [
        .target(
            name: "MapofAgentsCore"
        ),
        .target(
            name: "MapofAgentsUI",
            dependencies: ["MapofAgentsCore"]
        ),
        .executableTarget(
            name: "MapofAgentsApp",
            dependencies: ["MapofAgentsCore", "MapofAgentsUI"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "MapofAgentsCoreTests",
            dependencies: ["MapofAgentsCore"]
        ),
        .testTarget(
            name: "MapofAgentsUITests",
            dependencies: ["MapofAgentsCore", "MapofAgentsUI"]
        ),
        .testTarget(
            name: "MapofAgentsAppTests",
            dependencies: ["MapofAgentsApp"]
        ),
    ]
)
