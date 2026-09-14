// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ATSyntax",
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
