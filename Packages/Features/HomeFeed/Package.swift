// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "HomeFeed",
  platforms: [.iOS(.v18), .macOS(.v15)],
  defaultLocalization: "en",
  products: [
    .library(name: "HomeFeedLogic", targets: ["HomeFeedLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, ATURI, TID) from the
    // vendored runtime; depend on it directly rather than relying on a transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "HomeFeedLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/HomeFeedLogic"
    ),
    .testTarget(
      name: "HomeFeedLogicTests",
      dependencies: [
        "HomeFeedLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
      ],
      path: "Tests/HomeFeedLogicTests"
    ),
  ]
)
