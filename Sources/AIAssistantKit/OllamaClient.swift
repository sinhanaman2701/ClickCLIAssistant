import Foundation

public struct OllamaClient: Sendable {
    public let host: URL
    public let model: String

    public init(host: URL, model: String) {
        self.host = host
        self.model = model
    }

    public func healthCheck() async throws {
        let url = host.appending(path: "/api/tags")
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.ollamaUnavailable("Unexpected response from \(url.absoluteString)")
        }
    }

    public func transform(text: String, using skill: Skill) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let url = host.appending(path: "/api/chat")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            do {
                request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [
                    .init(role: "system", content: """
                    You are a text transformation assistant.
                    Only return the transformed text.
                    Do not add explanation, framing, or markdown fences unless the input clearly requires it.
                    """),
                    .init(role: "user", content: """
                    Skill:
                    \(skill.prompt)

                    Selected text:
                    \(text)
                    """)
                ]))
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let streamer = StreamDelegate(continuation: continuation)
            let session = URLSession(configuration: .ephemeral, delegate: streamer, delegateQueue: nil)
            let task = session.dataTask(with: request)
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
            
            task.resume()
        }
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    
    // We use a mutable buffer to handle chunk fragmentation
    private let jsonBuffer = UnsafeMutableTransferBox("")

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunkStr = String(data: data, encoding: .utf8) else { return }
        
        let localBox = jsonBuffer
        localBox.value += chunkStr
        
        let lines = localBox.value.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return } // Wait until we hit a newline boundary
        
        for i in 0..<(lines.count - 1) {
            let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            
            if let decoded = try? JSONDecoder().decode(OllamaResponse.self, from: lineData) {
                if let content = decoded.message?.content, !content.isEmpty {
                    continuation.yield(content)
                } else if let responseStr = decoded.response, !responseStr.isEmpty {
                    continuation.yield(responseStr)
                }
            }
        }
        
        // Keep the last segment in the buffer in case it was a fractured chunk (no newline at the end)
        localBox.value = String(lines.last ?? "")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

private final class UnsafeMutableTransferBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream = true
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}
