// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ArelFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArelFocus", targets: ["ArelFocus"]),
        .executable(name: "ArelFocusNativeBridge", targets: ["ArelFocusNativeBridge"])
    ],
    targets: [
        .executableTarget(
            name: "ArelFocus",
            path: "Sources/ArelFocus"
        ),
        .executableTarget(
            name: "ArelFocusNativeBridge",
            path: "Sources/ArelFocusNativeBridge"
        )
    ]
)
