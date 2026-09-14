// swift-tools-version: 6.3
// The shared component library for the Swift app: standard SwiftUI patterns
// carrying Bluesky identity through DesignSystem.
//
// Two targets, on purpose:
//   - UIComponentsCore: no UI framework. The pure decisions behind the views -
//     button matrix resolution, embed variant dispatch, feed-item view data,
//     moderation surface resolution, image-loader protocol. Built and tested on
//     Linux (`swift build && swift test`), like DesignSystemCore.
//   - UIComponents: SwiftUI. Post/PostFeedItem, Button styles, avatars/banners,
//     list states, toasts, and the internal ComponentGallery. Verified on the
//     macOS CI (ios-selfhosted) only.
// This package is a UI package, so MainActor-default isolation is allowed here
// (the Linux boundary rule applies to the 🌐 packages, not to this one).
import PackageDescription

let package = Package(
  name: "UIComponents",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "UIComponents", targets: ["UIComponents"]),
    .library(name: "UIComponentsCore", targets: ["UIComponentsCore"]),
  ],
  dependencies: [
    .package(path: "../DesignSystem"),
    .package(path: "../DesignTokens"),
    .package(path: "../Moderation"),
    .package(path: "../RichText"),
  ],
  targets: [
    .target(
      name: "UIComponentsCore",
      dependencies: [
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "RichText", package: "RichText"),
      ],
      path: "Sources/UIComponentsCore",
      swiftSettings: [.defaultIsolation(nil)]
    ),
    .target(
      name: "UIComponents",
      dependencies: [
        "UIComponentsCore",
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "RichText", package: "RichText"),
      ],
      path: "Sources/UIComponents"
    ),
    .testTarget(
      name: "UIComponentsCoreTests",
      dependencies: ["UIComponentsCore"],
      path: "Tests/UIComponentsCoreTests",
      swiftSettings: [.defaultIsolation(nil)]
    ),
  ]
)
