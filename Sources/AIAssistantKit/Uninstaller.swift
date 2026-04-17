import Foundation

public enum Uninstaller {
    public static func run(
        executablePath: String = CommandLine.arguments[0],
        force: Bool = false
    ) throws -> UninstallResult {
        let sourceDirectory = sourceDirectoryToRemove(from: executablePath)

        if !force {
            print("This will remove:")
            print("- \(AppPaths.appSupportDirectory.path)")
            if let sourceDirectory {
                print("- \(sourceDirectory.path)")
            }
            print("")
            print("Continue? [y/N]: ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                throw AppError.uninstallCancelled
            }
        }

        var removedPaths: [String] = []
        let fileManager = FileManager.default

        let hadLaunchAgent = fileManager.fileExists(atPath: AppPaths.launchAgentPlist.path)
        BridgeLaunchAgent.uninstall()
        if hadLaunchAgent {
            removedPaths.append(AppPaths.launchAgentPlist.path)
        }

        if fileManager.fileExists(atPath: AppPaths.appSupportDirectory.path) {
            try fileManager.removeItem(at: AppPaths.appSupportDirectory)
            removedPaths.append(AppPaths.appSupportDirectory.path)
        }

        if let sourceDirectory,
           fileManager.fileExists(atPath: sourceDirectory.path),
           isSafeSourceDirectory(sourceDirectory) {
            try fileManager.removeItem(at: sourceDirectory)
            removedPaths.append(sourceDirectory.path)
        }

        return UninstallResult(removedPaths: removedPaths)
    }

    private static func sourceDirectoryToRemove(from executablePath: String) -> URL? {
        let executableURL = URL(fileURLWithPath: executablePath)
        if let packageRoot = packageRoot(from: executableURL), isSafeSourceDirectory(packageRoot) {
            return packageRoot
        }

        if isSafeSourceDirectory(AppPaths.bootstrapSourceDirectory) {
            return AppPaths.bootstrapSourceDirectory
        }

        return nil
    }

    private static func isSafeSourceDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path == "\(home)/.click-cli-assistant-src"
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

public struct UninstallResult: Sendable {
    public let removedPaths: [String]

    public init(removedPaths: [String]) {
        self.removedPaths = removedPaths
    }
}
