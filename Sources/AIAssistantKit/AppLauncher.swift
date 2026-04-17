import Foundation

public enum AppLauncher {
    @discardableResult
    public static func launchApp(from executablePath: String = CommandLine.arguments[0]) -> Bool {
        guard let bundleURL = try? AppBundleBuilder.ensureBundle(from: executablePath) else {
            return false
        }
        return AppBundleBuilder.launch(bundleURL: bundleURL)
    }
}
