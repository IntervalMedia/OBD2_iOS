// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NissanDiagnostics", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "NissanCore", targets: ["NissanCore"])], targets: [.target(name: "NissanCore"), .target(name: "NissanTransport", dependencies: ["NissanCore"], path: "AppleApp", exclude: ["NissanDiagnosticsApp.swift"], sources: ["TCPTransport.swift"]), .testTarget(name: "NissanCoreTests", dependencies: ["NissanCore"]), .testTarget(name: "NissanTransportTests", dependencies: ["NissanCore", "NissanTransport"])])
