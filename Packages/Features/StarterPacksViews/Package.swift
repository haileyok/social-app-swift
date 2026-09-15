// swift-tools-version: 6.3
// The SwiftUI half of the Starter Packs feature: the pack screen (header,
// people, feeds), the create/edit wizard, the share sheet with its QR card,
// and the logged-out landing screen.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the
// Linux build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. All
// decision logic - tab derivation, header stats, the wizard state machine and
// its refusals, membership, share URLs - lives in StarterPacksLogic next door.
// Nothing here re-derives a rule that package already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "StarterPacksViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "StarterPacksViews", targets: ["StarterPacksViews"])
  ],
  dependencies: [
    .package(path: "../StarterPacks"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Lexicons"),
    .package(path: "../../UIComponents"),
    // The generated lexicon types expose formats (FormatString, ATURI, DID)
    // from the vendored runtime; depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "StarterPacksViews",
      dependencies: [
        .product(name: "StarterPacksLogic", package: "StarterPacks"),
        // StarterPacksLogic's default arguments and protocol witnesses reference
        // ATProtoClient types; the iOS product-framework link closure needs the
        // direct dependency.
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/StarterPacksViews"
    )
  ]
)
