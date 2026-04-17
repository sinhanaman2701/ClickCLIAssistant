import Foundation

public enum AppLauncher {
    @discardableResult
    public static func launchApp(from executablePath: String = CommandLine.arguments[0]) -> Bool {
        let currentURL = URL(fileURLWithPath: executablePath)
        let appURL = currentURL.deletingLastPathComponent().appendingPathComponent("ai-assistant-app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return false
        }
        return OllamaEnvironment.runDetached(appURL.path, [])
    }
}
