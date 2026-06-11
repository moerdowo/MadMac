import Foundation

// Thin URLSession client for the OpenAI API. No SDK dependency.
// Endpoints used: /v1/models, /v1/chat/completions (structured outputs),
// /v1/images/generations, /v1/images/edits (gpt-image-1).

enum AIError: LocalizedError {
    case noKey
    case api(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "No OpenAI API key — add one in Settings → AI."
        case .api(let message): return message
        case .badResponse(let s): return "Unexpected AI response: \(s)"
        }
    }
}

struct OpenAIClient {
    private var key: String {
        get throws {
            guard let key = AIPrefs.loadKey() else { throw AIError.noKey }
            return key
        }
    }

    private func request(_ path: String) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        req.setValue("Bearer \(try key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180
        return req
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let message = ((obj["error"] as? [String: Any])?["message"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw AIError.api(message)
        }
        return obj
    }

    // ── Connection test ────────────────────────────────────────────────────

    func listModels() async throws -> [String] {
        let obj = try await send(try request("models"))
        let data = obj["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }.sorted()
    }

    // ── Structured text (chat completions + json_schema) ──────────────────

    func structured(system: String, user: String,
                    schemaName: String, schema: [String: Any],
                    model: String) async throws -> [String: Any] {
        var req = try request("chat/completions")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let obj = try await send(req)
        guard let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let data = content.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse(String(describing: obj).prefix(200).description)
        }
        return parsed
    }

    // ── Images ─────────────────────────────────────────────────────────────

    func generateImages(prompt: String, size: String, count: Int,
                        quality: String) async throws -> [Data] {
        var req = try request("images/generations")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": prompt,
            "n": count,
            "size": size,
            "quality": quality,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let obj = try await send(req)
        return imagePayload(obj)
    }

    func editImage(_ imageURL: URL, prompt: String, quality: String) async throws -> Data {
        var req = try request("images/edits")
        req.httpMethod = "POST"
        let boundary = "madmac-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var form = Data()
        func field(_ name: String, _ value: String) {
            form.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "gpt-image-1")
        field("prompt", prompt)
        field("quality", quality)
        let imageData = try Data(contentsOf: imageURL)
        let ext = imageURL.pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : ext == "webp" ? "image/webp" : "image/jpeg"
        form.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(imageURL.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        form.append(imageData)
        form.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = form

        let obj = try await send(req)
        guard let first = imagePayload(obj).first else {
            throw AIError.badResponse("no image in edit response")
        }
        return first
    }

    private func imagePayload(_ obj: [String: Any]) -> [Data] {
        let rows = obj["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            (row["b64_json"] as? String).flatMap { Data(base64Encoded: $0) }
        }
    }
}
