import Foundation

/// アプリケーション定数
public enum Constants {

    // MARK: - Audio Settings

    public enum Audio {
        /// デフォルトサンプルレート
        public static let sampleRate: Int = 48000

        /// デフォルトチャンネル数（モノラル）
        public static let channels: Int = 1

        /// フレームサイズ（サンプル数）
        public enum FrameSize {
            public static let ultraLow: Int = 128   // ~2.7ms
            public static let balanced: Int = 256   // ~5.3ms
            public static let highQuality: Int = 512 // ~10.7ms
        }

        /// リングバッファ設定
        public enum Buffer {
            /// バッファサイズ（ミリ秒）
            public static let sizeMs: Int = 200
        }

        /// レイテンシ目標（ミリ秒）
        public enum LatencyTarget {
            public static let ultraLow: Double = 20
            public static let balanced: Double = 40
            public static let highQuality: Double = 60
        }
    }

    // MARK: - DSP Settings

    public enum DSP {
        /// ハイパスフィルタのカットオフ周波数
        public static let hpfCutoffHz: Float = 80

        /// AGCターゲットレベル（dB）
        public static let agcTargetDb: Float = -18

        /// リミッターのシーリング（dB）
        public static let limiterCeilingDb: Float = -1

        /// クロスフェード時間（ミリ秒）
        public static let crossfadeMs: Int = 30

        /// ピッチシフト範囲（半音）
        public static let pitchRange: ClosedRange<Float> = -12...12

        /// フォルマントシフト範囲
        public static let formantRange: ClosedRange<Float> = -1...1
    }

    // MARK: - UI Settings

    public enum UI {
        /// VUメーターの更新間隔（ミリ秒）
        public static let meterUpdateIntervalMs: Int = 50

        /// VUメーターの範囲（dB）
        public static let meterMinDb: Float = -60
        public static let meterMaxDb: Float = 0
    }

    // MARK: - Virtual Device

    public enum VirtualDevice {
        /// 仮想マイクの名前
        public static let micName = "VoiceChanger Virtual Mic"

        /// 仮想スピーカーの名前
        public static let spkName = "VoiceChanger Virtual Speaker"

        /// メーカー名
        public static let manufacturer = "VoiceChanger"

        /// バンドルID
        public static let bundleId = "com.voicechanger.virtualmicdriver"
    }

    // MARK: - App Info

    public enum App {
        public static let name = "Voice Changer"
        public static let version = "1.0.0"
        public static let bundleId = "com.voicechanger.app"
    }

    // MARK: - Performance Thresholds

    public enum Performance {
        /// CPU使用率の警告閾値（%）
        public static let cpuWarningThreshold: Float = 80

        /// XRUNの警告閾値
        public static let xrunWarningThreshold: Int = 3

        /// 自動DEGRADEDモードへの移行閾値
        public static let degradedTriggerXruns: Int = 5
    }
}
