import Foundation

/// Async client for the SimpleTex image-to-LaTeX OCR API.
///
/// Endpoint: `POST https://server.simpletex.net/api/simpletex_ocr`
/// Auth: `token` header with a User Access Token.
/// Body: `multipart/form-data` with `file` (image) and `rec_mode=formula`.
enum SimpletexService {

    struct SimpletexError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let endpoint = URL(string: "https://server.simpletex.net/api/simpletex_ocr")!

    /// Sends `imageData` (PNG) to SimpleTex and returns the recognised LaTeX string.
    static func recognise(imageData: Data, token: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // -- file field --
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.png\"\r\n")
        body.append("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")

        // -- rec_mode field --
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"rec_mode\"\r\n\r\n")
        body.append("formula\r\n")

        // -- closing boundary --
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SimpletexError(message: "Invalid response from SimpleTex")
        }

        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            throw SimpletexError(message: "SimpleTex returned HTTP \(httpResponse.statusCode): \(bodyStr)")
        }

        // Parse JSON: { "status": true, "res": { "type": "formula", "info": "..." } }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let res = json["res"] as? [String: Any],
              let latex = res["info"] as? String else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            throw SimpletexError(message: "Could not parse SimpleTex response: \(bodyStr)")
        }

        return latex
    }
}

// MARK: - Data + String Append

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
