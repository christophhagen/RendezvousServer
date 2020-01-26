// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Rendezvous",
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "3.3.0")),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.7.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.2.0"),
        .package(url: "https://github.com/christophhagen/CryptoKit25519.git", from: "0.2.0")
    ],
    targets: [
        .target(name: "App", dependencies: ["Vapor", "SwiftProtobuf", "CryptoSwift", "CryptoKit25519"]),
        .target(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: ["App"]),
    ]
)

