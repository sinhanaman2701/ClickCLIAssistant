import Foundation

public enum Installer {
    public static func run(executablePath: String = CommandLine.arguments[0]) async throws -> InstallResult {
        try ensureOllamaInstalled()

        let host = "http://localhost:11434"
        let skillsDirectory = AppPaths.appSupportDirectory.appendingPathComponent("skills", isDirectory: true)
        try AppPaths.ensureBaseDirectory()
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        try ensureSampleSkill(in: skillsDirectory)

        let modelCommand = prompt(
            "Paste your Ollama cloud model command",
            defaultValue: "ollama run kimi-k2.5:cloud"
        )
        let model = try parseModel(from: modelCommand)

        print("")
        print("Verifying model \(model)...")
        guard let ollamaPath = OllamaEnvironment.ollamaPath() else {
            throw AppError.ollamaUnavailable("Could not resolve the `ollama` executable.")
        }
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

        let config = AppConfig(
            skillsDirectory: skillsDirectory.path,
            defaultModel: model,
            ollamaHost: host
        )
        try ConfigStore.save(config)

        let didLaunch = AppLauncher.launchApp(from: executablePath)

        return InstallResult(
            configPath: AppPaths.configFile.path,
            skillsDirectory: skillsDirectory.path,
            model: model,
            didLaunchApp: didLaunch
        )
    }

    public static func printSummary(_ result: InstallResult) {
        print("")
        print("Config saved to \(result.configPath)")
        print("Skills directory: \(result.skillsDirectory)")
        print("Default model: \(result.model)")
        print("Add your .md skill files here: \(result.skillsDirectory)")
        print("")
        if result.didLaunchApp {
            print("AI Assistant app launched.")
        } else {
            print("Could not auto-launch the app. Start it with `swift run ai-assistant-app` or `swift run click-assistant run`.")
        }
        print("Select text in an app and look for the `Use Skills` popup above the selection.")
        print("If the popup does not appear, enable Accessibility permission for Terminal in macOS Settings.")
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

    private static func ensureSampleSkill(in directory: URL) throws {
        let sample = directory.appendingPathComponent("Grammar Correction.md")
        guard !FileManager.default.fileExists(atPath: sample.path) else { return }

        let contents = """
        # Grammar Correction

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
    public let didLaunchApp: Bool
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
