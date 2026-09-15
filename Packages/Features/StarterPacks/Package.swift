// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "StarterPacks",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "StarterPacksLogic", targets: ["StarterPacksLogic"])
  ],
  dependencies: [
    .package(path: "../../ATSyntax"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, ATURI, DID) from
    // the vendored runtime; depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "StarterPacksLogic",
      dependencies: [
        .product(name: "ATSyntax", package: "ATSyntax"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/StarterPacksLogic"
    ),
    .testTarget(
      name: "StarterPacksLogicTests",
      dependencies: [
        "StarterPacksLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/StarterPacksLogicTests"
    ),
  ]
)
