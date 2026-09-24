import Foundation
import Speech

/// Speech never leaves the device. Unsupported locales fail rather than using a server.
enum Transcriber {
    enum Failure: LocalizedError {
        case notAuthorized, unavailable, onDeviceUnavailable, timedOut

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition is turned off for Wrist in Settings."
            case .unavailable: "Speech recognition isn't available right now."
            case .onDeviceUnavailable: "On-device speech recognition is unavailable for this language. No audio was sent to a server. Try a text note instead."
            case .timedOut: "On-device transcription timed out. You can retry this capture."
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    static func transcribe(url: URL, locale: Locale = .current) async throws -> String {
        try Task.checkCancellation()
        guard await requestAuthorization() else { throw Failure.notAuthorized }
        try Task.checkCancellation()
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { throw Failure.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.onDeviceUnavailable }
        guard recognizer.isAvailable else { throw Failure.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true

        let operation = RecognitionOperation()
        defer { withExtendedLifetime(operation) {} }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(recognizer: recognizer, request: request, continuation: continuation)
            }
        } onCancel: {
            operation.finish(.failure(CancellationError()))
        }
    }

    /// The lock protects callback/cancellation/timeout races, including synchronous callbacks
    /// before recognitionTask returns. Never call Speech or resume a continuation under it.
    private final class RecognitionOperation: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: Result<String, Error>?
        private var continuation: CheckedContinuation<String, Error>?
        private var task: SFSpeechRecognitionTask?
        private var recognizer: SFSpeechRecognizer?
        private var timeout: DispatchWorkItem?

        func start(recognizer: SFSpeechRecognizer, request: SFSpeechURLRecognitionRequest,
                   continuation: CheckedContinuation<String, Error>) {
            lock.lock()
            if let completion {
                lock.unlock()
                continuation.resume(with: completion)
                return
            }
            self.continuation = continuation
            self.recognizer = recognizer
            lock.unlock()

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result, result.isFinal {
                    self?.finish(.success(result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else if let error {
                    let nsError = error as NSError
                    // Restrict the no-speech special case to the Speech assistant domain.
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                        self?.finish(.success(""))
                    } else {
                        self?.finish(.failure(error))
                    }
                }
            }
            let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(Failure.timedOut)) }
            lock.lock()
            let alreadyFinished = completion != nil
            if !alreadyFinished {
                self.task = task
                self.timeout = timeout
            }
            lock.unlock()
            if alreadyFinished {
                task.cancel()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
            }
        }

        func finish(_ result: Result<String, Error>) {
            lock.lock()
            guard completion == nil else { lock.unlock(); return }
            completion = result
            let continuation = self.continuation
            let task = self.task
            let timeout = self.timeout
            self.continuation = nil
            self.task = nil
            self.timeout = nil
            self.recognizer = nil
            lock.unlock()
            timeout?.cancel()
            task?.cancel()
            continuation?.resume(with: result)
        }
    }
}
