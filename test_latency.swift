import Foundation

let startTime = Date()

let requestDict: [String: Any] = [
    "model": "qwen3.5:397b-cloud",
    "messages": [["role": "user", "content": "Correct grammar: i went to stores yesterday and it was good"]],
    "stream": true
]

let url = URL(string: "http://localhost:11434/api/chat")!
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.httpBody = try! JSONSerialization.data(withJSONObject: requestDict)
req.setValue("application/json", forHTTPHeaderField: "Content-Type")

Task {
    do {
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        var first = true
        for try await _ in bytes.lines {
            if first {
                print("Time to first token: \(-startTime.timeIntervalSinceNow) seconds")
                first = false
            }
        }
        print("Total time: \(-startTime.timeIntervalSinceNow) seconds")
    } catch {
        print("Error: \(error)")
    }
    exit(0)
}

RunLoop.main.run()
