// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Settings",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "SettingsLogic", targets: ["SettingsLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Persistence"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, DID) from the
    // vendored runtime, so depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "SettingsLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/SettingsLogic"
    ),
    .testTarget(
      name: "SettingsLogicTests",
      dependencies: [
        "SettingsLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/SettingsLogicTests"
    ),
  ]
)
