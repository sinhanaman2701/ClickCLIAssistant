// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AI Assistant",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ai-assistant-app", targets: ["AIAssistantApp"]),
        .executable(name: "ai-assistant-install", targets: ["AIAssistantInstall"]),
        .executable(name: "click-assistant", targets: ["ClickAssistantCLI"]),
    ],
    targets: [
        .target(
            name: "AIAssistantKit",
            path: "Sources/AIAssistantKit"
        ),
        .executableTarget(
            name: "AIAssistantApp",
            dependencies: ["AIAssistantKit"],
            path: "Sources/AIAssistantApp"
        ),
        .executableTarget(
            name: "AIAssistantInstall",
            dependencies: ["AIAssistantKit"],
            path: "Sources/AIAssistantInstall"
        ),
        .executableTarget(
            name: "ClickAssistantCLI",
            dependencies: ["AIAssistantKit"],
            path: "Sources/ClickAssistantCLI"
        ),
    ]
)
