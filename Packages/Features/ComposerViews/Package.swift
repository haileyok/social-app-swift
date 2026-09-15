// swift-tools-version: 6.3
// The SwiftUI half of the Composer feature: the post composer screen (text
// editor with facet feedback, character counter, image/video attach rows,
// reply and quote context, link card, self-labels, threadgate), its sheets,
// and the fixture surface the debug entry point drives.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and boundary-lint
// does not scan them, because they import SwiftUI by design. Every decision the
// screen makes - validation, the publish gate, the character count, the thread
// shape - is the ComposerLogic reducer's; nothing here re-derives a rule.
//
// Dependency note (this bit the LoginViews branch too): the iOS product-framework
// link closure needs every module this package imports as a *direct* product
// dependency, including modules that are only reachable as default arguments of
// ComposerLogic's public API. RichText/ATProtoClient/Lexicons/SwiftAtproto/Domain
// appear in ComposerLogic's public signatures and default arguments, so they are
// declared here even where no file below imports them.
import PackageDescription

let package = Package(
  name: "ComposerViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ComposerViews", targets: ["ComposerViews"])
  ],
  dependencies: [
    .package(path: "../Composer"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../RichText"),
    .package(path: "../../UIComponents"),
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ComposerViews",
      dependencies: [
        .product(name: "ComposerLogic", package: "Composer"),
        // The modules below are referenced by ComposerLogic's public API and its
        // default arguments, so the app's link closure pulls their symbols into
        // this module even though only a few files import them directly.
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/ComposerViews"
    )
  ]
)
