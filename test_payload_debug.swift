import Foundation

// Mirrors SkillParser exactly
func parseSkillPrompt(from fileContents: String) -> String {
    let trimmed = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmed.components(separatedBy: .newlines)

    var sections: [String: [String]] = [:]
    var currentSection: String?

    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("## ") {
            currentSection = t.replacingOccurrences(of: "## ", with: "").lowercased().trimmingCharacters(in: .whitespaces)
            sections[currentSection!, default: []] = []
            continue
        }
        guard let cs = currentSection else { continue }
        sections[cs, default: []].append(line)
    }

    let prompt = sections["prompt"]?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    return prompt
}

let skillFileContents = (try? String(contentsOf: URL(fileURLWithPath: "\(NSHomeDirectory())/.ai-assistant/skills/Grammar skill.md"), encoding: .utf8)) ?? ""
let skillPrompt = parseSkillPrompt(from: skillFileContents)
let selectedText = "Sharper product judgment, captured in working notes."

let systemPrompt = """
You are a text transformation assistant.
Only return the transformed text.
Do not add explanation, framing, or markdown fences unless the input clearly requires it.
"""

let userPrompt = """
Skill:
\(skillPrompt)

Selected text:
\(selectedText)
"""

print("=== EXACT PAYLOAD DEBUG ===")
print("[SKILL PROMPT] (\(skillPrompt.count) chars):\n\(skillPrompt)")
print()
print("[SYSTEM PROMPT] (\(systemPrompt.count) chars)")
print("[USER PROMPT] (\(userPrompt.count) chars):\n\(userPrompt)")
print()

let body = try! JSONSerialization.data(withJSONObject: [
    "model": "qwen3.5:cloud",
    "system": systemPrompt,
    "prompt": userPrompt,
    "stream": true
])
print("[TOTAL PAYLOAD BYTES] \(body.count)")
print("[FULL JSON]")
print(String(data: body, encoding: .utf8)!)
print()

// Now fire it and time it
var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
req.httpMethod = "POST"
req.httpBody = body
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

let start = Date()
print("[START] \(Date())")

Task {
    do {
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        var first = true
        for try await _ in bytes.lines {
            if first {
                print(String(format: "[TTFT] %.3f seconds", -start.timeIntervalSinceNow))
                first = false
            }
        }
        print(String(format: "[TOTAL] %.3f seconds", -start.timeIntervalSinceNow))
    } catch { print("[ERROR] \(error)") }
    exit(0)
}
RunLoop.main.run()
