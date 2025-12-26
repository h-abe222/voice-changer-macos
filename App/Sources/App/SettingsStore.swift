import Foundation

/// アプリケーション設定
struct Settings: Codable {
    var inputDeviceId: String?
    var presetId: String
    var latencyMode: LatencyMode
    var isMonitorEnabled: Bool

    static let `default` = Settings(
        inputDeviceId: nil,
        presetId: "default",
        latencyMode: .balanced,
        isMonitorEnabled: false
    )
}

/// 設定の永続化
final class SettingsStore {
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "VoiceChangerSettings"

    func load() -> Settings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: settingsKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: settingsKey)
    }
}
