// swift-tools-version: 6.3
// The thread screens: one scrolling list of post rows, the anchor highlighted,
// reply connectors drawn from the flattened thread's connector data, tombstones
// for unavailable branches, and "load more" rows wired to the window model.
//
// Mac-only, on purpose. This package imports SwiftUI, so the Linux CI skips it:
// `linux.yml` excludes any feature directory whose name ends in `Views` from
// both the test matrix and the boundary lint, and the iOS workflows
// (`ios-selfhosted.yml`, `ios.yml`) filter on `Packages/Features/**`, so a push
// touching this package builds it on the Mac. The logic lives in the sibling
// `PostThread` package (`PostThreadLogic`), which is Linux-testable.
import PackageDescription

let package = Package(
  name: "PostThreadViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "PostThreadViews", targets: ["PostThreadViews"])
  ],
  dependencies: [
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../RichText"),
    .package(path: "../../UIComponents"),
    .package(path: "../PostThread"),
    // The generated lexicon types express their formats in the vendored
    // runtime's `FormatString`, and the fixtures construct those directly, so
    // the runtime is a direct dependency rather than a transitive one.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "PostThreadViews",
      dependencies: [
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "PostThreadLogic", package: "PostThread"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/PostThreadViews"
    )
  ]
)
