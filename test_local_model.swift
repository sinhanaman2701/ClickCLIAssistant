import Foundation

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
                onToken(c, -start.timeIntervalSinceNow)
            }
        }
        buf.value = String(buf.value[searchRange...])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let rem = buf.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rem.isEmpty, let d = rem.data(using: .utf8),
           let r = try? JSONDecoder().decode(GenerateResponse.self, from: d), let c = r.response, !c.isEmpty {
            onToken(c, -start.timeIntervalSinceNow)
        }
        onDone(-start.timeIntervalSinceNow)
    }
}

func runTest(label: String, model: String, system: String, prompt: String) {
    print("\n═══ \(label) ═══")
    let body = try! JSONEncoder().encode(GenerateRequest(model: model, system: system, prompt: prompt))
    var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
    req.httpMethod = "POST"; req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    let start = Date(); let sema = DispatchSemaphore(value: 0)
    var ttft: TimeInterval = -1; var out = ""

    let d = Delegate(start: start,
        onToken: { tok, t in
            if ttft < 0 { ttft = t; print(String(format: "  TTFT: %.3fs → \"\(tok)\"", t)) }
            out += tok
        },
        onDone: { total in
            print(String(format: "  Total: %.3fs | \"\(out.trimmingCharacters(in: .whitespacesAndNewlines))\"", total))
            sema.signal()
        }
    )
    URLSession(configuration: .ephemeral, delegate: d, delegateQueue: nil).dataTask(with: req).resume()
    sema.wait()
}

let systemPrompt = "Return only the corrected text. No explanations."
let userPrompt = "Fix grammar: Sharper product judgment captured in working note."

runTest(label: "qwen3:0.6b (LOCAL — fully offline)", model: "qwen3:0.6b",
        system: systemPrompt, prompt: userPrompt)

print("\n✅ Done"); exit(0)
