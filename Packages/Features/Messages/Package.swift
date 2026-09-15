// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Messages",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "MessagesLogic", targets: ["MessagesLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Lexicons"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, ATURI, DID) from the
    // vendored runtime; depend on it directly rather than relying on a transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "MessagesLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/MessagesLogic"
    ),
    .testTarget(
      name: "MessagesLogicTests",
      dependencies: [
        "MessagesLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/MessagesLogicTests"
    ),
  ]
)
