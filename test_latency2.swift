import Foundation

let startTime = Date()

let requestDict: [String: Any] = [
    "model": "qwen3.5:397b-cloud",
    "messages": [["role": "system", "content": "You are a text transformation assistant."],
                 ["role": "user", "content": "Correct grammar: i went to stores yesterday and it was good"]],
    "stream": true
]

let url = URL(string: "http://localhost:11434/api/chat")!
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.httpBody = try! JSONSerialization.data(withJSONObject: requestDict)
req.setValue("application/json", forHTTPHeaderField: "Content-Type")

func test() async throws {
    let (bytes, _) = try await URLSession.shared.bytes(for: req)
    
    var fullText = ""
    var buffer = ""
    var lastRender = Date()
    var count = 0
    var ttft: TimeInterval?

    for try await line in bytes.lines {
        // Mock JSON parse
        let chunk = "." // simulating successful decode
        
        if ttft == nil {
            ttft = -startTime.timeIntervalSinceNow
            print("[\(ttft!)] TTFT Received!")
        }
        
        fullText += chunk
        buffer += chunk
        
        if Date().timeIntervalSince(lastRender) > 0.05 {
            print("[\(-startTime.timeIntervalSinceNow)] Flushing buffer of length \(buffer.count)")
            buffer = ""
            lastRender = Date()
        }
        count += 1
    }

    if !buffer.isEmpty {
        print("[\(-startTime.timeIntervalSinceNow)] Final Flush: \(buffer.count)")
    }
    
    print("Total chunks: \(count)")
}

Task {
    do {
        try await test()
        exit(0)
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
