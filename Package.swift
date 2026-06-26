// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spotoast",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Spotoast",
            path: "Sources/Spotoast",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
