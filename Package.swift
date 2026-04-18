// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "LidGuard",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2"),
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
  ],
  targets: [
    .executableTarget(
      name: "LidGuard",
      dependencies: [
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        "KeyboardShortcuts"
      ],
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    )
  ]
)
