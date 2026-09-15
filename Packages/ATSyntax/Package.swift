// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ATSyntax",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ATSyntax", targets: ["ATSyntax"])
  ],
  targets: [
    .target(name: "ATSyntax"),
    .testTarget(
      name: "ATSyntaxTests",
      dependencies: ["ATSyntax"],
      resources: [
        // atproto repo interop fixtures (interop-test-files/syntax/*.txt)
        .copy("Fixtures")
      ]
    ),
  ]
)
