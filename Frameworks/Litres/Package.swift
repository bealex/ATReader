// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "Litres",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "Litres", targets: [ "Litres" ])
    ],
    targets: [
        .target(name: "Litres", swiftSettings: [ .swiftLanguageMode(.v6) ]),
        .testTarget(name: "LitresTests", dependencies: [ "Litres" ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
    ]
)
