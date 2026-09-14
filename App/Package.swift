// swift-tools-version: 6.3
// The iOS app shell. NOT Linux-verifiable (imports SwiftUI/UIKit).
// All source code lives in Packages/; this target is the thin entry point.
import PackageDescription

let package = Package(
  name: "AppShell",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "AppShell", targets: ["AppShell"])
  ],
  dependencies: [
    // UI packages (macOS-CI-built). Added as they land:
    // .package(path: "../Packages/DesignSystem"),
    // .package(path: "../Packages/UIComponents"),
  ],
  targets: [
    .target(
      name: "AppShell",
      path: "Sources/AppShell"
    )
  ]
)
