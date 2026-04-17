import Foundation
import Network

public enum BridgeServer {
    public static let host = "127.0.0.1"
    public static let port: UInt16 = 48765

    public static func run() async throws {
        let config = try ConfigStore.load()
        let service = BridgeService(config: config)

        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        let queue = DispatchQueue(label: "click-assistant.bridge")

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receiveRequest(on: connection, data: Data(), service: service)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Browser bridge listening on http://\(host):\(port)")
            case .failed(let error):
                fputs("Bridge failed: \(error.localizedDescription)\n", stderr)
            default:
                break
            }
        }
        listener.start(queue: queue)

        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func receiveRequest(on connection: NWConnection, data: Data, service: BridgeService) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { chunk, _, isComplete, error in
            if let error {
                send(response: .internalError(error.localizedDescription), on: connection)
                return
            }

            var buffer = data
            if let chunk {
                buffer.append(chunk)
            }

            if let request = HTTPRequestParser.parse(buffer) {
                Task {
                    let response = await handle(request: request, service: service)
                    send(response: response, on: connection)
                }
                return
            }

            if isComplete {
                send(response: .badRequest("Malformed HTTP request"), on: connection)
                return
            }

            receiveRequest(on: connection, data: buffer, service: service)
        }
    }

    private static func handle(request: HTTPRequest, service: BridgeService) async -> HTTPResponse {
        if request.method == "OPTIONS" {
            return .noContent()
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .okJSON(#"{"ok":true}"#)
        case ("GET", "/skills"):
            do {
                let payload = try await service.skillsPayload()
                return .okData(payload)
            } catch {
                return .internalError(error.localizedDescription)
            }
        case ("POST", "/transform"):
            do {
                let payload = try await service.transformPayload(from: request.body)
                return .okData(payload)
            } catch {
                return .badRequest(error.localizedDescription)
            }
        default:
            return .notFound
        }
    }

    private static func send(response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private actor BridgeService {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func skillsPayload() throws -> Data {
        let skills = try loadSkills().map { SkillSummary(id: $0.id, name: $0.name, description: $0.description) }
        return try JSONEncoder().encode(SkillsResponse(skills: skills))
    }

    func transformPayload(from body: Data) async throws -> Data {
        let request = try JSONDecoder().decode(TransformRequest.self, from: body)
        let skills = try loadSkills()
        guard let skill = skills.first(where: { $0.id == request.skillID }) else {
            throw AppError.invalidSkillFile("Unknown skill id: \(request.skillID)")
        }

        guard let hostURL = URL(string: config.ollamaHost) else {
            throw AppError.ollamaUnavailable("Invalid Ollama host: \(config.ollamaHost)")
        }

        let client = OllamaClient(host: hostURL, model: config.defaultModel)
        let output = try await client.transform(text: request.text, using: skill)
        let response = TransformResponse(skillID: skill.id, skillName: skill.name, output: output)
        return try JSONEncoder().encode(response)
    }

    private func loadSkills() throws -> [Skill] {
        let directory = URL(fileURLWithPath: config.skillsDirectory, isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map(SkillParser.parse(url:))
    }
}

private struct SkillsResponse: Codable {
    let skills: [SkillSummary]
}

private struct SkillSummary: Codable {
    let id: String
    let name: String
    let description: String?
}

private struct TransformRequest: Codable {
    let text: String
    let skillID: String

    enum CodingKeys: String, CodingKey {
        case text
        case skillID = "skillId"
    }
}

private struct TransformResponse: Codable {
    let skillID: String
    let skillName: String
    let output: String

    enum CodingKeys: String, CodingKey {
        case skillID = "skillId"
        case skillName
        case output
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
}

private enum HTTPRequestParser {
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 2 else { return nil }

        let method = String(tokens[0]).uppercased()
        let rawPath = String(tokens[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath

        var contentLength = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            if pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" {
                contentLength = Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }

        let bodyStart = headerRange.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else {
            return nil
        }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(method: method, path: path, body: body)
    }
}

private struct HTTPResponse {
    let statusCode: Int
    let statusText: String
    let body: Data
    let contentType: String

    var data: Data {
        var result = Data()
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        result.append(Data(headers.utf8))
        result.append(body)
        return result
    }

    static func okJSON(_ string: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, statusText: "OK", body: Data(string.utf8), contentType: "application/json")
    }

    static func okData(_ data: Data) -> HTTPResponse {
        HTTPResponse(statusCode: 200, statusText: "OK", body: data, contentType: "application/json")
    }

    static func noContent() -> HTTPResponse {
        HTTPResponse(statusCode: 204, statusText: "No Content", body: Data(), contentType: "text/plain")
    }

    static func badRequest(_ message: String) -> HTTPResponse {
        let json = #"{"error":"\#(escape(message))"}"#
        return HTTPResponse(statusCode: 400, statusText: "Bad Request", body: Data(json.utf8), contentType: "application/json")
    }

    static var notFound: HTTPResponse {
        HTTPResponse(statusCode: 404, statusText: "Not Found", body: Data(#"{"error":"Not found"}"#.utf8), contentType: "application/json")
    }

    static func internalError(_ message: String) -> HTTPResponse {
        let json = #"{"error":"\#(escape(message))"}"#
        return HTTPResponse(statusCode: 500, statusText: "Internal Server Error", body: Data(json.utf8), contentType: "application/json")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
