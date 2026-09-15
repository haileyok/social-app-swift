// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Profile",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ProfileLogic", targets: ["ProfileLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types express fields in the vendored runtime's
    // `FormatString`/`LexBlob`, so the runtime is a direct dependency rather
    // than a transitive one.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ProfileLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/ProfileLogic"
    ),
    .testTarget(
      name: "ProfileLogicTests",
      dependencies: [
        "ProfileLogic",
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/ProfileLogicTests"
    ),
  ]
)
