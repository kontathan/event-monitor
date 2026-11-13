// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventMonitor",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EventMonitor", targets: ["EventMonitor"])
    ],
    targets: [
        // Plattformunabhängige Logik: Modelle, Quellen, Parser, Ausschlussregeln.
        .target(name: "EventMonitorCore"),
        // Die SwiftUI-Oberfläche.
        .executableTarget(name: "EventMonitor", dependencies: ["EventMonitorCore"]),
        .testTarget(name: "EventMonitorCoreTests", dependencies: ["EventMonitorCore"])
    ]
)
