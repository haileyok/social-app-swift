// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ATProtoClient",
  defaultLocalization: "en",
  products: [
    .library(name: "ATProtoClient", targets: ["ATProtoClient"])
  ],
  dependencies: [
    .package(path: "../ATSyntax")
  ],
  targets: [
    .target(name: "ATProtoClient", dependencies: ["ATSyntax"]),
    .testTarget(name: "ATProtoClientTests", dependencies: ["ATProtoClient"]),
  ]
)
