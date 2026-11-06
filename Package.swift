// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FaceLook",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FaceLook", targets: ["FaceLook"])
    ],
    targets: [
        .executableTarget(
            name: "FaceLook",
            path: "Sources/FaceLook",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "FaceLookTests",
            dependencies: ["FaceLook"],
            path: "Tests/FaceLookTests"
        ),
    ]
)

