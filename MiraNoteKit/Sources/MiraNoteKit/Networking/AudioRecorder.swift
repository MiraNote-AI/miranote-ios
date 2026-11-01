import AVFoundation
import Foundation

/// Records microphone audio to a file and hands back the bytes. Abstracted so
/// view models can be driven by `MockAudioRecorder` in tests instead of the
/// real microphone.
@MainActor
public protocol AudioRecording {
    var isRecording: Bool { get }
    /// The input level right now, 0 (silence) to 1 (loud), for a live
    /// meter; 0 while not recording.
    var level: Float { get }
    func start() async throws
    func stop() async throws -> Data
}

/// Turns a recorder's average power into a meter level.
public enum AudioLevel {
    /// The quietest power the meter shows; anything below reads as silence.
    public static let floorDecibels: Float = -50

    /// Maps decibels (-160 ... 0, as `AVAudioRecorder` reports them)
    /// linearly from `floorDecibels` ... 0 onto 0 ... 1.
    public static func normalized(power decibels: Float) -> Float {
        min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }
}

public enum RecordingError: Error, LocalizedError {
    case microphonePermissionDenied
    case noAudioCaptured

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return String(appCopy: "Microphone access is off. Enable it in Settings to record voice notes.")
        case .noAudioCaptured:
            return String(appCopy: "No audio was captured. Try recording again.")
        }
    }
}

/// Measures recorded audio without playing it.
public enum AudioInfo {
    /// Duration of an encoded clip; 0 when the bytes are not decodable.
    public static func duration(of data: Data) -> TimeInterval {
        (try? AVAudioPlayer(data: data))?.duration ?? 0
    }
}

/// Test double: no microphone, returns canned bytes and a fixed level
/// while recording.
@MainActor
public final class MockAudioRecorder: AudioRecording {
    /// Mock recorders on right now, all instances together: what a -UITEST
    /// probe reads to tell that no microphone was left on.
    public private(set) static var liveCount = 0

    public private(set) var isRecording = false {
        didSet {
            if isRecording != oldValue { Self.liveCount += isRecording ? 1 : -1 }
        }
    }
    /// What `level` reads while recording.
    public var recordingLevel: Float
    private let cannedAudio: Data
    /// How long the mic takes to come up (the real one waits on the audio
    /// session, and on the permission alert the first time).
    private let startDelay: Duration

    public init(
        cannedAudio: Data = Data("mock-audio".utf8),
        recordingLevel: Float = 0.6,
        startDelay: Duration = .zero
    ) {
        self.cannedAudio = cannedAudio
        self.recordingLevel = recordingLevel
        self.startDelay = startDelay
    }

    public var level: Float { isRecording ? recordingLevel : 0 }

    public func start() async throws {
        if startDelay > .zero { try? await Task.sleep(for: startDelay) }
        isRecording = true
    }

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

    public var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return AudioLevel.normalized(power: recorder.averagePower(forChannel: 0))
    }

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
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
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
