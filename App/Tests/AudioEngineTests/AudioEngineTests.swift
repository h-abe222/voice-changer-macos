import XCTest
@testable import AudioEngine

final class AudioEngineTests: XCTestCase {

    // MARK: - Engine State Tests

    func testEngineStateDisplayText() {
        XCTAssertEqual(EngineState.idle.displayText, "Idle")
        XCTAssertEqual(EngineState.armed.displayText, "Ready")
        XCTAssertEqual(EngineState.running.displayText, "Running")
        XCTAssertEqual(EngineState.degraded.displayText, "Degraded")
        XCTAssertEqual(EngineState.error.displayText, "Error")
    }

    // MARK: - Latency Mode Tests

    func testLatencyModeFrameSize() {
        XCTAssertEqual(LatencyMode.ultraLow.frameSize, 128)
        XCTAssertEqual(LatencyMode.balanced.frameSize, 256)
        XCTAssertEqual(LatencyMode.highQuality.frameSize, 512)
    }

    // MARK: - Engine Stats Tests

    func testEngineStatsDefaults() {
        let stats = EngineStats()
        XCTAssertEqual(stats.inputLevelDb, -60)
        XCTAssertEqual(stats.outputLevelDb, -60)
        XCTAssertEqual(stats.cpuLoad, 0)
        XCTAssertEqual(stats.xruns, 0)
        XCTAssertEqual(stats.droppedFrames, 0)
    }

    // MARK: - Device Manager Tests

    func testDeviceManagerInitialization() {
        let manager = DeviceManager()

        // デバイスリストが取得できることを確認
        // 注: 実際のデバイスはテスト環境により異なる
        XCTAssertNotNil(manager.inputDevices)
        XCTAssertNotNil(manager.outputDevices)
    }

    func testDeviceTransportTypes() {
        XCTAssertEqual(AudioDevice.TransportType.builtIn.rawValue, "builtIn")
        XCTAssertEqual(AudioDevice.TransportType.usb.rawValue, "usb")
        XCTAssertEqual(AudioDevice.TransportType.bluetooth.rawValue, "bluetooth")
        XCTAssertEqual(AudioDevice.TransportType.virtual.rawValue, "virtual")
    }
}
