import Foundation

// Test 1: qwen3.5:cloud via generate
// Test 2: See if a local model is available

func test(model: String, prompt: String) async -> (ttft: TimeInterval, total: TimeInterval)? {
    let body = try! JSONSerialization.data(withJSONObject: [
        "model": model,
        "prompt": prompt,
        "stream": true
    ])
    var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
    req.httpMethod = "POST"
    req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let start = Date()
    var ttft: TimeInterval?

    do {
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        print("[\(model)] HTTP \(status)")
        for try await _ in bytes.lines {
            if ttft == nil { ttft = -start.timeIntervalSinceNow }
        }
        return (ttft ?? 0, -start.timeIntervalSinceNow)
    } catch {
        print("[\(model)] ERROR: \(error)")
        return nil
    }
}

// List available local models
func listModels() async -> [String] {
    guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://localhost:11434/api/tags")!),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let models = json["models"] as? [[String: Any]] else { return [] }
    return models.compactMap { $0["name"] as? String }
}

Task {
    let models = await listModels()
    print("[AVAILABLE MODELS] \(models)")
    print()

    // Time the cloud model with a bare minimal prompt
    print("--- Testing qwen3.5:cloud (bare minimal) ---")
    if let r = await test(model: "qwen3.5:cloud", prompt: "Say hi") {
        print(String(format: "TTFT: %.2fs | Total: %.2fs\n", r.ttft, r.total))
    }

    // Time any local model if available
    let localModels = models.filter { !$0.contains(":cloud") }
    if let local = localModels.first {
        print("--- Testing local model: \(local) ---")
        if let r = await test(model: local, prompt: "Say hi") {
            print(String(format: "TTFT: %.2fs | Total: %.2fs\n", r.ttft, r.total))
        }
    } else {
        print("[INFO] No local models found — only cloud models installed")
    }

    exit(0)
}

RunLoop.main.run()
