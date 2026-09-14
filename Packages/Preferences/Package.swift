// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Preferences",
  defaultLocalization: "en",
  products: [
    .library(name: "Preferences", targets: ["Preferences"])
  ],
  targets: [
    .target(name: "Preferences", dependencies: []),
    .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
  ]
)
