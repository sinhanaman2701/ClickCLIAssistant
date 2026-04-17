import Foundation

public enum AppBundleBuilder {
    public static let installedBundleURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
        .appendingPathComponent("ClickCLIAssistant.app", isDirectory: true)
    public static let installedServiceBundleURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Services", isDirectory: true)
        .appendingPathComponent("ClickCLIAssistant.service", isDirectory: true)

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

        let bundleURL = installedBundleURL

        try recreateBundle(at: bundleURL, from: builtBinary)
        try recreateServiceBundle()
        refreshLaunchServices(for: bundleURL)
        refreshLaunchServices(for: installedServiceBundleURL)
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

        let parentDirectory = bundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let macOSDirectory = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesDirectory = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOSDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let executableURL = macOSDirectory.appendingPathComponent("ClickCLIAssistant")
        try fileManager.copyItem(at: builtBinary, to: executableURL)

        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let infoPlist = makeInfoPlist()
        try infoPlist.write(to: infoPlistURL, options: .atomic)

        let pkgInfoURL = bundleURL.appendingPathComponent("Contents/PkgInfo")
        try "APPL????".write(to: pkgInfoURL, atomically: true, encoding: .utf8)
    }

    private static func refreshLaunchServices(for bundleURL: URL) {
        guard let lsregister = lsregisterPath() else { return }
        _ = OllamaEnvironment.run(lsregister, ["-f", bundleURL.path])
    }

    private static func makeInfoPlist() -> Data {
        let services: [[String: Any]] = [[
            "NSMenuItem": [
                "default": "Use Skills",
            ],
            "NSMessage": "useSkills",
            "NSPortName": "ClickCLIAssistant",
            "NSRequiredContext": [
                "NSServiceCategory": "public.text",
            ],
            "NSSendTypes": [
                "public.text",
                "public.utf8-plain-text",
            ],
            "NSReturnTypes": [],
        ]]

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "ClickCLIAssistant",
            "CFBundleExecutable": "ClickCLIAssistant",
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

    private static func makeServiceBundlePlist() -> Data {
        let services: [[String: Any]] = [[
            "NSMenuItem": [
                "default": "Use Skills",
            ],
            "NSMessage": "useSkills",
            "NSPortName": "ClickCLIAssistant",
            "NSRequiredContext": [
                "NSServiceCategory": "public.text",
            ],
            "NSSendTypes": [
                "public.text",
                "public.utf8-plain-text",
            ],
            "NSReturnTypes": [],
        ]]

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "ClickCLIAssistant",
            "CFBundleIdentifier": "com.sinhanaman2701.ClickCLIAssistant.services",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "ClickCLIAssistant",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "NSServices": services,
        ]

        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    private static func recreateServiceBundle() throws {
        let fileManager = FileManager.default
        let bundleURL = installedServiceBundleURL

        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }

        let parentDirectory = bundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let contentsDirectory = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contentsDirectory, withIntermediateDirectories: true)

        let infoPlistURL = contentsDirectory.appendingPathComponent("Info.plist")
        try makeServiceBundlePlist().write(to: infoPlistURL, options: .atomic)

        let pkgInfoURL = contentsDirectory.appendingPathComponent("PkgInfo")
        try "BNDL????".write(to: pkgInfoURL, atomically: true, encoding: .utf8)
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

    private static func lsregisterPath() -> String? {
        let candidates = [
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Support/lsregister",
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }
}
