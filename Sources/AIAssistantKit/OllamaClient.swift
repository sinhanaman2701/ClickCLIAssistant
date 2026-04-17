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

    public func transform(text: String, using skill: Skill) async throws -> String {
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
            """),
        ]))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw AppError.ollamaUnavailable(detail)
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        if let content = decoded.message?.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        if let response = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines), !response.isEmpty {
            return response
        }

        throw AppError.ollamaUnavailable("Ollama returned an empty response")
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream = false
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}
