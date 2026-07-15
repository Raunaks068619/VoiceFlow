// swift-tools-version:5.9
import PackageDescription

// Standalone MCP server for Vordi. Deliberately ZERO dependencies and a
// separate SwiftPM package so it never touches the main app's xcodeproj build.
// It reads Vordi's on-disk run history directly (~/Library/Application Support/
// Vordi/runs) — no app process required, read-only.
let package = Package(
    name: "vordi-mcp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "vordi-mcp",
            path: "Sources/vordi-mcp"
        )
    ]
)
