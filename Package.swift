// swift-tools-version: 5.9
import PackageDescription

// The app builds through Xcode/Theos; this package exercises its platform-neutral
// protocol and data code without requiring a connected vehicle or simulator.
let package = Package(
    name: "OBDMVP",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "NissanCore", targets: ["NissanCore"]),
        .library(name: "OBDCore", targets: ["OBDCore"])
    ],
    targets: [
        .target(name: "NissanCore", path: "Src/Services/NissanCore"),
        .target(
            name: "OBDCore",
            dependencies: ["NissanCore"],
            path: "Src",
            exclude: [
                "App", "ViewModels", "Views", "Networking/Bluetooth",
                "Services/NissanCore",
                "Services/OBDService.swift", "Services/LogStore.swift",
                "Services/NissanSessionService.swift"
            ],
            sources: [
                "Models", "Networking/AdapterResponseBuffer.swift", "Networking/OBDTransport.swift",
                "Networking/OBDCommandQueue.swift", "Networking/OBDTransporting.swift",
                "Services/OBDParser.swift", "Services/OBDCommandBuilder.swift",
                "Services/PersistenceStore.swift", "Services/CSVExporter.swift",
                "Utilities"
            ]
        ),
        .testTarget(name: "NissanCoreTests", dependencies: ["NissanCore"]),
        .testTarget(name: "OBDCoreTests", dependencies: ["OBDCore"])
    ]
)
