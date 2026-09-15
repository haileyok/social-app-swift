// swift-tools-version: 6.3
// The SwiftUI half of the Messages feature: the 1:1 inbox and conversation
// screens, plus the fixture surfaces that render a scripted conversation.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. Every
// decision - history paging, the outbox, reactions, read state - belongs to the
// MessagesLogic package next door; nothing here re-derives a rule.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "MessagesViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "MessagesViews", targets: ["MessagesViews"])
  ],
  dependencies: [
    .package(path: "../Messages"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../RichText"),
    .package(path: "../../UIComponents"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, DID) from the
    // vendored runtime; depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "MessagesViews",
      dependencies: [
        .product(name: "MessagesLogic", package: "Messages"),
        // MessagesLogic's default arguments and public state reference
        // ATProtoClient types; the iOS product-framework link closure needs the
        // direct dependency.
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/MessagesViews"
    )
  ]
)
