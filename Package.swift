// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "LidGuard",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2")
  ],
  targets: [
    .executableTarget(
      name: "LidGuard",
      dependencies: [
        "SkyLightWindow",
        .product(name: "MarkdownUI", package: "swift-markdown-ui")
      ],
      path: "Sources"
    )
  ]
)
