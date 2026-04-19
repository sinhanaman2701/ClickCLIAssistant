import Foundation

// Testing SiliconFlow with OpenAI-compatible Chat Completions API
let wordCount = 4000
let dummyWord = "test "
let dummyText = String(repeating: dummyWord, count: wordCount)

func testSiliconFlowOpenAI() async {
    // Official SiliconFlow OpenAI-compatible endpoint
    let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW", forHTTPHeaderField: "Authorization")
    
    // Using a known SiliconFlow model ID (Gemma 2 27B)
    let body: [String: Any] = [
        "model": "google/gemma-2-27b-it",
        "messages": [
            ["role": "system", "content": "You are a helpful assistant."],
            ["role": "user", "content": "Please summarize this text into one sentence: \(dummyText)"]
        ],
        "stream": false,
        "max_tokens": 512
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("Sending 4000-word OpenAI-style request to SiliconFlow...")
        
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = Date().timeIntervalSince(start)
        
        let httpResponse = response as? HTTPURLResponse
        print("Status Code: \(httpResponse?.statusCode ?? 0) (took \(String(format: "%.2f", duration))s)")
        
        if let body = String(data: data, encoding: .utf8) {
            if (200..<300).contains(httpResponse?.statusCode ?? 0) {
                print("SUCCESS!")
                print("Response Body: \(body.prefix(300))...")
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
    await testSiliconFlowOpenAI()
    sema.signal()
}
sema.wait()
