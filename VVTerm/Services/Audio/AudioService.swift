import Foundation
import Combine
import os.log

@MainActor
class AudioService: NSObject, ObservableObject {
    private let logger = Logger.audio
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var partialTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionStatus: AudioPermissionManager.PermissionStatus = .notDetermined

    // Services
    private let permissionManager = AudioPermissionManager()
    private let speechRecognitionService = SpeechRecognitionService()
    private let audioCaptureService = AudioCaptureService()

    private var activeProvider: TranscriptionProvider = .system

    override init() {
        super.init()
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Permission status
        permissionManager.$permissionStatus
            .assign(to: &$permissionStatus)

        // Speech recognition
        speechRecognitionService.$transcribedText
            .assign(to: &$transcribedText)

        speechRecognitionService.$partialTranscription
            .assign(to: &$partialTranscription)

        // Audio capture
        audioCaptureService.$audioLevel
            .assign(to: &$audioLevel)

        audioCaptureService.$recordingDuration
            .assign(to: &$recordingDuration)
    }

    // MARK: - Permission Handling

    func requestPermissions(includeSpeech: Bool) async -> Bool {
        return await permissionManager.requestPermissions(includeSpeech: includeSpeech)
    }

    func checkPermissions(includeSpeech: Bool) async -> Bool {
        return await permissionManager.checkPermissions(includeSpeech: includeSpeech)
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        activeProvider = .system

        let hasPermissions = await checkPermissions(includeSpeech: true)
        if !hasPermissions {
            let granted = await requestPermissions(includeSpeech: true)
            guard granted else {
                throw RecordingError.permissionDenied
            }
        }

        speechRecognitionService.resetTranscriptions()
        audioCaptureService.cancel()

        try await startAppleSpeech()
        isRecording = true
    }

    func stopRecording() async -> String {
        isRecording = false
        _ = audioCaptureService.stop()
        let finalText = await speechRecognitionService.stopRecognition()
        speechRecognitionService.resetTranscriptions()
        return finalText
    }

    func cancelRecording() {
        isRecording = false

        audioCaptureService.cancel()
        speechRecognitionService.cancelRecognition()
        speechRecognitionService.resetTranscriptions()
        transcribedText = ""
        partialTranscription = ""
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError {
        case permissionDenied
        case speechRecognitionUnavailable
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return String(localized: "Microphone permission is required. The microphone will be automatically requested when recording starts.")
            case .speechRecognitionUnavailable:
                return String(localized: "Speech recognition is not available. Please enable Siri in System Settings > Siri & Spotlight.")
            case .recordingFailed:
                return String(localized: "Failed to start recording. Please check microphone permissions in System Settings > Privacy & Security > Microphone.")
            }
        }
    }

    // MARK: - Apple Speech

    private func startAppleSpeech() async throws {
        guard speechRecognitionService.isAvailable else {
            throw RecordingError.speechRecognitionUnavailable
        }

        audioCaptureService.bufferHandler = { [weak speechRecognitionService] buffer in
            speechRecognitionService?.appendAudioBuffer(buffer)
        }

        try await speechRecognitionService.startRecognition()
        do {
            try audioCaptureService.start()
        } catch {
            throw RecordingError.recordingFailed
        }
    }

}
