import Foundation

public struct AppConfig: Codable, Sendable {
    public var skillsDirectory: String
    public var defaultModel: String
    public var ollamaHost: String
    public var setupMode: SetupMode

    public enum SetupMode: String, Codable, Sendable {
        case localOllama
        case apiKey
    }

    public init(
        skillsDirectory: String,
        defaultModel: String = "kimi-k2.5:cloud",
        ollamaHost: String = "http://localhost:11434",
        setupMode: SetupMode = .localOllama
    ) {
        self.skillsDirectory = skillsDirectory
        self.defaultModel = defaultModel
        self.ollamaHost = ollamaHost
        self.setupMode = setupMode
    }
}

public struct Skill: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let prompt: String
    public let sourceFile: String

    public init(id: String, name: String, description: String?, prompt: String, sourceFile: String) {
        self.id = id
        self.name = name
        self.description = description
        self.prompt = prompt
        self.sourceFile = sourceFile
    }
}

public struct SelectionSnapshot: Sendable, Equatable {
    public let text: String
    public let frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

public struct OllamaResponse: Decodable, Sendable {
    public let message: OllamaMessage?
    public let response: String?
    public let done: Bool?

    public struct OllamaMessage: Decodable, Sendable {
        public let role: String
        public let content: String
    }
}

public enum AppError: LocalizedError {
    case invalidSkillFile(String)
    case missingConfig
    case ollamaUnavailable(String)
    case unsupportedSelection
    case uninstallCancelled

    public var errorDescription: String? {
        switch self {
        case .invalidSkillFile(let file):
            return "Invalid skill file: \(file)"
        case .missingConfig:
            return "App config is missing. Run ai-assistant-install first."
        case .ollamaUnavailable(let detail):
            return "Ollama is unavailable: \(detail)"
        case .unsupportedSelection:
            return "Unable to read the current text selection."
        case .uninstallCancelled:
            return "Uninstall cancelled."
        }
    }
}
