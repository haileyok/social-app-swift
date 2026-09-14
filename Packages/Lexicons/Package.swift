// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Lexicons",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "Lexicons", targets: ["Lexicons"])
  ],
  dependencies: [
    // Vendored generator runtime (MIT, pinned) — provides ATProtoRecord,
    // UnknownRecord, FormatString and the XRPC request protocols that
    // generated types conform to. See tools/lexicon-codegen/README.md.
    .package(path: "../../tools/lexicon-codegen/swift-atproto")
  ],
  targets: [
    .target(
      name: "Lexicons",
      dependencies: [.product(name: "SwiftAtproto", package: "swift-atproto")],
      path: "Sources/Lexicons"
    ),
    .testTarget(
      name: "LexiconsTests",
      dependencies: ["Lexicons"],
      path: "Tests/LexiconsTests"
    )
  ]
)
