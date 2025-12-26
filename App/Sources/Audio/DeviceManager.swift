import Foundation
import CoreAudio
import Combine

/// オーディオデバイス情報
public struct AudioDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let uid: String
    public let isInput: Bool
    public let isOutput: Bool
    public let sampleRates: [Double]
    public let channelCount: Int
    public let isVirtual: Bool
    public let transportType: TransportType

    public enum TransportType: String {
        case builtIn
        case usb
        case bluetooth
        case virtual
        case unknown
    }
}

/// デバイス変更イベント
public enum DeviceChangeEvent {
    case deviceAdded(AudioDevice)
    case deviceRemoved(String) // deviceId
    case defaultInputChanged(AudioDevice?)
    case defaultOutputChanged(AudioDevice?)
}

/// オーディオデバイス管理
public final class DeviceManager: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var inputDevices: [AudioDevice] = []
    @Published public private(set) var outputDevices: [AudioDevice] = []
    @Published public private(set) var defaultInputDevice: AudioDevice?
    @Published public private(set) var defaultOutputDevice: AudioDevice?
    @Published public private(set) var virtualMicDevice: AudioDevice?

    // MARK: - Private Properties

    private var deviceChangeSubject = PassthroughSubject<DeviceChangeEvent, Never>()
    public var deviceChangePublisher: AnyPublisher<DeviceChangeEvent, Never> {
        deviceChangeSubject.eraseToAnyPublisher()
    }

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Initialization

    public init() {
        refreshDevices()
        startDeviceMonitoring()
    }

    deinit {
        stopDeviceMonitoring()
    }

    // MARK: - Public Methods

    /// デバイスリストを更新
    public func refreshDevices() {
        inputDevices = listInputDevices()
        outputDevices = listOutputDevices()
        defaultInputDevice = getDefaultInputDevice()
        defaultOutputDevice = getDefaultOutputDevice()
        virtualMicDevice = findVirtualMic()
    }

    /// 入力デバイス一覧取得
    public func listInputDevices() -> [AudioDevice] {
        return getDevices(scope: kAudioObjectPropertyScopeInput)
    }

    /// 出力デバイス一覧取得
    public func listOutputDevices() -> [AudioDevice] {
        return getDevices(scope: kAudioObjectPropertyScopeOutput)
    }

    /// デフォルト入力デバイス取得
    public func getDefaultInputDevice() -> AudioDevice? {
        guard let deviceId = getDefaultDeviceId(forInput: true) else { return nil }
        return inputDevices.first { $0.id == String(deviceId) }
    }

    /// デフォルト出力デバイス取得
    public func getDefaultOutputDevice() -> AudioDevice? {
        guard let deviceId = getDefaultDeviceId(forInput: false) else { return nil }
        return outputDevices.first { $0.id == String(deviceId) }
    }

    /// 仮想マイクを検索
    public func findVirtualMic() -> AudioDevice? {
        return inputDevices.first { $0.name.contains("VoiceChanger") || $0.isVirtual }
    }

    /// 仮想スピーカーを検索（v1.5用）
    public func findVirtualSpk() -> AudioDevice? {
        return outputDevices.first { $0.name.contains("VoiceChanger") && $0.isVirtual }
    }

    // MARK: - Private Methods

    private func getDevices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return [] }

        return deviceIds.compactMap { deviceId -> AudioDevice? in
            guard hasStreams(deviceId: deviceId, scope: scope) else { return nil }
            return createAudioDevice(from: deviceId, isInput: scope == kAudioObjectPropertyScopeInput)
        }
    }

    private func hasStreams(deviceId: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func createAudioDevice(from deviceId: AudioDeviceID, isInput: Bool) -> AudioDevice? {
        guard let name = getDeviceName(deviceId: deviceId),
              let uid = getDeviceUID(deviceId: deviceId) else {
            return nil
        }

        let transportType = getTransportType(deviceId: deviceId)
        let isVirtual = transportType == .virtual

        return AudioDevice(
            id: String(deviceId),
            name: name,
            uid: uid,
            isInput: isInput,
            isOutput: !isInput,
            sampleRates: [48000], // 簡略化
            channelCount: 1,
            isVirtual: isVirtual,
            transportType: transportType
        )
    }

    private func getDeviceName(deviceId: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr, let cfName = name else { return nil }

        return cfName as String
    }

    private func getDeviceUID(deviceId: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &uid)
        guard status == noErr, let cfUID = uid else { return nil }

        return cfUID as String
    }

    private func getTransportType(deviceId: AudioDeviceID) -> AudioDevice.TransportType {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &transportType)
        guard status == noErr else { return .unknown }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .unknown
        }
    }

    private func getDefaultDeviceId(forInput: Bool) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: forInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    private func startDeviceMonitoring() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        propertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            propertyListenerBlock!
        )
    }

    private func stopDeviceMonitoring() {
        guard let block = propertyListenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
}
