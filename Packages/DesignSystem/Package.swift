// swift-tools-version: 6.3
// The first UI package in the repo: SwiftUI wiring over the DesignTokens data.
//
// Two targets, on purpose:
//   - DesignSystemCore: no UI framework. Hex parsing, weight mapping, breakpoint
//     math, shadow geometry. Built and tested on Linux (`swift build && swift test`).
//   - DesignSystem: SwiftUI. Theme environment, colors, typography, modifiers,
//     the TokenGallery demo. Verified on macOS CI (ios-selfhosted) only.
// This package is a UI package, so MainActor-default isolation is allowed here
// (the Linux boundary rule applies to the 🌐 packages, not to this one).
import PackageDescription

let package = Package(
  name: "DesignSystem",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "DesignSystemCore", targets: ["DesignSystemCore"]),
  ],
  dependencies: [
    .package(path: "../DesignTokens")
  ],
  targets: [
    .target(
      name: "DesignSystemCore",
      dependencies: [.product(name: "DesignTokens", package: "DesignTokens")],
      path: "Sources/DesignSystemCore",
      swiftSettings: [.defaultIsolation(nil)]
    ),
    .target(
      name: "DesignSystem",
      dependencies: [
        "DesignSystemCore",
        .product(name: "DesignTokens", package: "DesignTokens"),
      ],
      path: "Sources/DesignSystem",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "DesignSystemCoreTests",
      dependencies: ["DesignSystemCore"],
      path: "Tests/DesignSystemCoreTests",
      swiftSettings: [.defaultIsolation(nil)]
    ),
  ]
)
