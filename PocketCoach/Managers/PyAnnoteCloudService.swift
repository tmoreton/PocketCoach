import Foundation
import FluidAudio

enum PyAnnoteError: Error, LocalizedError {
    case invalidAPIKey
    case uploadFailed(statusCode: Int, message: String)
    case jobSubmissionFailed(statusCode: Int, message: String)
    case jobFailed(status: String)
    case pollingTimeout
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "PyAnnote API key not configured"
        case .uploadFailed(let code, let msg): return "Upload failed (HTTP \(code)): \(msg)"
        case .jobSubmissionFailed(let code, let msg): return "Job submission failed (HTTP \(code)): \(msg)"
        case .jobFailed(let status): return "Diarization job failed with status: \(status)"
        case .pollingTimeout: return "Diarization job timed out after 5 minutes"
        case .invalidResponse: return "Invalid response from pyannote.ai"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

class PyAnnoteCloudService {
    static let shared = PyAnnoteCloudService()

    private let baseURL = "https://api.pyannote.ai/v1"
    private let session = URLSession.shared
    private let pollInterval: UInt64 = 5_000_000_000 // 5 seconds in nanoseconds
    private let maxPollAttempts = 60 // 5 minutes total

    private var apiKey: String {
        Constants.pyAnnoteAPIKey
    }

    // MARK: - Public API

    func diarize(audio: [Float], sampleRate: Double, numSpeakers: Int?) async throws -> [TimedSpeakerSegment] {
        guard !apiKey.isEmpty && apiKey != "TODO" else {
            throw PyAnnoteError.invalidAPIKey
        }

        #if DEBUG
        print("[PyAnnote] Starting cloud diarization: \(audio.count) samples, \(String(format: "%.0f", sampleRate))Hz")
        #endif

        // Step 1: Encode audio as WAV
        let wavData = encodeWAV(samples: audio, sampleRate: Int(sampleRate))

        #if DEBUG
        print("[PyAnnote] WAV encoded: \(wavData.count) bytes")
        #endif

        // Step 2: Create media key and get presigned upload URL
        let mediaKey = "media://pocketcoach-\(UUID().uuidString)"
        let presignedURL = try await createMediaInput(mediaKey: mediaKey)

        #if DEBUG
        print("[PyAnnote] Got presigned upload URL for \(mediaKey)")
        #endif

        // Step 3: Upload WAV data to presigned URL
        try await uploadMedia(wavData: wavData, to: presignedURL)

        #if DEBUG
        print("[PyAnnote] Upload complete")
        #endif

        // Step 4: Submit diarization job with media:// key
        let jobId = try await submitJob(mediaKey: mediaKey, numSpeakers: numSpeakers)

        #if DEBUG
        print("[PyAnnote] Job submitted: \(jobId)")
        #endif

        // Step 5: Poll for completion
        let segments = try await pollForResult(jobId: jobId)

        #if DEBUG
        print("[PyAnnote] Diarization complete: \(segments.count) segments")
        #endif

        return segments
    }

    // MARK: - WAV Encoding

    /// Encode [Float] audio (assumed mono) as 16-bit PCM WAV Data
    private func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: Int32(16)) // chunk size
        data.append(littleEndian: Int16(1))  // PCM format
        data.append(littleEndian: numChannels)
        data.append(littleEndian: Int32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)

        // Convert Float samples [-1.0, 1.0] to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            data.append(littleEndian: int16Value)
        }

        return data
    }

    // MARK: - API Calls

    /// POST /v1/media/input with media:// key → presigned upload URL
    private func createMediaInput(mediaKey: String) async throws -> String {
        #if DEBUG
        print("[PyAnnote] Step 2: Creating media input for key: \(mediaKey)")
        #endif

        var request = URLRequest(url: URL(string: "\(baseURL)/media/input")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": mediaKey])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PyAnnoteError.invalidResponse
        }

        #if DEBUG
        print("[PyAnnote] Step 2 response: HTTP \(httpResponse.statusCode)")
        if let body = String(data: data, encoding: .utf8) {
            print("[PyAnnote] Step 2 body: \(body)")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PyAnnoteError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["url"] as? String else {
            throw PyAnnoteError.invalidResponse
        }

        return url
    }

    /// PUT WAV data to presigned URL
    private func uploadMedia(wavData: Data, to urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("[PyAnnote] Step 3 FAILED: Invalid presigned URL: \(urlString)")
            #endif
            throw PyAnnoteError.invalidResponse
        }

        #if DEBUG
        print("[PyAnnote] Step 3: Uploading \(wavData.count) bytes to presigned URL")
        print("[PyAnnote] Step 3 URL host: \(url.host ?? "unknown")")
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PyAnnoteError.invalidResponse
        }

        #if DEBUG
        print("[PyAnnote] Step 3 response: HTTP \(httpResponse.statusCode)")
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            print("[PyAnnote] Step 3 body: \(body.prefix(500))")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PyAnnoteError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// POST /v1/diarize with media:// key → job ID
    private func submitJob(mediaKey: String, numSpeakers: Int?) async throws -> String {
        #if DEBUG
        print("[PyAnnote] Step 4: Submitting diarization job for \(mediaKey), numSpeakers=\(String(describing: numSpeakers))")
        #endif

        var request = URLRequest(url: URL(string: "\(baseURL)/diarize")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "url": mediaKey,
            "model": "precision-2"
        ]
        if let numSpeakers = numSpeakers {
            body["numSpeakers"] = numSpeakers
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PyAnnoteError.invalidResponse
        }

        #if DEBUG
        print("[PyAnnote] Step 4 response: HTTP \(httpResponse.statusCode)")
        if let body = String(data: data, encoding: .utf8) {
            print("[PyAnnote] Step 4 body: \(body)")
        }
        #endif

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PyAnnoteError.jobSubmissionFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["jobId"] as? String else {
            throw PyAnnoteError.invalidResponse
        }

        return jobId
    }

    /// GET /v1/jobs/{jobId} — poll until complete or failed
    private func pollForResult(jobId: String) async throws -> [TimedSpeakerSegment] {
        for attempt in 1...maxPollAttempts {
            try await Task.sleep(nanoseconds: pollInterval)

            var request = URLRequest(url: URL(string: "\(baseURL)/jobs/\(jobId)")!)
            request.httpMethod = "GET"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PyAnnoteError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PyAnnoteError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw PyAnnoteError.invalidResponse
            }

            #if DEBUG
            print("[PyAnnote] Poll \(attempt)/\(maxPollAttempts): status=\(status)")
            #endif

            switch status {
            case "succeeded":
                guard let output = json["output"] as? [String: Any],
                      let diarization = output["diarization"] as? [[String: Any]] else {
                    throw PyAnnoteError.invalidResponse
                }
                return convertSegments(diarization)

            case "failed", "error":
                throw PyAnnoteError.jobFailed(status: status)

            default:
                // processing / queued — keep polling
                continue
            }
        }

        throw PyAnnoteError.pollingTimeout
    }

    // MARK: - Response Conversion

    /// Convert pyannote.ai segments to TimedSpeakerSegment
    private func convertSegments(_ segments: [[String: Any]]) -> [TimedSpeakerSegment] {
        return segments.compactMap { seg in
            guard let speaker = seg["speaker"] as? String,
                  let start = seg["start"] as? Double,
                  let end = seg["end"] as? Double else {
                return nil
            }

            let confidence = seg["confidence"] as? Double ?? 0.8

            return TimedSpeakerSegment(
                speakerId: speaker,
                embedding: [],  // Cloud API doesn't return embeddings
                startTimeSeconds: Float(start),
                endTimeSeconds: Float(end),
                qualityScore: Float(confidence)
            )
        }
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(littleEndian value: Int16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func append(littleEndian value: Int32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
