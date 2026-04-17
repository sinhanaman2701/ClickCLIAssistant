import Foundation
import CryptoKit

public enum SkillParser {
    public static func parse(url: URL) throws -> Skill {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidSkillFile(url.lastPathComponent)
        }

        let lines = trimmed.components(separatedBy: .newlines)
        let title = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") })
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }

        let sections = parseSections(from: lines)
        let name = title ?? url.deletingPathExtension().lastPathComponent
        let description = sections["description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = sections["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        guard !prompt.isEmpty else {
            throw AppError.invalidSkillFile(url.lastPathComponent)
        }

        let id = Insecure.MD5.hash(data: Data(url.path.utf8)).map { String(format: "%02hhx", $0) }.joined()
        return Skill(id: id, name: name, description: description, prompt: prompt, sourceFile: url.path)
    }

    private static func parseSections(from lines: [String]) -> [String: String] {
        var sections: [String: [String]] = [:]
        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                currentSection = trimmed
                    .replacingOccurrences(of: "## ", with: "")
                    .lowercased()
                    .trimmingCharacters(in: .whitespaces)
                sections[currentSection!, default: []] = []
                continue
            }

            guard let currentSection else { continue }
            sections[currentSection, default: []].append(line)
        }

        return sections.mapValues { $0.joined(separator: "\n") }
    }
}
