// swift-tools-version: 6.3
// The SwiftUI half of the Notifications feature: the notifications list screen
// (reason rows, unread highlighting, the all/mentions/priority filter, the empty
// state) and the fixture surface the app shell mounts.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. Every
// decision this screen makes - which reason renders as which copy, which icon,
// which rows group together, whether a row is unread - lives in the
// NotificationsLogic package next door and is ported from the RN
// `NotificationFeedItem`; the view only draws the value it is handed.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "NotificationsViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "NotificationsViews", targets: ["NotificationsViews"])
  ],
  dependencies: [
    .package(path: "../Notifications"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../UIComponents"),
    // Vendored generator runtime: the fixture builds lexicon rows, which means
    // `FormatString`/`ATURI`/`DID`/`LexLink` and `UnknownATPValue` at the call
    // sites, so it is a direct dependency rather than one reached through
    // Lexicons alone.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "NotificationsViews",
      dependencies: [
        .product(name: "NotificationsLogic", package: "Notifications"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Lexicons", package: "Lexicons"),
        // `NotificationReasons.postView` hands back a `Moderation.PostView`, and
        // `PostFeedItem` takes a `Moderation.ModerationDecision`, so this
        // module's link closure needs the product directly.
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/NotificationsViews"
    ),
  ]
)
