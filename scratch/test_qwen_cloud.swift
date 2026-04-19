import Foundation

// Diagnostic test for 4000 words using qwen3.5:cloud
let wordCount = 4000
let dummyWord = "test "
let dummyText = String(repeating: dummyWord, count: wordCount)

func testQwenCloud() async {
    // Using the endpoint that verified working for "Say hi"
    let url = URL(string: "https://ollama.com/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW", forHTTPHeaderField: "Authorization")
    
    let body: [String: Any] = [
        "model": "qwen3.5:cloud",
        "system": "You are a helpful assistant.",
        "prompt": "Summarize this in one sentence: \(dummyText)",
        "stream": false
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("Testing 4000 words with qwen3.5:cloud...")
        
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = Date().timeIntervalSince(start)
        
        let httpResponse = response as? HTTPURLResponse
        print("Status Code: \(httpResponse?.statusCode ?? 0)")
        print("Time Taken: \(String(format: "%.2f", duration))s")
        
        if let body = String(data: data, encoding: .utf8) {
            if (200..<300).contains(httpResponse?.statusCode ?? 0) {
                print("RESULT: SUCCESS")
                print("Response snippet: \(body.prefix(200))...")
            } else {
                print("RESULT: FAILURE")
                print("Error Detail: \(body)")
            }
        }
    } catch {
        print("RESULT: ERROR")
        print("Error: \(error)")
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await testQwenCloud()
    sema.signal()
}
sema.wait()
