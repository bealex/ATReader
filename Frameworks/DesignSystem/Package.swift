// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [ .iOS("27.0"), .macOS(.v15) ],
    products: [
        .library(name: "DesignSystem", targets: [ "DesignSystem" ])
    ],
    targets: [
        .target(name: "DesignSystem", resources: [ .process("Resources") ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: [ "DesignSystem" ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        ),
    ]
)
