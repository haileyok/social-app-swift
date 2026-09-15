// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Preferences",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "Preferences", targets: ["Preferences"])
  ],
  dependencies: [
    .package(path: "../Lexicons"),
    .package(path: "../ATProtoClient"),
    // The generated lexicon types expose formats (FormatString, ATURI, TID) from the
    // vendored runtime; depend on it directly rather than relying on a transitive import.
    .package(path: "../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "Preferences",
      dependencies: [
        "Lexicons",
        "ATProtoClient",
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ]),
    .testTarget(
      name: "PreferencesTests",
      dependencies: [
        "Preferences",
        "Lexicons",
        "ATProtoClient",
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ]),
  ]
)
