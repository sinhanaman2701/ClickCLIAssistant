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
            Task {
                do {
                    let url = host.appending(path: "/api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: AppError.ollamaUnavailable("Ollama returned an error status: \( (response as? HTTPURLResponse)?.statusCode ?? 500 )"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        if let decoded = try? JSONDecoder().decode(OllamaResponse.self, from: data) {
                            if let content = decoded.message?.content, !content.isEmpty {
                                continuation.yield(content)
                            } else if let responseStr = decoded.response, !responseStr.isEmpty {
                                continuation.yield(responseStr)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
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
