import XCTest
@testable import DSP

final class DSPChainTests: XCTestCase {

    var dspChain: DSPChain!

    override func setUp() async throws {
        dspChain = DSPChain()
    }

    override func tearDown() async throws {
        dspChain = nil
    }

    // MARK: - Audio Frame Tests

    func testAudioFrameSilence() {
        let frame = AudioFrame.silence(frameSize: 256)
        XCTAssertEqual(frame.count, 256)
        XCTAssertTrue(frame.samples.allSatisfy { $0 == 0 })
    }

    func testAudioFrameCreation() {
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4]
        let frame = AudioFrame(samples: samples, sampleRate: 48000)

        XCTAssertEqual(frame.count, 4)
        XCTAssertEqual(frame.sampleRate, 48000)
        XCTAssertEqual(frame.samples, samples)
    }

    // MARK: - DSP Chain Tests

    func testProcessDoesNotCrash() async {
        var frame = AudioFrame.silence(frameSize: 256)
        await dspChain.process(&frame)
        XCTAssertEqual(frame.count, 256)
    }

    func testBypassDoesNotModify() async {
        let originalSamples: [Float] = (0..<256).map { Float($0) / 256.0 }
        var frame = AudioFrame(samples: originalSamples)

        await dspChain.bypass(&frame)
        XCTAssertEqual(frame.samples, originalSamples)
    }

    // MARK: - Limiter Tests

    func testLimiterClamps() {
        let limiter = Limiter()
        var frame = AudioFrame(samples: [1.5, -1.5, 0.5, -0.5])

        limiter.process(&frame)

        XCTAssertLessThanOrEqual(frame.samples[0], 0.95)
        XCTAssertGreaterThanOrEqual(frame.samples[1], -0.95)
        XCTAssertEqual(frame.samples[2], 0.5, accuracy: 0.001)
        XCTAssertEqual(frame.samples[3], -0.5, accuracy: 0.001)
    }

    // MARK: - Preset Tests

    func testDefaultPresetLoad() {
        let preset = VoicePreset.load(id: "default")
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.id, "default")
    }

    func testMaleToFemalePreset() {
        let preset = VoicePreset.maleToFemale
        XCTAssertEqual(preset.id, "male_to_female")
        XCTAssertGreaterThan(preset.pitchShift, 0)
        XCTAssertGreaterThan(preset.formantShift, 0)
    }

    func testFemaleToMalePreset() {
        let preset = VoicePreset.femaleToMale
        XCTAssertEqual(preset.id, "female_to_male")
        XCTAssertLessThan(preset.pitchShift, 0)
        XCTAssertLessThan(preset.formantShift, 0)
    }
}
