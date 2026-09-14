// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Notifications",
  defaultLocalization: "en",
  products: [
    .library(name: "NotificationsLogic", targets: ["NotificationsLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "NotificationsLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        "Lexicons",
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/NotificationsLogic"
    ),
    .testTarget(
      name: "NotificationsLogicTests",
      dependencies: [
        "NotificationsLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/NotificationsLogicTests"
    ),
  ]
)
