import Foundation
import Combine
import AVFoundation
import DSP

/// オーディオエンジンの状態
public enum EngineState: String, Codable {
    case idle       // 未初期化
    case armed      // 準備完了
    case running    // 処理中
    case degraded   // 品質低下モード
    case error      // エラー

    public var displayText: String {
        switch self {
        case .idle: return "Idle"
        case .armed: return "Ready"
        case .running: return "Running"
        case .degraded: return "Degraded"
        case .error: return "Error"
        }
    }

    public var color: Color {
        switch self {
        case .idle: return .gray
        case .armed: return .yellow
        case .running: return .green
        case .degraded: return .orange
        case .error: return .red
        }
    }
}

import SwiftUI

/// レイテンシモード
public enum LatencyMode: String, Codable {
    case ultraLow    // 128 samples (~2.7ms)
    case balanced    // 256 samples (~5.3ms)
    case highQuality // 512 samples (~10.7ms)

    public var frameSize: Int {
        switch self {
        case .ultraLow: return 128
        case .balanced: return 256
        case .highQuality: return 512
        }
    }
}

/// エンジン統計情報
public struct EngineStats {
    public var inputLevelDb: Float = -60
    public var outputLevelDb: Float = -60
    public var cpuLoad: Float = 0
    public var xruns: Int = 0
    public var droppedFrames: Int = 0
}

/// オーディオエンジン
/// マイク入力をキャプチャし、DSP処理を行い、仮想マイクに出力する
public actor AudioEngine {

    // MARK: - Properties

    private var state: EngineState = .idle
    private var latencyMode: LatencyMode = .balanced
    private var currentPresetId: String = "default"
    private var inputDeviceId: String?
    private var isMonitorEnabled: Bool = false

    private var stats = EngineStats()

    // Publishers
    private let statsSubject = PassthroughSubject<EngineStats, Never>()
    private let stateSubject = PassthroughSubject<EngineState, Never>()

    public nonisolated var statsPublisher: AnyPublisher<EngineStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }

    public nonisolated var statePublisher: AnyPublisher<EngineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // Core Audio
    private var audioUnit: AudioUnit?
    private let dspChain = DSPChain()

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// エンジンの準備
    public func prepare() async throws {
        guard state == .idle else { return }

        // マイク権限チェック
        let authorized = await requestMicrophonePermission()
        guard authorized else {
            throw AudioEngineError.permissionDenied
        }

        // オーディオセッション設定
        try setupAudioSession()

        state = .armed
        stateSubject.send(state)
    }

    /// Speaking開始
    public func startSpeaking() async throws {
        guard state == .armed || state == .running else {
            throw AudioEngineError.invalidState
        }

        // AudioUnitを開始
        try startAudioUnit()

        state = .running
        stateSubject.send(state)
    }

    /// Speaking停止
    public func stopSpeaking() async {
        stopAudioUnit()

        if state == .running {
            state = .armed
            stateSubject.send(state)
        }
    }

    /// 完全停止
    public func stop() async {
        await stopSpeaking()
        teardownAudioSession()
        state = .idle
        stateSubject.send(state)
    }

    /// 入力デバイス設定
    public func setInputDevice(_ deviceId: String) async {
        inputDeviceId = deviceId
        // TODO: デバイス切り替え実装
    }

    /// プリセット設定
    public func setPreset(_ presetId: String) async {
        currentPresetId = presetId
        await dspChain.loadPreset(presetId)
    }

    /// レイテンシモード設定
    public func setLatencyMode(_ mode: LatencyMode) async {
        latencyMode = mode
        await dspChain.setFrameSize(mode.frameSize)
    }

    /// モニター設定
    public func setMonitor(enabled: Bool) async {
        isMonitorEnabled = enabled
    }

    // MARK: - Private Methods

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func setupAudioSession() throws {
        // macOSではAudioSessionは不要だが、将来のiOS対応を見据えて
        // ここでCore Audio HAL設定を行う
    }

    private func teardownAudioSession() {
        // クリーンアップ
    }

    private func startAudioUnit() throws {
        // TODO: Core Audio AudioUnit実装
        // 1. AudioComponentDescription設定
        // 2. AudioUnit作成
        // 3. フォーマット設定 (48kHz, mono, Float32)
        // 4. コールバック設定
        // 5. 開始
    }

    private func stopAudioUnit() {
        // TODO: AudioUnit停止
    }
}

// MARK: - Errors

public enum AudioEngineError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case invalidState
    case audioUnitError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        case .deviceNotFound:
            return "Audio device not found."
        case .invalidState:
            return "Invalid engine state."
        case .audioUnitError(let status):
            return "Audio Unit error: \(status)"
        }
    }
}
