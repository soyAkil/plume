// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
        // Automatic updates for the distributed app.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // llama.cpp, for local summaries: the official prebuilt framework, so no Xcode is needed.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11461/llama-b11461-xcframework.zip",
            checksum: "d33fba3588cabdf6378fb67871fe6dfe7a5ae49ce7d510c3def91d8a4b8e3d6e"
        ),
        .target(
            name: "PlumeKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), "llama"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Plume",
            dependencies: ["PlumeKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is placed in the app's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PlumeKitTests",
            dependencies: ["PlumeKit", "llama"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlumeTests",
            dependencies: ["Plume", "PlumeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
