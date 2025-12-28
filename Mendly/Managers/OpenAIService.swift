import Foundation
import UIKit

enum OpenAIError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case rateLimited(resetAt: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .rateLimited: return "Daily analysis limit reached. Try again tomorrow."
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        }
    }
}

class OpenAIService {
    static let shared = OpenAIService()

    /// The model used for all LLM requests. Change this in one place.
    static let model = "gpt-4o"

    private let proxyURL = "https://mend.ly/api/analyze"
    private let session = URLSession.shared

    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    var isConfigured: Bool { true }

    /// Send a chat completion request via the Vercel proxy.
    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        model: String = OpenAIService.model,
        temperature: Double = 0.3,
        maxTokens: Int = 4096,
        sessionId: String? = nil
    ) async throws -> String {
        var request = URLRequest(url: URL(string: proxyURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        if let sessionId = sessionId {
            request.addValue(sessionId, forHTTPHeaderField: "X-Session-ID")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw OpenAIError.rateLimited(resetAt: errorJson?["resetAt"] as? String)
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content
    }
}
