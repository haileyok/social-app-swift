// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Domain",
  defaultLocalization: "en",
  products: [
    .library(name: "Domain", targets: ["Domain"])
  ],
  targets: [
    .target(name: "Domain", dependencies: []),
    .testTarget(name: "DomainTests", dependencies: ["Domain"]),
  ]
)
