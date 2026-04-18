import Foundation

private struct ChatRequest: Encodable {
    let model: String
    let messages: [String]
    let stream = true
}

let request = ChatRequest(model: "test_model", messages: ["test_message"])
let data = try JSONEncoder().encode(request)
let jsonString = String(data: data, encoding: .utf8)!

print("Encoded JSON: \(jsonString)")
