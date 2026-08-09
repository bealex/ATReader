// swift-tools-version: 6.3
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

// StyleRespace — a tiny, parser-aware post-formatter used by Scripts/format.sh.
//
// swift-format normalises collection literals to tight brackets (`[.foo]`), but the project code style
// wants interior spaces (`[ .foo ]`). swift-format has no option for that, and a regex rewrite can't tell a
// literal from a subscript or an array TYPE. So this tool parses the file with SwiftSyntax and re-inserts the
// interior spaces on single-line array/dictionary *literals* only — never touching subscripts, types,
// strings, or comments. It is a separate package so the swift-syntax dependency stays out of the engine.
let package = Package(
    name: "StyleRespace",
    platforms: [ .macOS(.v13) ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0")
    ],
    targets: [
        .executableTarget(
            name: "style-respace",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        )
    ]
)
