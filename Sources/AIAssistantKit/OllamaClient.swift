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
            let url = host.appending(path: "/api/generate")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            do {
                request.httpBody = try JSONEncoder().encode(GenerateRequest(
                    model: model,
                    system: """
                    You are a text transformation assistant.
                    Only return the transformed text.
                    Do not add explanation, framing, or markdown fences unless the input clearly requires it.
                    """,
                    prompt: """
                    Skill:
                    \(skill.prompt)

                    Selected text:
                    \(text)
                    """
                ))
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let streamer = OllamaStreamDelegate(continuation: continuation)
            let session = URLSession(configuration: .ephemeral, delegate: streamer, delegateQueue: nil)
            let task = session.dataTask(with: request)

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }

            task.resume()
        }
    }
}

// MARK: - URLSession Streaming Delegate

private final class OllamaStreamDelegate: NSObject, URLSessionDataDelegate, Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let jsonBuffer = UnsafeMutableTransferBox("")

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunkStr = String(data: data, encoding: .utf8) else { return }

        let box = jsonBuffer
        box.value += chunkStr

        // Split on newlines — /api/generate emits one JSON object per line
        let lines = box.value.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return }

        for i in 0..<(lines.count - 1) {
            let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }

            if let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: lineData),
               let content = decoded.response, !content.isEmpty {
                continuation.yield(content)
            }
        }

        // Retain any partial line at the end for next chunk
        box.value = String(lines.last ?? "")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

// MARK: - Models

private final class UnsafeMutableTransferBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

private struct GenerateRequest: Encodable {
    let model: String
    let system: String
    let prompt: String
    let stream = true
}

private struct GenerateResponse: Decodable {
    let response: String?
    let done: Bool?
}
