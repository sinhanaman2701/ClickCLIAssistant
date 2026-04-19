import Foundation

// Final diagnostic test for the 4000-word SiliconFlow setup
let wordCount = 4000
let dummyWord = "test "
let dummyText = String(repeating: dummyWord, count: wordCount)

func testFinalSetup() async {
    // The endpoint we just configured in the app
    let url = URL(string: "https://api.siliconflow.cn/v1/ollama/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW", forHTTPHeaderField: "Authorization")
    
    let body: [String: Any] = [
        "model": "gemma3:27b-cloud",
        "system": "You are a helpful assistant.",
        "prompt": "Please summarize this text into one sentence: \(dummyText)",
        "options": ["num_ctx": 32768],
        "stream": false
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("Sending 4000-word request (~\(dummyText.count) chars) to SiliconFlow...")
        
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = Date().timeIntervalSince(start)
        
        let httpResponse = response as? HTTPURLResponse
        print("Status Code: \(httpResponse?.statusCode ?? 0) (took \(String(format: "%.2f", duration))s)")
        
        if let body = String(data: data, encoding: .utf8) {
            if (200..<300).contains(httpResponse?.statusCode ?? 0) {
                print("SUCCESS!")
                // Print just a snippet of the response to avoid clutter
                if body.count > 200 {
                    print("Response snippet: \(body.prefix(200))...")
                } else {
                    print("Response: \(body)")
                }
            } else {
                print("FAILURE!")
                print("Error Body: \(body)")
            }
        }
    } catch {
        print("Network/Encoding Error: \(error)")
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await testFinalSetup()
    sema.signal()
}
sema.wait()
