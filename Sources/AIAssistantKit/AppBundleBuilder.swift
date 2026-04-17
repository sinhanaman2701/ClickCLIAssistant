import Foundation

public enum AppBundleBuilder {
    public static func ensureBundle(from executablePath: String) throws -> URL {
        let currentURL = URL(fileURLWithPath: executablePath)
        guard let packageRoot = packageRoot(from: currentURL) else {
            throw AppError.missingConfig
        }

        guard let swiftPath = OllamaEnvironment.swiftPath() else {
            throw AppError.ollamaUnavailable("Swift executable could not be resolved.")
        }

        let buildResult = OllamaEnvironment.run(
            swiftPath,
            ["build", "--product", "ai-assistant-app"],
            currentDirectory: packageRoot.path
        )
        guard buildResult.status == 0 else {
            throw AppError.ollamaUnavailable("Building ai-assistant-app failed: \(buildResult.output)")
        }

        let builtBinary = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("ai-assistant-app")

        guard FileManager.default.fileExists(atPath: builtBinary.path) else {
            throw AppError.ollamaUnavailable("Built app binary not found at \(builtBinary.path)")
        }

        let bundleURL = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("ClickCLIAssistant.app")

        try recreateBundle(at: bundleURL, from: builtBinary)
        return bundleURL
    }

    public static func launch(bundleURL: URL) -> Bool {
        OllamaEnvironment.run("/usr/bin/open", [bundleURL.path]).status == 0
    }

    private static func recreateBundle(at bundleURL: URL, from builtBinary: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }

        let macOSDirectory = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesDirectory = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOSDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let executableURL = macOSDirectory.appendingPathComponent("ai-assistant-app")
        try fileManager.copyItem(at: builtBinary, to: executableURL)

        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let infoPlist = makeInfoPlist()
        try infoPlist.write(to: infoPlistURL, options: .atomic)

        let pkgInfoURL = bundleURL.appendingPathComponent("Contents/PkgInfo")
        try "APPL????".write(to: pkgInfoURL, atomically: true, encoding: .utf8)
    }

    private static func makeInfoPlist() -> Data {
        let services: [[String: Any]] = [[
            "NSMenuItem": "Use Skills",
            "NSMessage": "useSkills:",
            "NSPortName": "ClickCLIAssistant",
            "NSSendTypes": ["public.utf8-plain-text"],
            "NSReturnTypes": [],
        ]]

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "ClickCLIAssistant",
            "CFBundleExecutable": "ai-assistant-app",
            "CFBundleIdentifier": "com.sinhanaman2701.ClickCLIAssistant",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "ClickCLIAssistant",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSBackgroundOnly": false,
            "NSServices": services,
            "NSPrincipalClass": "NSApplication",
        ]

        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    private static func packageRoot(from executableURL: URL) -> URL? {
        let pathComponents = executableURL.pathComponents
        guard let buildIndex = pathComponents.firstIndex(of: ".build"), buildIndex > 0 else {
            return nil
        }
        let rootComponents = Array(pathComponents.prefix(buildIndex))
        guard !rootComponents.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: rootComponents), isDirectory: true)
    }
}
