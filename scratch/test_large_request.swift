import Foundation

// A simple script to test the Ollama transformation with large text
let wordCount = 4000
let dummyWord = "word "
let dummyText = String(repeating: dummyWord, count: wordCount)

let config = """
{
  "apiKey" : "d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW",
  "defaultModel" : "gemma3:27b-cloud",
  "ollamaHost" : "http://localhost:11434"
}
"""

struct GenerateRequest: Encodable {
    let model: String
    let system: String
    let prompt: String
    let stream: Bool = false // Non-streaming for easier testing
    let options: [String: [String: Int]]? // Simulating the structure
}

func testRequest() async {
    let url = URL(string: "https://ollama.com/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer d227cf7eced44e1f8f8ea339c7e73c4d.p8CccmbGY8QmW1JH0zD0kNvW", forHTTPHeaderField: "Authorization")
    
    let body: [String: Any] = [
        "model": "gemma3:27b-cloud",
        "system": "You are a text transformation assistant.",
        "prompt": "Skill: Summarize\\n\\nSelected text: \(dummyText)",
        "options": ["num_ctx": 32768],
        "stream": false
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("Sending request with ~\(dummyText.count) characters...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        print("Status Code: \(httpResponse?.statusCode ?? 0)")
        
        if let body = String(data: data, encoding: .utf8) {
            print("Response Body: \(body)")
        }
    } catch {
        print("Error: \(error)")
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await testRequest()
    sema.signal()
}
sema.wait()
