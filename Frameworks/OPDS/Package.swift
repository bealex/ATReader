// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "OPDS",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "OPDS", targets: [ "OPDS" ])
    ],
    targets: [
        .target(name: "OPDS", swiftSettings: [ .swiftLanguageMode(.v6) ]),
        .testTarget(name: "OPDSTests", dependencies: [ "OPDS" ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
    ]
)
