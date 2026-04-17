import Foundation

public enum AppLauncher {
    @discardableResult
    public static func launchApp(from executablePath: String = CommandLine.arguments[0]) -> Bool {
        let currentURL = URL(fileURLWithPath: executablePath)

        if let directBinary = directAppBinary(from: currentURL),
           FileManager.default.fileExists(atPath: directBinary.path) {
            return OllamaEnvironment.runDetached(directBinary.path, [])
        }

        guard let packageRoot = packageRoot(from: currentURL),
              let swiftPath = OllamaEnvironment.swiftPath() else {
            return false
        }

        let buildResult = OllamaEnvironment.run(
            swiftPath,
            ["build", "--product", "ai-assistant-app"],
            currentDirectory: packageRoot.path
        )
        guard buildResult.status == 0 else {
            return false
        }

        let builtBinary = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("ai-assistant-app")

        guard FileManager.default.fileExists(atPath: builtBinary.path) else {
            return false
        }

        return OllamaEnvironment.runDetached(builtBinary.path, [])
    }

    private static func directAppBinary(from currentURL: URL) -> URL? {
        currentURL.deletingLastPathComponent().appendingPathComponent("ai-assistant-app")
    }

    private static func packageRoot(from executableURL: URL) -> URL? {
        let pathComponents = executableURL.pathComponents
        guard let buildIndex = pathComponents.firstIndex(of: ".build"), buildIndex > 0 else {
            return nil
        }

        let rootComponents = Array(pathComponents.prefix(buildIndex))
        guard !rootComponents.isEmpty else { return nil }

        let rootPath = NSString.path(withComponents: rootComponents)
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }
}
