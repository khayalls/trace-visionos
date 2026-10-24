// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TraceCore", platforms: [.macOS(.v14)], products: [.library(name: "TraceCore", targets: ["TraceCore"])], targets: [
    .target(name: "TraceCore", path: "TRACE", exclude: ["Tracking", "Scene", "UI", "TraceApp.swift", "StudioModel.swift", "Info.plist", "Assets.xcassets"], sources: ["Core", "Storage"], resources: [.copy("HandAssets")]),
    .testTarget(name: "TraceCoreTests", dependencies: ["TraceCore"], path: "Tests/TraceCoreTests")
])
