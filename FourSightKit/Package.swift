// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FourSightKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "FourSightKit", targets: ["Protocol", "ThreatEngine", "Perception", "Links"]),
    ],
    targets: [
        .target(name: "Protocol"),
        .target(name: "ThreatEngine", dependencies: ["Protocol"]),
        .target(name: "Perception", dependencies: ["Protocol"]),
        .target(name: "Links", dependencies: ["Protocol"]),
        // XCTest is absent from Command Line Tools; `swift run Checks` covers the same cases.
        .executableTarget(name: "Checks", dependencies: ["Protocol", "ThreatEngine", "Perception"]),
        .executableTarget(name: "ReplayBoxes", dependencies: ["Protocol", "Perception"]),
        .testTarget(name: "ProtocolTests", dependencies: ["Protocol"]),
        .testTarget(name: "ThreatEngineTests", dependencies: ["ThreatEngine", "Protocol"]),
        .testTarget(name: "PerceptionTests", dependencies: ["Perception", "Protocol"]),
    ]
)
