import Foundation

// ─── Mirrors OllamaClient exactly as deployed ───────────────────────────────

struct GenerateRequest: Encodable {
    let model: String
    let system: String
    let prompt: String
    let stream = true
}

struct GenerateResponse: Decodable {
    let response: String?
    let done: Bool?
}

final class OllamaStreamDelegate: NSObject, URLSessionDataDelegate {
    var onToken: (String) -> Void
    var onDone: () -> Void
    var buffer = ""

    init(onToken: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.onToken = onToken
        self.onDone = onDone
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return }
        for i in 0..<(lines.count - 1) {
            let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: lineData),
               let content = decoded.response, !content.isEmpty {
                onToken(content)
            }
        }
        buffer = String(lines.last ?? "")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print(error == nil ? "[DONE] Stream completed successfully" : "[ERROR] \(error!.localizedDescription)")
        onDone()
    }
}

// ─── Run the test ────────────────────────────────────────────────────────────

let config = try! String(contentsOfFile: "\(NSHomeDirectory())/.ai-assistant/config.json")
print("[CONFIG] \(config.trimmingCharacters(in: .whitespacesAndNewlines))")

let modelName: String = {
    if let data = config.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let m = json["defaultModel"] as? String { return m }
    return "qwen3.5:cloud"
}()
print("[MODEL] \(modelName)")

let skillContent = (try? String(contentsOfFile: "\(NSHomeDirectory())/.ai-assistant/skills/Grammar skill.md")) ?? "Fix grammar mistakes."
print("[SKILL FILE] \(skillContent.prefix(100))...")

let selectedText = "Sharper product judgment, captured in working notes."
print("[INPUT TEXT] \(selectedText)")
print("[WORD COUNT] \(selectedText.split(separator: " ").count) words")

let body = try! JSONEncoder().encode(GenerateRequest(
    model: modelName,
    system: """
    You are a text transformation assistant.
    Only return the transformed text.
    Do not add explanation, framing, or markdown fences unless the input clearly requires it.
    """,
    prompt: """
    Skill:
    \(skillContent)

    Selected text:
    \(selectedText)
    """
))
print("[PAYLOAD SIZE] \(body.count) bytes")
print()

var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
req.httpMethod = "POST"
req.httpBody = body
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

let globalStart = Date()
var firstTokenTime: TimeInterval?
var tokenCount = 0
var full = ""

let delegate = OllamaStreamDelegate(
    onToken: { token in
        if firstTokenTime == nil {
            firstTokenTime = -globalStart.timeIntervalSinceNow
            print(String(format: "[TTFT] %.3f seconds — First token: \(token.debugDescription)", firstTokenTime!))
        }
        tokenCount += 1
        full += token
        print("[TOKEN \(tokenCount)] \(token.debugDescription)")
    },
    onDone: {
        let total = -globalStart.timeIntervalSinceNow
        print()
        print("[RESULT] \(full)")
        print(String(format: "[TOTAL] %.3f seconds — %d tokens", total, tokenCount))
        exit(0)
    }
)

let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
let task = session.dataTask(with: req)

print("[START] Firing request at \(Date())")
task.resume()

RunLoop.main.run()
