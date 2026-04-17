import Foundation

public enum OllamaEnvironment {
    public static func ollamaExists() -> Bool {
        executablePath(for: "ollama") != nil
    }

    public static func homebrewExists() -> Bool {
        executablePath(for: "brew") != nil
    }

    public static func ollamaPath() -> String? {
        executablePath(for: "ollama")
    }

    public static func brewPath() -> String? {
        executablePath(for: "brew")
    }

    public static func swiftPath() -> String? {
        executablePath(for: "swift")
    }

    public static func localOllamaReachable(host: String) async -> Bool {
        guard let url = URL(string: host)?.appending(path: "/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            return (200..<500).contains(statusCode)
        } catch {
            return false
        }
    }

    @discardableResult
    public static func run(
        _ launchPath: String,
        _ arguments: [String],
        currentDirectory: String? = nil
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    @discardableResult
    public static func runInteractive(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }

    @discardableResult
    public static func runDetached(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func executablePath(for name: String) -> String? {
        let result = run("/usr/bin/which", [name])
        guard result.status == 0 else { return nil }
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
