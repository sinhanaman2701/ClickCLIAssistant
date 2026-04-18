#if false
import Darwin
import Foundation

public struct BridgeLaunchAgentStatus: Sendable {
    public let label: String
    public let plistPath: String
    public let binaryPath: String
    public let isInstalled: Bool
    public let isLoaded: Bool
    public let autoStartEnabled: Bool

    public init(
        label: String,
        plistPath: String,
        binaryPath: String,
        isInstalled: Bool,
        isLoaded: Bool,
        autoStartEnabled: Bool
    ) {
        self.label = label
        self.plistPath = plistPath
        self.binaryPath = binaryPath
        self.isInstalled = isInstalled
        self.isLoaded = isLoaded
        self.autoStartEnabled = autoStartEnabled
    }
}

public enum BridgeLaunchAgent {
    public static let label = "com.clickcliassistant.bridge"

    public static func installAndStart(from executablePath: String) throws -> BridgeLaunchAgentStatus {
        let binary = try prepareBridgeBinary(from: executablePath)
        let plist = try writeLaunchAgentPlist(binaryPath: binary.path)
        let loaded = loadOrRestart(plistPath: plist.path)
        return status(binaryPath: binary.path, plistPath: plist.path, autoStartEnabled: loaded)
    }

    public static func status(binaryPath: String? = nil, plistPath: String? = nil, autoStartEnabled: Bool = false) -> BridgeLaunchAgentStatus {
        let plist = plistPath ?? AppPaths.launchAgentPlist.path
        let binary = binaryPath ?? AppPaths.bridgeBinary.path
        let installed = FileManager.default.fileExists(atPath: plist)
        let loaded = isLoaded()
        return BridgeLaunchAgentStatus(
            label: label,
            plistPath: plist,
            binaryPath: binary,
            isInstalled: installed,
            isLoaded: loaded,
            autoStartEnabled: autoStartEnabled || loaded
        )
    }

    public static func uninstall() {
        _ = OllamaEnvironment.run("/bin/launchctl", ["bootout", launchDomainAndTarget()])
        if FileManager.default.fileExists(atPath: AppPaths.launchAgentPlist.path) {
            try? FileManager.default.removeItem(at: AppPaths.launchAgentPlist)
        }
    }

    private static func prepareBridgeBinary(from executablePath: String) throws -> URL {
        try AppPaths.ensureBaseDirectory()
        try FileManager.default.createDirectory(at: AppPaths.binDirectory, withIntermediateDirectories: true)

        let current = URL(fileURLWithPath: executablePath)
        let source = try resolveBridgeExecutable(from: current)
        let destination = AppPaths.bridgeBinary

        if source.standardizedFileURL.path != destination.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private static func resolveBridgeExecutable(from current: URL) throws -> URL {
        let fileManager = FileManager.default
        if current.lastPathComponent == "click-assistant", fileManager.fileExists(atPath: current.path) {
            return current
        }

        let sibling = current.deletingLastPathComponent().appendingPathComponent("click-assistant")
        if fileManager.fileExists(atPath: sibling.path) {
            return sibling
        }

        throw AppError.ollamaUnavailable("Could not locate `click-assistant` binary for bridge auto-start.")
    }

    private static func writeLaunchAgentPlist(binaryPath: String) throws -> URL {
        let plistURL = AppPaths.launchAgentPlist
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: AppPaths.logsDirectory, withIntermediateDirectories: true)

        let stdoutPath = AppPaths.logsDirectory.appendingPathComponent("bridge.stdout.log").path
        let stderrPath = AppPaths.logsDirectory.appendingPathComponent("bridge.stderr.log").path
        let payload = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escape(binaryPath))</string>
                <string>bridge</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>WorkingDirectory</key>
            <string>\(escape(AppPaths.appSupportDirectory.path))</string>
            <key>StandardOutPath</key>
            <string>\(escape(stdoutPath))</string>
            <key>StandardErrorPath</key>
            <string>\(escape(stderrPath))</string>
        </dict>
        </plist>
        """
        try payload.write(to: plistURL, atomically: true, encoding: .utf8)
        return plistURL
    }

    private static func loadOrRestart(plistPath: String) -> Bool {
        _ = OllamaEnvironment.run("/bin/launchctl", ["bootout", launchDomainAndTarget()])
        let bootstrap = OllamaEnvironment.run("/bin/launchctl", ["bootstrap", launchDomain(), plistPath])
        if bootstrap.status != 0 {
            return false
        }

        let kickstart = OllamaEnvironment.run("/bin/launchctl", ["kickstart", "-k", launchDomainAndTarget()])
        return kickstart.status == 0 && isLoaded()
    }

    private static func isLoaded() -> Bool {
        let result = OllamaEnvironment.run("/bin/launchctl", ["print", launchDomainAndTarget()])
        return result.status == 0
    }

    private static func launchDomain() -> String {
        "gui/\(getuid())"
    }

    private static func launchDomainAndTarget() -> String {
        "\(launchDomain())/\(label)"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

#endif
