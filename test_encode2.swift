import Foundation

struct ChatMessage: Encodable {
    let role: String
    let content: String
}

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream = true
}

let req = ChatRequest(model: "kimi", messages: [ChatMessage(role: "user", content: "hello")])
if let data = try? JSONEncoder().encode(req), let str = String(data: data, encoding: .utf8) {
    print("ENCODED: \(str)")
} else {
    print("FAILED TO ENCODE")
}
