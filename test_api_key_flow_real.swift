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
    var onFirstToken: (TimeInterval) -> Void
    var onDone: (Error?, TimeInterval) -> Void
    var error: Error?
    let start: Date
    var seenFirstToken = false

    init(start: Date, onFirstToken: @escaping (TimeInterval) -> Void, onToken: @escaping (String, TimeInterval) -> Void, onDone: @escaping (Error?, TimeInterval) -> Void) {
        self.start = start; self.onFirstToken = onFirstToken; self.onToken = onToken; self.onDone = onDone
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let status = httpResponse.statusCode
            self.error = NSError(domain: "OllamaAPI", code: status, userInfo: [NSLocalizedDescriptionKey: "Ollama Cloud returned HTTP \(status)"])
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunkStr = String(data: data, encoding: .utf8) else { return }
        
        // print("[RAW] \(chunkStr.replacingOccurrences(of: "\n", with: "\\n"))")
        
        let localBox = buf
        localBox.value += chunkStr
        
        var searchRange = localBox.value.startIndex
        while let newlineRange = localBox.value.range(of: "\n", range: searchRange..<localBox.value.endIndex) {
            let line = String(localBox.value[searchRange..<newlineRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            searchRange = newlineRange.upperBound

            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: lineData),
               let content = decoded.response, !content.isEmpty {
                   if !seenFirstToken {
                       seenFirstToken = true
                       onFirstToken(-start.timeIntervalSinceNow)
                   }
                onToken(content, -start.timeIntervalSinceNow)
            }
        }
        localBox.value = String(localBox.value[searchRange...])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let actualError = self.error ?? error
        onDone(actualError, -start.timeIntervalSinceNow)
    }
}

func testAPIKeyFlow() {
    print("Testing against real config...")
    let configURL = URL(fileURLWithPath: "/Users/namansinha/.ai-assistant/config.json")
    let configData = try! Data(contentsOf: configURL)
    let configObj = try! JSONSerialization.jsonObject(with: configData) as! [String: Any]
    let apiKey = configObj["apiKey"] as! String
    let model = configObj["defaultModel"] as! String
    print("Using model: \(model)")

    let body = try! JSONEncoder().encode(GenerateRequest(
        model: model,
        system: "You are a text transformation assistant.",
        prompt: "Say hi."
    ))
    
    var req = URLRequest(url: URL(string: "https://ollama.com/api/generate")!)
    req.httpMethod = "POST"
    req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    let start = Date(); let sema = DispatchSemaphore(value: 0)
    var out = ""

    let d = Delegate(start: start,
        onFirstToken: { t in print("--- Time to First Token (TTFT): \(t)s ---") },
        onToken: { tok, t in
            out += tok
        },
        onDone: { err, total in
            print("\nTotal Time: \(total)s")
            if let e = err {
                print("Finished with ERROR: \(e.localizedDescription)")
            } else {
                print("Finished SUCCESSFULLY with output: \(out)")
            }
            sema.signal()
        }
    )
    URLSession(configuration: .ephemeral, delegate: d, delegateQueue: nil).dataTask(with: req).resume()
    sema.wait()
}

testAPIKeyFlow()

exit(0)
