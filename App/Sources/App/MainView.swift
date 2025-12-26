import SwiftUI
import AudioEngine

struct MainView: View {
    @EnvironmentObject private var appController: AppController

    var body: some View {
        VStack(spacing: 20) {
            // ヘッダー
            HeaderView()

            // ステータス表示
            StatusView(state: appController.engineState, error: appController.lastError)

            Divider()

            // メインコントロール
            SpeakingToggle(isEnabled: $appController.isSpeakingEnabled)

            // VUメーター
            VUMeterView(
                inputLevel: appController.inputLevel,
                outputLevel: appController.outputLevel
            )

            Divider()

            // 設定パネル
            SettingsPanel()

            Spacer()

            // フッター
            FooterView(cpuLoad: appController.cpuLoad)
        }
        .padding()
        .frame(minWidth: 350, minHeight: 450)
        .task {
            await appController.start()
        }
    }
}

// MARK: - Sub Views

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text("Voice Changer")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("for macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct StatusView: View {
    let state: EngineState
    let error: String?

    var body: some View {
        HStack {
            Circle()
                .fill(state.color)
                .frame(width: 10, height: 10)

            Text(state.displayText)
                .font(.subheadline)

            Spacer()

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SpeakingToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $isEnabled) {
                HStack {
                    Image(systemName: isEnabled ? "mic.fill" : "mic.slash.fill")
                        .foregroundStyle(isEnabled ? .green : .secondary)
                    Text("Speaking Mode")
                        .font(.headline)
                }
            }
            .toggleStyle(.switch)
            .padding()
            .background(isEnabled ? Color.green.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(isEnabled ? "Your voice is being transformed" : "Click to start voice transformation")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct VUMeterView: View {
    let inputLevel: Float
    let outputLevel: Float

    var body: some View {
        VStack(spacing: 8) {
            MeterRow(label: "IN", level: inputLevel)
            MeterRow(label: "OUT", level: outputLevel)
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MeterRow: View {
    let label: String
    let level: Float

    private var normalizedLevel: Double {
        // dBを0-1の範囲に正規化 (-60dB to 0dB)
        let clampedDb = max(-60, min(0, Double(level)))
        return (clampedDb + 60) / 60
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 30)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterGradient)
                        .frame(width: geometry.size.width * normalizedLevel)
                }
            }
            .frame(height: 12)

            Text(String(format: "%.1f dB", level))
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 50)
        }
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct SettingsPanel: View {
    @EnvironmentObject private var appController: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            // プリセット選択
            HStack {
                Text("Preset")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $appController.selectedPresetId) {
                    Text("Default").tag("default")
                    Text("Male to Female").tag("male_to_female")
                    Text("Female to Male").tag("female_to_male")
                    Text("Deep Voice").tag("deep")
                    Text("High Voice").tag("high")
                }
                .labelsHidden()
            }

            // レイテンシモード
            HStack {
                Text("Latency")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $appController.latencyMode) {
                    Text("Ultra Low").tag(LatencyMode.ultraLow)
                    Text("Balanced").tag(LatencyMode.balanced)
                    Text("High Quality").tag(LatencyMode.highQuality)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // モニター
            Toggle("Monitor (hear your transformed voice)", isOn: $appController.isMonitorEnabled)
                .font(.subheadline)
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FooterView: View {
    let cpuLoad: Float

    var body: some View {
        HStack {
            Image(systemName: "cpu")
            Text(String(format: "CPU: %.1f%%", cpuLoad))
                .font(.caption)
                .monospacedDigit()

            Spacer()

            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .environmentObject(AppController())
}
