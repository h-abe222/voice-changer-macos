import Foundation
import Combine
import AudioEngine

/// アプリケーション全体の状態管理
@MainActor
final class AppController: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var engineState: EngineState = .idle
    @Published var isSpeakingEnabled: Bool = false {
        didSet {
            Task {
                await toggleSpeaking(enabled: isSpeakingEnabled)
            }
        }
    }
    @Published var isMonitorEnabled: Bool = false
    @Published var selectedInputDeviceId: String?
    @Published var selectedPresetId: String = "default"
    @Published var latencyMode: LatencyMode = .balanced

    @Published private(set) var inputLevel: Float = 0.0
    @Published private(set) var outputLevel: Float = 0.0
    @Published private(set) var cpuLoad: Float = 0.0
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    private let audioEngine: AudioEngine
    private let settingsStore: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.audioEngine = AudioEngine()
        self.settingsStore = SettingsStore()
        loadSettings()
        setupBindings()
    }

    // MARK: - Public Methods

    func start() async {
        do {
            try await audioEngine.prepare()
            engineState = .armed
        } catch {
            engineState = .error
            lastError = error.localizedDescription
        }
    }

    func shutdown() async {
        await audioEngine.stop()
        engineState = .idle
        saveSettings()
    }

    func selectInputDevice(_ deviceId: String) {
        selectedInputDeviceId = deviceId
        Task {
            await audioEngine.setInputDevice(deviceId)
        }
    }

    func selectPreset(_ presetId: String) {
        selectedPresetId = presetId
        Task {
            await audioEngine.setPreset(presetId)
        }
    }

    func setLatencyMode(_ mode: LatencyMode) {
        latencyMode = mode
        Task {
            await audioEngine.setLatencyMode(mode)
        }
    }

    // MARK: - Private Methods

    private func toggleSpeaking(enabled: Bool) async {
        if enabled {
            do {
                try await audioEngine.startSpeaking()
                engineState = .running
            } catch {
                engineState = .error
                lastError = error.localizedDescription
                isSpeakingEnabled = false
            }
        } else {
            await audioEngine.stopSpeaking()
            engineState = .armed
        }
    }

    private func setupBindings() {
        audioEngine.statsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.inputLevel = stats.inputLevelDb
                self?.outputLevel = stats.outputLevelDb
                self?.cpuLoad = stats.cpuLoad
            }
            .store(in: &cancellables)

        audioEngine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.engineState = state
            }
            .store(in: &cancellables)
    }

    private func loadSettings() {
        let settings = settingsStore.load()
        selectedInputDeviceId = settings.inputDeviceId
        selectedPresetId = settings.presetId
        latencyMode = settings.latencyMode
        isMonitorEnabled = settings.isMonitorEnabled
    }

    private func saveSettings() {
        let settings = Settings(
            inputDeviceId: selectedInputDeviceId,
            presetId: selectedPresetId,
            latencyMode: latencyMode,
            isMonitorEnabled: isMonitorEnabled
        )
        settingsStore.save(settings)
    }
}
