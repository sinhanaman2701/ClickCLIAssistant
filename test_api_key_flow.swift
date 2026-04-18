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
    var onDone: (Error?, TimeInterval) -> Void
    var error: Error?
    let start: Date

    init(start: Date, onToken: @escaping (String, TimeInterval) -> Void, onDone: @escaping (Error?, TimeInterval) -> Void) {
        self.start = start; self.onToken = onToken; self.onDone = onDone
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let status = httpResponse.statusCode
            self.error = NSError(domain: "OllamaAPI", code: status, userInfo: [NSLocalizedDescriptionKey: "Ollama Cloud returned HTTP \(status)"])
            // Cancel the stream if we hit an error
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunkStr = String(data: data, encoding: .utf8) else { return }
        
        // Print the raw data to see if we get an HTML error page or JSON error
        print("[DEBUG DATA] \(chunkStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        let localBox = buf
        localBox.value += chunkStr
        
        let lines = localBox.value.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return }
        
        var searchRange = localBox.value.startIndex
        while let newlineRange = localBox.value.range(of: "\n", range: searchRange..<localBox.value.endIndex) {
            let line = String(localBox.value[searchRange..<newlineRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            searchRange = newlineRange.upperBound

            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: lineData),
               let content = decoded.response, !content.isEmpty {
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

func testAPIKeyFlow(apiKey: String) {
    print("\n═══ Testing API Key Flow ═══")
    
    let body = try! JSONEncoder().encode(GenerateRequest(
        model: "kimi-k2.5:cloud",
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
        onToken: { tok, t in
            out += tok
        },
        onDone: { err, total in
            print("Total Time: \(total)s")
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

// Test with a fake API key
testAPIKeyFlow(apiKey: "sk-ollama-fakekey123456789")

exit(0)
