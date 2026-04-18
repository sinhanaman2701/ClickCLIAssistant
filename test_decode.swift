import Foundation

let jsonString = """
{"model":"qwen3.5:397b-cloud","created_at":"2026-04-18T08:19:18.572748213Z","message":{"role":"assistant","content":")\\n-"},"done":false}
"""

struct OllamaResponse: Decodable {
    let message: OllamaMessage?
    let response: String?
    let done: Bool?

    struct OllamaMessage: Decodable {
        let role: String
        let content: String
    }
}

let data = jsonString.data(using: .utf8)!
do {
    let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
    print("Decoded successfully: \(decoded)")
} catch {
    print("Error decoding: \(error)")
}
