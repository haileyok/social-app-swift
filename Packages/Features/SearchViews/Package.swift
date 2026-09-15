// swift-tools-version: 6.3
// The SwiftUI half of the Search feature: the search screen (field, suggestions
// and history, post/actor/starter-pack results under tabs) and the Explore
// screen (trending, suggested accounts, discover feeds, starter packs).
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. Every
// decision lives in the SearchLogic package next door - the state machine, the
// Explore assembly, the history actor - and nothing here re-derives a rule it
// already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "SearchViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "SearchViews", targets: ["SearchViews"])
  ],
  dependencies: [
    .package(path: "../Search"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../RichText"),
    .package(path: "../../UIComponents"),
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "SearchViews",
      dependencies: [
        .product(name: "SearchLogic", package: "Search"),
        // SearchLogic's default arguments and public model types reference these
        // types, so the iOS product-framework link closure needs the direct
        // dependencies even where this module only names the types indirectly.
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/SearchViews"
    )
  ]
)
