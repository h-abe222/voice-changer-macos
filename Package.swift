// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceChanger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceChanger", targets: ["VoiceChangerApp"]),
        .library(name: "AudioEngine", targets: ["AudioEngine"]),
        .library(name: "DSP", targets: ["DSP"]),
    ],
    dependencies: [
        // 将来的に追加予定
        // .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.6.0"),
    ],
    targets: [
        // メインアプリ
        .executableTarget(
            name: "VoiceChangerApp",
            dependencies: ["AudioEngine", "DSP", "Utilities"],
            path: "App/Sources/App"
        ),

        // オーディオエンジン
        .target(
            name: "AudioEngine",
            dependencies: ["DSP", "Utilities", "CHelpers"],
            path: "App/Sources/Audio"
        ),

        // DSP処理
        .target(
            name: "DSP",
            dependencies: ["Utilities"],
            path: "App/Sources/DSP"
        ),

        // UI（SwiftUI）
        .target(
            name: "UI",
            dependencies: ["AudioEngine"],
            path: "App/Sources/UI"
        ),

        // モデル
        .target(
            name: "Models",
            path: "App/Sources/Models"
        ),

        // Cヘルパー（Swift非対応POSIX関数ラッパー）
        .target(
            name: "CHelpers",
            path: "App/Sources/CHelpers",
            publicHeadersPath: "include"
        ),

        // ユーティリティ
        .target(
            name: "Utilities",
            dependencies: ["CHelpers"],
            path: "App/Sources/Utilities"
        ),

        // テスト
        .testTarget(
            name: "DSPTests",
            dependencies: ["DSP"],
            path: "App/Tests/DSPTests"
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"],
            path: "App/Tests/AudioEngineTests"
        ),
    ]
)
