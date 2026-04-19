import Foundation

public enum Installer {
    public static func run(executablePath: String = CommandLine.arguments[0]) async throws -> InstallResult {

        let host = "http://localhost:11434"
        let skillsDirectory = AppPaths.appSupportDirectory.appendingPathComponent("skills", isDirectory: true)
        try AppPaths.ensureBaseDirectory()
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        try ensureSampleSkill(in: skillsDirectory)

        print("")
        print("Click Assistant setup")
        print("How would you like to run AI inference?")
        print("  [1] Local Ollama  — Free, offline, uses local models.")
        print("                      ⚠ Cloud models (.:cloud) may be slow locally.")
        print("  [2] Ollama API Key — Calls https://ollama.com/api directly.")
        print("                      Free tier, fast response, requires internet.")
        print("")
        
        let modeSelection = prompt("Choose 1 or 2", defaultValue: "2")

        let setupMode: AppConfig.SetupMode
        var apiKey: String? = nil
        let model: String
        
        if modeSelection == "1" {
            setupMode = .localOllama
            
            try ensureOllamaInstalled()
            guard let ollamaPath = OllamaEnvironment.ollamaPath() else {
                throw AppError.ollamaUnavailable("Could not resolve the `ollama` executable.")
            }

            // Auto-detect installed models and show them
            let installedModels = detectInstalledModels(ollamaPath: ollamaPath)
            let smartDefault = pickBestModel(from: installedModels)

            if !installedModels.isEmpty {
                print("")
                print("Detected Ollama models:")
                for m in installedModels { print("  - \(m)") }
            }

            print("")
            let modelCommand = prompt(
                "Paste your Ollama model command (or just the model name)",
                defaultValue: "ollama run \(smartDefault)"
            )
            model = try parseModel(from: modelCommand)

            print("")
            print("Verifying model \(model)...")
            var verifyResult = OllamaEnvironment.run(
                ollamaPath,
                ["run", model, "Reply with only OK"]
            )

            if verifyResult.status != 0, model.hasSuffix(":cloud") {
                print("Verification failed. Attempting `ollama signin` and retrying...")
                let signInStatus = OllamaEnvironment.runInteractive(ollamaPath, ["signin"])
                guard signInStatus == 0 else {
                    throw AppError.ollamaUnavailable("`ollama signin` did not complete successfully.")
                }
                verifyResult = OllamaEnvironment.run(
                    ollamaPath,
                    ["run", model, "Reply with only OK"]
                )
            }

            guard verifyResult.status == 0 else {
                let detail = verifyResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AppError.ollamaUnavailable(
                    detail.isEmpty ? "Model verification failed for \(model)." : detail
                )
            }
            
            let reachable = await OllamaEnvironment.localOllamaReachable(host: host)
            guard reachable else {
                throw AppError.ollamaUnavailable("Local Ollama is still not reachable at \(host) after verification.")
            }
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
            print("Which model?")
            print("ℹ We recommend gemma3:27b-cloud or qwen2.5 for fast response times.")
            print("  You can find more models on ollama.com by looking for their `ollama run` command.")
            
            let modelCommand = prompt(
                "Model (paste the command or just the name)",
                defaultValue: "gemma3:27b-cloud"
            )
            model = try parseModel(from: modelCommand)
            
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

    private static func ensureSampleSkill(in directory: URL) throws {
        let sample = directory.appendingPathComponent("Grammar skill.md")
        guard !FileManager.default.fileExists(atPath: sample.path) else { return }

        let contents = """
        # Grammar skill

        ## Description
        Correct the grammar of the selected text and return only the corrected text.

        ## Prompt
        You are a grammar correction assistant.

        Correct the grammar, spelling, punctuation, and basic sentence flow of the selected text.

        Rules:
        - Return only the corrected text.
        - Do not explain the changes.
        - Do not add headings, labels, or commentary.
        - Preserve the original meaning and tone as much as possible.
        - Make minimal changes unless grammar requires otherwise.
        """
        try contents.write(to: sample, atomically: true, encoding: .utf8)
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
