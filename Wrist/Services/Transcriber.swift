import Foundation
import Speech

/// On-device speech-to-text for recorded audio files.
enum Transcriber {
    enum Failure: LocalizedError {
        case notAuthorized, unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition is turned off for Wrist in Settings."
            case .unavailable: "Speech recognition isn't available right now."
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(url: URL, locale: Locale = .current) async throws -> String {
        guard await requestAuthorization() else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { throw Failure.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    // 1110 = "No speech detected" — treat as an empty capture, not a failure.
                    if (error as NSError).code == 1110 {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
