import Foundation

/// Groq（OpenAI 互換）へのストリーミング翻訳クライアント。
struct TranslationService: Sendable {
    enum ServiceError: LocalizedError {
        case missingKey
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Groq の API キーが未設定です（設定 → APIキー）"
            case .http(let code, let body):
                return "Groq エラー (\(code)): \(body.prefix(200))"
            case .badResponse:
                return "応答が不正です"
            }
        }
    }

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let modelsURL = URL(string: "https://api.groq.com/openai/v1/models")!
    private let model = "llama-3.3-70b-versatile"

    /// TLS / HTTP2 コネクションを温めて初回ハンドシェイク往復を消す。
    func warmUp() {
        guard let key = KeychainStore.get(.groq), !key.isEmpty else { return }
        var req = URLRequest(url: modelsURL)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        Task { _ = try? await URLSession.shared.data(for: req) }
    }

    /// トークン delta を逐次 yield するストリーム。
    /// instruction を渡すと方向プロンプトの後ろに追記する（トーン・ニュアンス調整用）。
    func stream(text: String, direction: TranslationDirection, instruction: String? = nil) -> AsyncThrowingStream<String, Error> {
        let endpoint = self.endpoint
        let model = self.model
        let systemContent: String = {
            guard let instruction, !instruction.isEmpty else { return direction.systemPrompt }
            return direction.systemPrompt + " " + instruction
        }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = KeychainStore.get(.groq), !key.isEmpty else {
                        throw ServiceError.missingKey
                    }
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "system", "content": systemContent],
                            ["role": "user", "content": text],
                        ],
                        "stream": true,
                        "temperature": 0.3,
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServiceError.badResponse
                    }
                    guard http.statusCode == 200 else {
                        var msg = ""
                        for try await line in bytes.lines { msg += line }
                        throw ServiceError.http(http.statusCode, msg)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
