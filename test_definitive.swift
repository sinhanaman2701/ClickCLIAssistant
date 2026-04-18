import Foundation

// Exact copy of OllamaClient logic from deployed code

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

final class Box: @unchecked Sendable { var value: String; init(_ v: String) { value = v } }

final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let buf = Box("")
    var onToken: (String, TimeInterval) -> Void
    var onDone: (TimeInterval) -> Void
    let start: Date
    var tokenCount = 0

    init(start: Date, onToken: @escaping (String, TimeInterval) -> Void, onDone: @escaping (TimeInterval) -> Void) {
        self.start = start; self.onToken = onToken; self.onDone = onDone
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buf.value += chunk

        var searchRange = buf.value.startIndex
        while let nlRange = buf.value.range(of: "\n", range: searchRange..<buf.value.endIndex) {
            let line = String(buf.value[searchRange..<nlRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            searchRange = nlRange.upperBound
            guard !line.isEmpty, let d = line.data(using: .utf8) else { continue }
            if let r = try? JSONDecoder().decode(GenerateResponse.self, from: d), let c = r.response, !c.isEmpty {
                tokenCount += 1
                onToken(c, -start.timeIntervalSinceNow)
            }
        }
        buf.value = String(buf.value[searchRange...])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // flush remaining
        let rem = buf.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rem.isEmpty, let d = rem.data(using: .utf8),
           let r = try? JSONDecoder().decode(GenerateResponse.self, from: d), let c = r.response, !c.isEmpty {
            tokenCount += 1
            onToken(c, -start.timeIntervalSinceNow)
        }
        onDone(-start.timeIntervalSinceNow)
    }
}

func runTest(label: String, model: String, system: String, prompt: String) {
    print("\n═══ \(label) ═══")
    print("Model: \(model)")
    print("Prompt bytes: \(prompt.utf8.count + system.utf8.count)")

    let body = try! JSONEncoder().encode(GenerateRequest(model: model, system: system, prompt: prompt))
    var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
    req.httpMethod = "POST"; req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    let start = Date()
    let sema = DispatchSemaphore(value: 0)
    var firstTokenAt: TimeInterval = -1
    var fullText = ""

    let delegate = Delegate(start: start,
        onToken: { token, t in
            if firstTokenAt < 0 {
                firstTokenAt = t
                print(String(format: "  TTFT: %.3fs → \"\(token)\"", t))
            }
            fullText += token
        },
        onDone: { total in
            print(String(format: "  Total: %.3fs", total))
            print("  Output: \"\(fullText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
            sema.signal()
        }
    )

    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    session.dataTask(with: req).resume()
    sema.wait()
}

// ── Test 1: Absolute minimal ─────────────────────────────────────────────────
runTest(label: "1. Bare minimal",
    model: "qwen3.5:cloud",
    system: "",
    prompt: "Fix grammar: i went to store yesterday")

// ── Test 2: With system prompt (like app) ────────────────────────────────────
runTest(label: "2. With system prompt",
    model: "qwen3.5:cloud",
    system: "You are a text transformation assistant. Only return the transformed text. No explanation.",
    prompt: "Fix grammar: i went to store yesterday")

// ── Test 3: Full skill prompt (exact app payload) ────────────────────────────
let skillPrompt = """
You are a grammar correction assistant.

Correct the grammar, spelling, punctuation, and basic sentence flow of the selected text.

Rules:
- Return only the corrected text.
- Do not explain the changes.
- Do not add headings, labels, or commentary.
- Preserve the original meaning and tone as much as possible.
- Make minimal changes unless grammar requires otherwise.
"""

runTest(label: "3. Full skill payload (exact app)",
    model: "qwen3.5:cloud",
    system: "You are a text transformation assistant. Only return the transformed text. Do not add explanation, framing, or markdown fences unless the input clearly requires it.",
    prompt: "Skill:\n\(skillPrompt)\n\nSelected text:\nSharper product judgment, captured in working notes.")

print("\n✅ All tests done")
exit(0)
