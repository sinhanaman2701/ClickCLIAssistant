import Foundation

let startTime = Date()

let largeText = String(repeating: "This is a dummy sentence designed to bloat the context window. ", count: 200) // ~12,000 characters

let requestDict: [String: Any] = [
    "model": "qwen3.5:397b-cloud",
    "messages": [
        ["role": "system", "content": "You are a text transformation assistant."],
        ["role": "user", "content": "Skill:\nCorrect the grammar\n\nSelected text:\n\(largeText)"]
    ],
    "stream": true
]

let url = URL(string: "http://localhost:11434/api/chat")!
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.httpBody = try! JSONSerialization.data(withJSONObject: requestDict)
req.setValue("application/json", forHTTPHeaderField: "Content-Type")

Task {
    do {
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        print("Connected to \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        var first = true
        for try await line in bytes.lines {
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
