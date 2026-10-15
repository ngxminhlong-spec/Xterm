// swift-tools-version:5.9
// Vendored copy of Citadel 0.12.1 (MIT, (c) Joannis Orlandos) with the minimum
// platform lowered to iOS 16 so Portico can support iOS 16.
// Changes vs upstream: platforms, server example and tests removed, and
// withDiscardingTaskGroup (iOS 17) replaced by withTaskGroup in RemotePortForward+Client.swift.
import PackageDescription

let package = Package(
    name: "Citadel",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "Citadel", targets: ["Citadel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
    ],
    targets: [
        .target(name: "CCitadelBcrypt"),
        .target(
            name: "Citadel",
            dependencies: [
                .target(name: "CCitadelBcrypt"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
