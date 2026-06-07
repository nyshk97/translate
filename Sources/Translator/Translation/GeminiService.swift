import Foundation

/// Gemini（vision）への画像翻訳ストリーミングクライアント。テキスト経路とは別系統。
struct GeminiService: Sendable {
    static let modelName = "gemini-2.5-flash"

    enum ServiceError: LocalizedError {
        case missingKey
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Gemini の API キーが未設定です（設定 → APIキー）"
            case .http(let code, let body):
                return "Gemini エラー (\(code)): \(body.prefix(200))"
            }
        }
    }

    private let model = GeminiService.modelName
    private let prompt = """
    Read all the text in this image and translate it. If the text is Japanese, \
    translate it into natural English; otherwise translate it into natural Japanese. \
    Output only the translation, with no explanations, labels, or quotes.
    """

    /// TLS コネクションを温める。
    func warmUp() {
        guard let key = KeychainStore.get(.gemini), !key.isEmpty else { return }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)") else { return }
        Task { _ = try? await URLSession.shared.data(from: url) }
    }

    func streamImageTranslation(imageData: Data, mimeType: String) -> AsyncThrowingStream<String, Error> {
        let model = self.model
        let prompt = self.prompt
        let base64 = imageData.base64EncodedString()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = KeychainStore.get(.gemini), !key.isEmpty else {
                        throw ServiceError.missingKey
                    }
                    let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(key)"
                    guard let url = URL(string: urlStr) else { throw ServiceError.http(0, "bad url") }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "contents": [[
                            "parts": [
                                ["text": prompt],
                                ["inline_data": ["mime_type": mimeType, "data": base64]],
                            ],
                        ]],
                        "generationConfig": ["temperature": 0.3],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServiceError.http(0, "no response")
                    }
                    guard http.statusCode == 200 else {
                        var msg = ""
                        for try await line in bytes.lines { msg += line }
                        throw ServiceError.http(http.statusCode, msg)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(GeminiChunk.self, from: data) {
                            for part in chunk.candidates?.first?.content?.parts ?? [] {
                                if let t = part.text, !t.isEmpty { continuation.yield(t) }
                            }
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

private struct GeminiChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
