import Foundation

let startTime = Date()

let requestDict: [String: Any] = [
    "model": "qwen3.5:cloud",
    "messages": [
        ["role": "system", "content": """
        You are a text transformation assistant.
        Only return the transformed text.
        Do not add explanation, framing, or markdown fences unless the input clearly requires it.
        """],
        ["role": "user", "content": """
        Skill:
        Correct the grammar

        Selected text:
        Sharper product judgment, captured in working notes.
        """]
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
        var count = 0
        for try await _ in bytes.lines {
            if first {
                print("Time to first token: \(-startTime.timeIntervalSinceNow) seconds")
                first = false
            }
            count += 1
        }
        print("Total line chunks: \(count)")
        print("Total time: \(-startTime.timeIntervalSinceNow) seconds")
    } catch {
        print("Error: \(error)")
    }
    exit(0)
}

RunLoop.main.run()
