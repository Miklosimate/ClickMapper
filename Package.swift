// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ClickMapper", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "ClickDiagnostic", swiftSettings: [.swiftLanguageMode(.v5)])
])
