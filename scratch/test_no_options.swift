import Foundation

// Testing ollama.com/api/generate with 4000 words BUT NO OPTIONS
let wordCount = 4000
let dummyWord = "word "
let dummyText = String(repeating: dummyWord, count: wordCount)

func testNoOptions() async {
    let url = URL(string: "https://ollama.com/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Using the real key from config
    request.setValue("Bearer d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW", forHTTPHeaderField: "Authorization")
    
    let body: [String: Any] = [
        "model": "gemma3:27b-cloud",
        "system": "You are a helpful assistant.",
        "prompt": "Summarize this: \(dummyText)",
        "stream": false
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("Sending 4000-word request WITHOUT options to ollama.com...")
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        print("Status Code: \((response as? HTTPURLResponse)?.statusCode ?? 0) in \(-start.timeIntervalSinceNow)s")
        if let body = String(data: data, encoding: .utf8) {
            print("Response: \(body.prefix(100))...")
        }
    } catch {
        print("Error: \(error)")
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await testNoOptions()
    sema.signal()
}
sema.wait()
