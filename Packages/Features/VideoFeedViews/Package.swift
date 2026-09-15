// swift-tools-version: 6.3
// The immersive video feed's SwiftUI layer: a full-screen vertical pager over
// `VideoFeedLogic`, an AVPlayer-backed player surface with a three-slot
// recycling pool, and the overlay chrome.
//
// This is a `Views` package, so the Linux build/test loop skips it and the
// boundary-lint does not scan it: importing SwiftUI/AVFoundation is the whole
// point. Every decision the pager makes - viewability, slot assignment, the
// autoplay gate, the playback phases - lives in `VideoFeedLogic` next door;
// nothing here re-derives a rule that package already owns.
//
// Every product listed below is imported somewhere in this target, including
// the modules that are only reached through another package's default
// arguments: the iOS product-framework link closure needs a direct dependency
// for each.
import PackageDescription

let package = Package(
  name: "VideoFeedViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "VideoFeedViews", targets: ["VideoFeedViews"])
  ],
  dependencies: [
    .package(path: "../VideoFeed"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../RichText"),
    .package(path: "../../UIComponents"),
    // The generated lexicon types used to build fixture posts expose formats
    // (FormatString, DID, Handle, ATURI, LexLink) from the vendored runtime;
    // depend on it directly rather than relying on a transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "VideoFeedViews",
      dependencies: [
        .product(name: "VideoFeedLogic", package: "VideoFeed"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/VideoFeedViews"
    )
  ]
)
