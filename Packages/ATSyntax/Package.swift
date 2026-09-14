// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ATSyntax",
  defaultLocalization: "en",
  products: [
    .library(name: "ATSyntax", targets: ["ATSyntax"])
  ],
  targets: [
    .target(name: "ATSyntax", dependencies: []),
    .testTarget(name: "ATSyntaxTests", dependencies: ["ATSyntax"]),
  ]
)
