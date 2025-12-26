import Foundation
import Accelerate

/// オーディオフレーム
public struct AudioFrame {
    public var samples: [Float]
    public var sampleRate: Int
    public var timestamp: UInt64

    public init(samples: [Float], sampleRate: Int = 48000, timestamp: UInt64 = 0) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = timestamp
    }

    public var count: Int { samples.count }

    public static func silence(frameSize: Int, sampleRate: Int = 48000) -> AudioFrame {
        AudioFrame(samples: [Float](repeating: 0, count: frameSize), sampleRate: sampleRate)
    }
}

/// DSP処理チェーン
public actor DSPChain {

    // MARK: - Properties

    private var frameSize: Int = 256
    private var sampleRate: Int = 48000

    private var hpf: HighPassFilter
    private var noiseSuppressor: NoiseSuppressor
    private var agc: AutoGainControl
    private var pitchShifter: PitchShifter
    private var formantShifter: FormantShifter
    private var equalizer: Equalizer
    private var limiter: Limiter

    private var currentPreset: VoicePreset = .default

    // MARK: - Initialization

    public init() {
        self.hpf = HighPassFilter(cutoffHz: 80, sampleRate: sampleRate)
        self.noiseSuppressor = NoiseSuppressor()
        self.agc = AutoGainControl()
        self.pitchShifter = PitchShifter()
        self.formantShifter = FormantShifter()
        self.equalizer = Equalizer()
        self.limiter = Limiter()
    }

    // MARK: - Public Methods

    /// フレームサイズ設定
    public func setFrameSize(_ size: Int) {
        frameSize = size
    }

    /// プリセット読み込み
    public func loadPreset(_ presetId: String) {
        currentPreset = VoicePreset.load(id: presetId) ?? .default
        applyPreset(currentPreset)
    }

    /// 音声処理
    public func process(_ frame: inout AudioFrame) {
        // 1. ハイパスフィルタ（DC除去、低周波ノイズ除去）
        hpf.process(&frame)

        // 2. ノイズ抑制
        if currentPreset.noiseSuppressionEnabled {
            noiseSuppressor.process(&frame)
        }

        // 3. 自動ゲイン調整
        if currentPreset.agcEnabled {
            agc.process(&frame)
        }

        // 4. ピッチシフト
        if currentPreset.pitchShift != 0 {
            pitchShifter.process(&frame)
        }

        // 5. フォルマントシフト
        if currentPreset.formantShift != 0 {
            formantShifter.process(&frame)
        }

        // 6. イコライザ
        equalizer.process(&frame)

        // 7. リミッター（クリッピング防止）
        limiter.process(&frame)
    }

    /// バイパス処理（変換なし）
    public func bypass(_ frame: inout AudioFrame) {
        // 何もしない（パススルー）
    }

    // MARK: - Private Methods

    private func applyPreset(_ preset: VoicePreset) {
        pitchShifter.setSemitones(preset.pitchShift)
        formantShifter.setShift(preset.formantShift)
        equalizer.setGains(low: preset.eqLow, mid: preset.eqMid, high: preset.eqHigh)
        noiseSuppressor.setStrength(preset.noiseSuppressionStrength)
        agc.setTargetLevel(preset.agcTargetDb)
    }
}

// MARK: - Voice Preset

public struct VoicePreset: Codable, Identifiable {
    public let id: String
    public var name: String

    // Pitch & Formant
    public var pitchShift: Float = 0          // -12 to +12 semitones
    public var formantShift: Float = 0        // -1.0 to +1.0

    // EQ (dB)
    public var eqLow: Float = 0               // -12 to +12
    public var eqMid: Float = 0
    public var eqHigh: Float = 0

    // Processing
    public var noiseSuppressionEnabled: Bool = true
    public var noiseSuppressionStrength: Float = 0.5  // 0 to 1
    public var agcEnabled: Bool = true
    public var agcTargetDb: Float = -18

    public static let `default` = VoicePreset(id: "default", name: "Default")

    public static let maleToFemale = VoicePreset(
        id: "male_to_female",
        name: "Male to Female",
        pitchShift: 4,
        formantShift: 0.3,
        eqHigh: 2
    )

    public static let femaleToMale = VoicePreset(
        id: "female_to_male",
        name: "Female to Male",
        pitchShift: -4,
        formantShift: -0.3,
        eqLow: 2
    )

    public static func load(id: String) -> VoicePreset? {
        switch id {
        case "default": return .default
        case "male_to_female": return .maleToFemale
        case "female_to_male": return .femaleToMale
        default: return nil
        }
    }
}

// MARK: - DSP Modules

/// ハイパスフィルタ
public class HighPassFilter {
    private var cutoffHz: Float
    private var sampleRate: Int
    private var previousSample: Float = 0
    private var alpha: Float

    public init(cutoffHz: Float, sampleRate: Int) {
        self.cutoffHz = cutoffHz
        self.sampleRate = sampleRate
        self.alpha = 1.0 / (1.0 + 2.0 * .pi * cutoffHz / Float(sampleRate))
    }

    public func process(_ frame: inout AudioFrame) {
        for i in 0..<frame.count {
            let input = frame.samples[i]
            let output = alpha * (previousSample + input - frame.samples[max(0, i-1)])
            frame.samples[i] = output
            previousSample = output
        }
    }
}

/// ノイズ抑制
public class NoiseSuppressor {
    private var strength: Float = 0.5

    public func setStrength(_ value: Float) {
        strength = max(0, min(1, value))
    }

    public func process(_ frame: inout AudioFrame) {
        // 簡易的なノイズゲート実装
        // TODO: WebRTC NSまたはRNNoiseを統合
        let threshold: Float = 0.01 * (1 - strength)
        for i in 0..<frame.count {
            if abs(frame.samples[i]) < threshold {
                frame.samples[i] *= 0.1
            }
        }
    }
}

/// 自動ゲイン調整
public class AutoGainControl {
    private var targetDb: Float = -18
    private var currentGain: Float = 1.0
    private let attackTime: Float = 0.01
    private let releaseTime: Float = 0.1

    public func setTargetLevel(_ db: Float) {
        targetDb = db
    }

    public func process(_ frame: inout AudioFrame) {
        // RMSレベル計算
        var rms: Float = 0
        vDSP_rmsqv(frame.samples, 1, &rms, vDSP_Length(frame.count))

        let currentDb = 20 * log10(max(rms, 1e-10))
        let targetGain = pow(10, (targetDb - currentDb) / 20)

        // スムーズなゲイン変更
        let alpha = currentDb < targetDb ? attackTime : releaseTime
        currentGain = currentGain * (1 - alpha) + targetGain * alpha
        currentGain = max(0.1, min(10, currentGain))

        // ゲイン適用
        var gain = currentGain
        vDSP_vsmul(frame.samples, 1, &gain, &frame.samples, 1, vDSP_Length(frame.count))
    }
}

/// ピッチシフター
public class PitchShifter {
    private var semitones: Float = 0

    public func setSemitones(_ value: Float) {
        semitones = max(-12, min(12, value))
    }

    public func process(_ frame: inout AudioFrame) {
        guard semitones != 0 else { return }
        // TODO: Phase Vocoder実装
        // 現時点ではプレースホルダー
    }
}

/// フォルマントシフター
public class FormantShifter {
    private var shift: Float = 0

    public func setShift(_ value: Float) {
        shift = max(-1, min(1, value))
    }

    public func process(_ frame: inout AudioFrame) {
        guard shift != 0 else { return }
        // TODO: LPC分析によるフォルマント制御
        // 現時点ではプレースホルダー
    }
}

/// イコライザ（3バンド）
public class Equalizer {
    private var lowGain: Float = 1.0
    private var midGain: Float = 1.0
    private var highGain: Float = 1.0

    public func setGains(low: Float, mid: Float, high: Float) {
        lowGain = pow(10, low / 20)
        midGain = pow(10, mid / 20)
        highGain = pow(10, high / 20)
    }

    public func process(_ frame: inout AudioFrame) {
        // TODO: Biquadフィルタによる3バンドEQ実装
        // 現時点では全体ゲインのみ適用
        let avgGain = (lowGain + midGain + highGain) / 3
        var gain = avgGain
        vDSP_vsmul(frame.samples, 1, &gain, &frame.samples, 1, vDSP_Length(frame.count))
    }
}

/// リミッター
public class Limiter {
    private var ceiling: Float = 0.95  // -0.5dB

    public func setCeiling(_ db: Float) {
        ceiling = pow(10, db / 20)
    }

    public func process(_ frame: inout AudioFrame) {
        for i in 0..<frame.count {
            if frame.samples[i] > ceiling {
                frame.samples[i] = ceiling
            } else if frame.samples[i] < -ceiling {
                frame.samples[i] = -ceiling
            }
        }
    }
}
