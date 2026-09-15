// swift-tools-version: 6.3
// The SwiftUI half of the Moderation feature: the content-label preferences
// screen, the muted-words editor, the blocked/muted account lists, the labeler
// directory, and the report dialog sheet.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. Every
// decision - which label rows exist, which reasons a labeler accepts, how a
// muted word serializes - lives in the ModerationUILogic package next door, and
// nothing here re-derives a rule that package already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "ModerationUIViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ModerationUIViews", targets: ["ModerationUIViews"])
  ],
  dependencies: [
    .package(path: "../ModerationUI"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    .package(path: "../../UIComponents"),
    // ModerationUILogic's public signatures are types from these modules
    // (`MutedWord`/`LabelValueDefinition` from Moderation, `ProfileView` from
    // Lexicons with `FormatString<DID>` from SwiftAtproto, `PrefObject` from
    // Preferences, `XrpcClient` from ATProtoClient, `QueryStore`), and its
    // default arguments reference them too, so the iOS product-framework link
    // closure needs every one of them declared directly. See the repo convention
    // recorded in App/Package.swift and LoginViews/Package.swift.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ModerationUIViews",
      dependencies: [
        .product(name: "ModerationUILogic", package: "ModerationUI"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/ModerationUIViews"
    )
  ]
)
