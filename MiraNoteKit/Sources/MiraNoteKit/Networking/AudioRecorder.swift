import AVFoundation
import Foundation

/// Records microphone audio to a file and hands back the bytes. Abstracted so
/// view models can be driven by `MockAudioRecorder` in tests instead of the
/// real microphone.
@MainActor
public protocol AudioRecording {
    var isRecording: Bool { get }
    func start() async throws
    func stop() async throws -> Data
}

public enum RecordingError: Error, LocalizedError {
    case microphonePermissionDenied
    case noAudioCaptured

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is off. Enable it in Settings to record voice notes."
        case .noAudioCaptured:
            return "No audio was captured. Try recording again."
        }
    }
}

/// Test double: no microphone, returns canned bytes.
@MainActor
public final class MockAudioRecorder: AudioRecording {
    public private(set) var isRecording = false
    private let cannedAudio: Data

    public init(cannedAudio: Data = Data("mock-audio".utf8)) {
        self.cannedAudio = cannedAudio
    }

    public func start() async throws { isRecording = true }

    public func stop() async throws -> Data {
        isRecording = false
        return cannedAudio
    }
}

/// Records mic input to an m4a file via `AVAudioRecorder`.
@MainActor
public final class AudioRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?
    private let fileURL: URL

    public init() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("miranote-dictation.m4a")
    }

    public var isRecording: Bool { recorder?.isRecording ?? false }

    public func start() async throws {
        try await ensurePermission()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        #endif
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        guard recorder.record() else { throw RecordingError.noAudioCaptured }
        self.recorder = recorder
    }

    public func stop() async throws -> Data {
        recorder?.stop()
        recorder = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        guard !data.isEmpty else { throw RecordingError.noAudioCaptured }
        return data
    }

    private func ensurePermission() async throws {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw RecordingError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            if !granted { throw RecordingError.microphonePermissionDenied }
        @unknown default:
            return
        }
        #endif
    }
}
