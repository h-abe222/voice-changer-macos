import Foundation
import Combine
import AVFoundation
import CoreAudio
import AudioToolbox

/// オーディオエンジンの状態
public enum EngineState: String, Codable, Sendable {
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
}

import SwiftUI

extension EngineState {
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

/// レイテンシモード
public enum LatencyMode: String, Codable, Sendable {
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
public struct EngineStats: Sendable {
    public var inputLevelDb: Float = -60
    public var outputLevelDb: Float = -60
    public var cpuLoad: Float = 0
    public var xruns: Int = 0
    public var droppedFrames: Int = 0
}

/// オーディオエンジン
/// マイク入力をキャプチャし、DSP処理を行い、仮想マイクに出力する
public final class AudioEngine: @unchecked Sendable {

    // MARK: - Properties

    private var state: EngineState = .idle
    private var latencyMode: LatencyMode = .balanced
    private var currentPresetId: String = "default"
    private var inputDeviceId: AudioDeviceID = 0
    private var isMonitorEnabled: Bool = false

    private var stats = EngineStats()

    // Publishers
    private let statsSubject = PassthroughSubject<EngineStats, Never>()
    private let stateSubject = PassthroughSubject<EngineState, Never>()

    public var statsPublisher: AnyPublisher<EngineStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }

    public var statePublisher: AnyPublisher<EngineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // Core Audio
    private var inputUnit: AudioComponentInstance?
    private var inputBuffer: [Float] = []

    // DSP
    private let dspChain = DSPChain()

    // 共有メモリ出力
    private let sharedMemoryOutput = SharedMemoryOutput()

    // スレッド
    private let processingQueue = DispatchQueue(label: "com.voicechanger.audioengine", qos: .userInteractive)
    private let lock = NSLock()

    // 統計
    private var lastStatsUpdate = Date()
    private var frameCount: Int = 0

    // MARK: - Initialization

    public init() {
        inputBuffer = [Float](repeating: 0, count: latencyMode.frameSize)
    }

    // MARK: - Public Methods

    /// エンジンの準備
    public func prepare() async throws {
        lock.lock()
        defer { lock.unlock() }

        guard state == .idle else { return }

        // マイク権限チェック
        let authorized = await requestMicrophonePermission()
        guard authorized else {
            throw AudioEngineError.permissionDenied
        }

        // デフォルト入力デバイス取得
        inputDeviceId = try getDefaultInputDevice()

        // 共有メモリ接続
        try sharedMemoryOutput.connect()

        // AudioUnit設定
        try setupInputUnit()

        state = .armed
        stateSubject.send(state)
    }

    /// Speaking開始
    public func startSpeaking() throws {
        lock.lock()
        defer { lock.unlock() }

        guard state == .armed || state == .degraded else {
            throw AudioEngineError.invalidState
        }

        guard let inputUnit = inputUnit else {
            throw AudioEngineError.invalidState
        }

        // 共有メモリをアクティブに
        sharedMemoryOutput.activate()

        // AudioUnit開始
        let status = AudioOutputUnitStart(inputUnit)
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        state = .running
        stateSubject.send(state)

        logInfo("AudioEngine started", category: .audio)
    }

    /// Speaking停止
    public func stopSpeaking() {
        lock.lock()
        defer { lock.unlock() }

        if let inputUnit = inputUnit {
            AudioOutputUnitStop(inputUnit)
        }

        sharedMemoryOutput.deactivate()

        if state == .running {
            state = .armed
            stateSubject.send(state)
        }

        logInfo("AudioEngine stopped", category: .audio)
    }

    /// 完全停止
    public func stop() {
        stopSpeaking()

        lock.lock()
        defer { lock.unlock() }

        if let inputUnit = inputUnit {
            AudioComponentInstanceDispose(inputUnit)
            self.inputUnit = nil
        }

        sharedMemoryOutput.disconnect()

        state = .idle
        stateSubject.send(state)
    }

    /// 入力デバイス設定
    public func setInputDevice(_ deviceId: AudioDeviceID) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let inputUnit = inputUnit else { return }

        var deviceId = deviceId
        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceId,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        self.inputDeviceId = deviceId
    }

    /// プリセット設定
    public func setPreset(_ presetId: String) async {
        currentPresetId = presetId
        await dspChain.loadPreset(presetId)
    }

    /// レイテンシモード設定
    public func setLatencyMode(_ mode: LatencyMode) async {
        lock.lock()
        latencyMode = mode
        inputBuffer = [Float](repeating: 0, count: mode.frameSize)
        lock.unlock()

        await dspChain.setFrameSize(mode.frameSize)
    }

    /// モニター設定
    public func setMonitor(enabled: Bool) {
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

    private func getDefaultInputDevice() throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceId
        )

        guard status == noErr else {
            throw AudioEngineError.deviceNotFound
        }

        return deviceId
    }

    private func setupInputUnit() throws {
        // AudioComponent検索
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioEngineError.deviceNotFound
        }

        // AudioUnit作成
        var unit: AudioComponentInstance?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let inputUnit = unit else {
            throw AudioEngineError.audioUnitError(status)
        }

        self.inputUnit = inputUnit

        // 入力を有効化
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // Input element
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        // 出力を無効化（入力のみ使用）
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // Output element
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        // デバイス設定
        var deviceId = inputDeviceId
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceId,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        // フォーマット設定 (48kHz, mono, Float32)
        var format = AudioStreamBasicDescription(
            mSampleRate: 48000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            inputUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,  // Input element's output
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        // コールバック設定
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }

        // 初期化
        status = AudioUnitInitialize(inputUnit)
        guard status == noErr else {
            throw AudioEngineError.audioUnitError(status)
        }
    }

    /// オーディオ入力コールバックで呼ばれる処理
    fileprivate func handleAudioInput(
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) {
        guard let inputUnit = inputUnit else { return }

        // バッファリスト作成
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: inNumberFrames * 4,
                mData: nil
            )
        )

        // バッファ確保
        let bufferSize = Int(inNumberFrames)
        if inputBuffer.count < bufferSize {
            inputBuffer = [Float](repeating: 0, count: bufferSize)
        }

        inputBuffer.withUnsafeMutableBufferPointer { ptr in
            bufferList.mBuffers.mData = UnsafeMutableRawPointer(ptr.baseAddress!)
            bufferList.mBuffers.mDataByteSize = UInt32(bufferSize * MemoryLayout<Float>.size)

            // 入力データ取得
            var timeStamp = AudioTimeStamp()
            let status = AudioUnitRender(
                inputUnit,
                nil,
                &timeStamp,
                1,  // Input element
                inNumberFrames,
                &bufferList
            )

            guard status == noErr else { return }
        }

        // DSP処理（非同期）
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // AudioFrame作成
            let samples = Array(self.inputBuffer.prefix(bufferSize))
            var frame = AudioFrame(samples: samples, sampleRate: 48000)

            // DSP処理
            Task {
                await self.dspChain.process(&frame)

                // 共有メモリに書き込み
                self.sharedMemoryOutput.write(frame.samples)

                // 統計更新
                self.updateStats(frame: frame)
            }
        }
    }

    private func updateStats(frame: AudioFrame) {
        // RMS計算（入力レベル）
        let rms = sqrt(frame.samples.reduce(0) { $0 + $1 * $1 } / Float(frame.samples.count))
        let db = 20 * log10(max(rms, 1e-10))

        stats.inputLevelDb = db
        stats.outputLevelDb = db  // TODO: 出力後のレベル計算

        frameCount += 1

        // 100msごとに統計を更新
        let now = Date()
        if now.timeIntervalSince(lastStatsUpdate) >= 0.1 {
            statsSubject.send(stats)
            lastStatsUpdate = now
        }
    }
}

// MARK: - Audio Callback

private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    engine.handleAudioInput(inNumberFrames: inNumberFrames, ioData: ioData)
    return noErr
}

// MARK: - Errors

public enum AudioEngineError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case invalidState
    case audioUnitError(OSStatus)
    case sharedMemoryError(Error)

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
        case .sharedMemoryError(let error):
            return "Shared memory error: \(error.localizedDescription)"
        }
    }
}
