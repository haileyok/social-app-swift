// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ModerationUI",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "ModerationUILogic", targets: ["ModerationUILogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // Vendored generator runtime, for `FormatString`/`ATURI`/`DID` used when
    // building lexicon fixtures in tests.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ModerationUILogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
      ],
      path: "Sources/ModerationUILogic"
    ),
    .testTarget(
      name: "ModerationUILogicTests",
      dependencies: [
        "ModerationUILogic",
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/ModerationUILogicTests"
    ),
  ]
)
