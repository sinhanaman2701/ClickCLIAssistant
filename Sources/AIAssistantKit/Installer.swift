import Foundation

public enum Installer {
    public static func run(executablePath: String = CommandLine.arguments[0]) async throws -> InstallResult {

        let host = "http://localhost:11434"
        let skillsDirectory = AppPaths.appSupportDirectory.appendingPathComponent("skills", isDirectory: true)
        try AppPaths.ensureBaseDirectory()
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        // Removed sample skill creation to allow users to start fresh with zero skills

        print("")
        print("Click Assistant setup")
        let modeIdx = TerminalUI.select(
            options: [
                "Ollama API Key — Works on free tier, fastest for large docs"
            ],
            title: "How would you like to run AI inference?"
        )
        let modeSelection = "2" // Always use API Key mode for now

        let setupMode: AppConfig.SetupMode
        var apiKey: String? = nil
        let model: String
        
        if modeSelection == "1" {
            // Local mode removed per user request.
            setupMode = .apiKey // Fallback (should not be reached)
            model = "gemini-3-flash-preview:cloud" 
        } else {
            setupMode = .apiKey
            print("")
            print("What is your Ollama API Key?")
            print("ℹ To get a free API key:")
            print("   1. Sign in or create an account at https://ollama.com")
            print("   2. Go to Settings -> API Keys -> Generate new key")
            
            apiKey = prompt("API Key", defaultValue: "")
            if apiKey?.isEmpty == true {
                throw AppError.ollamaUnavailable("API key cannot be empty.")
            }
            
            print("")
            print("")
            let modelIdx = TerminalUI.select(
                options: [
                    "gemini-3-flash-preview:cloud (recommended)",
                    "Use some other model..."
                ],
                title: "Which model?"
            )
            
            if modelIdx == 0 {
                model = "gemini-3-flash-preview:cloud"
            } else {
                let modelCommand = prompt(
                    "Paste the cloud model command (e.g. ollama run kimi-k2.5:cloud)",
                    defaultValue: "ollama run kimi-k2.5:cloud"
                )
                model = try parseModel(from: modelCommand)
            }
            
            print("")
            print("Verifying API key... ", terminator: "")
            let client = OllamaClient(host: URL(string: host)!, model: model, apiKey: apiKey)
            do {
                try await client.healthCheck()
                print("✅")
            } catch {
                print("❌")
                throw AppError.ollamaUnavailable("Failed to verify API key: \(error.localizedDescription)")
            }
        }

        let config = AppConfig(
            skillsDirectory: skillsDirectory.path,
            defaultModel: model,
            ollamaHost: host,
            setupMode: setupMode,
            apiKey: apiKey
        )
        try ConfigStore.save(config)

        // Browser extension setup disabled
        // let browserExtensionDirectory = try BrowserExtensionInstaller.install()
        // let bridgeAgent = try BridgeLaunchAgent.installAndStart(from: executablePath)

        return InstallResult(
            configPath: AppPaths.configFile.path,
            skillsDirectory: skillsDirectory.path,
            model: model
        )
    }

    public static func printSummary(_ result: InstallResult) {
        print("")
        print("Config saved to \(result.configPath)")
        print("Skills directory: \(result.skillsDirectory)")
        print("Default model: \(result.model)")
        print("Add your .md skill files here: \(result.skillsDirectory)")
        print("")
        print("Installation complete! Trigger the desktop assistant via the Cmd+Shift+Space hotkey.")
    }

    public static func doctor() async -> DoctorResult {
        let host = "http://localhost:11434"
        let reachable = await OllamaEnvironment.localOllamaReachable(host: host)
        return DoctorResult(
            ollamaInstalled: OllamaEnvironment.ollamaExists(),
            ollamaPath: OllamaEnvironment.ollamaPath(),
            localHostReachable: reachable,
            configPath: AppPaths.configFile.path,
            configExists: FileManager.default.fileExists(atPath: AppPaths.configFile.path)
        )
    }

    private static func ensureOllamaInstalled() throws {
        if OllamaEnvironment.ollamaExists() {
            return
        }

        guard OllamaEnvironment.homebrewExists() else {
            throw AppError.ollamaUnavailable("Ollama is not installed and Homebrew is not available for automatic install.")
        }

        print("Ollama is not installed. Installing with Homebrew...")
        guard let brewPath = OllamaEnvironment.brewPath() else {
            throw AppError.ollamaUnavailable("Homebrew was expected but its executable could not be resolved.")
        }
        let status = OllamaEnvironment.runInteractive(brewPath, ["install", "ollama"])
        guard status == 0 else {
            throw AppError.ollamaUnavailable("Automatic `brew install ollama` failed.")
        }
    }

    /// Fetch all model names from `ollama list`
    private static func detectInstalledModels(ollamaPath: String) -> [String] {
        let result = OllamaEnvironment.run(ollamaPath, ["list"])
        guard result.status == 0 else { return [] }
        let lines = result.output.components(separatedBy: .newlines).dropFirst() // skip header
        return lines.compactMap { line -> String? in
            let name = line.split(whereSeparator: \.isWhitespace).first.map(String.init)
            guard let n = name, !n.isEmpty else { return nil }
            return n
        }
    }

    /// Prefer small/fast local models; fall back to cloud if nothing local
    private static func pickBestModel(from models: [String]) -> String {
        // Prefer models that are local (no :cloud suffix), smallest first
        let local = models.filter { !$0.hasSuffix(":cloud") }
        if let best = local.first { return best }
        // Fall back to cloud models if that's all we have
        return models.first ?? "kimi-k2.5:cloud"
    }

    private static func prompt(_ label: String, defaultValue: String) -> String {
        print("\(label) [\(defaultValue)]: ", terminator: "")
        let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false ? value! : defaultValue)
    }

    private static func parseModel(from command: String) throws -> String {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            throw AppError.ollamaUnavailable("Expected a command like `ollama run kimi-k2.5:cloud`.")
        }

        if tokens.count == 1 {
            return tokens[0]
        }

        if tokens[0] == "ollama", tokens[1] == "run" {
            guard tokens.count >= 3, tokens[2] != "ollama", tokens[2] != "run" else {
                throw AppError.ollamaUnavailable("Expected a command like `ollama run kimi-k2.5:cloud`.")
            }
            return tokens[2]
        }

        if tokens.count >= 3, tokens[0].hasSuffix("/ollama"), tokens[1] == "run" {
            guard tokens[2] != "ollama", tokens[2] != "run" else {
                throw AppError.ollamaUnavailable("Expected a command like `ollama run kimi-k2.5:cloud`.")
            }
            return tokens[2]
        }

        throw AppError.ollamaUnavailable("Only commands in the form `ollama run <model>` are supported in setup.")
    }
}

public struct InstallResult: Sendable {
    public let configPath: String
    public let skillsDirectory: String
    public let model: String
}

public struct DoctorResult: Sendable {
    public let ollamaInstalled: Bool
    public let ollamaPath: String?
    public let localHostReachable: Bool
    public let configPath: String
    public let configExists: Bool

    public init(
        ollamaInstalled: Bool,
        ollamaPath: String?,
        localHostReachable: Bool,
        configPath: String,
        configExists: Bool
    ) {
        self.ollamaInstalled = ollamaInstalled
        self.ollamaPath = ollamaPath
        self.localHostReachable = localHostReachable
        self.configPath = configPath
        self.configExists = configExists
    }
}
