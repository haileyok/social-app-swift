// swift-tools-version: 6.3
// The Home feed screens: the SwiftUI layer over HomeFeedLogic.
//
// One target, on purpose: this package is a *Views package, so it is Mac-only
// (the Linux boundary rule skips `*Views` directories entirely) and every file
// in it imports SwiftUI. The pure decisions it renders - which slice shows a
// repost line, what the segmented switcher labels are, how a page state maps to
// a list state - live behind small helpers in the same target rather than a
// separate Core target, because nothing here needs to run on Linux. The logic
// package (`Packages/Features/HomeFeed`) is the Linux-verified half.
import PackageDescription

let package = Package(
  name: "HomeFeedViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "HomeFeedViews", targets: ["HomeFeedViews"])
  ],
  dependencies: [
    .package(path: "../../DesignSystem"),
    .package(path: "../../UIComponents"),
    .package(path: "../../RichText"),
    .package(path: "../HomeFeed"),
    .package(path: "../../Moderation"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Domain"),
    .package(path: "../../QueryStore"),
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "HomeFeedViews",
      dependencies: [
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "HomeFeedLogic", package: "HomeFeed"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/HomeFeedViews"
    )
  ]
)
