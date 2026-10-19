//
//  AudioInputDeviceCatalog.swift
//  leanring-buddy
//
//  Lists the Mac's audio input devices from Core Audio (id, name and whether
//  each is built in or Bluetooth), and finds macOS's default input, for
//  MicrophoneSelection. Reading these needs no permission.
//

import CoreAudio

enum AudioInputDeviceCatalog {
    static func availableInputDevices() -> [AudioInputDeviceInfo] {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesDataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &devicesDataSize) == noErr else {
            return []
        }
        var deviceIdentifiers = [AudioDeviceID](repeating: 0, count: Int(devicesDataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &devicesDataSize, &deviceIdentifiers) == noErr else {
            return []
        }

        return deviceIdentifiers.compactMap { deviceIdentifier in
            guard hasInputStreams(deviceIdentifier) else { return nil }
            return AudioInputDeviceInfo(
                deviceIdentifier: deviceIdentifier,
                name: deviceName(deviceIdentifier),
                transport: transport(of: deviceIdentifier)
            )
        }
    }

    static func systemDefaultInputDeviceIdentifier() -> AudioDeviceID? {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultInputDeviceIdentifier = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, 0, nil, &dataSize, &defaultInputDeviceIdentifier)
        return status == noErr && defaultInputDeviceIdentifier != 0 ? defaultInputDeviceIdentifier : nil
    }

    static func deviceName(_ deviceIdentifier: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceIdentifier, &nameAddress, 0, nil, &dataSize, &unmanagedName) == noErr,
              let unmanagedName else { return "unknown device" }
        return unmanagedName.takeRetainedValue() as String
    }

    private static func hasInputStreams(_ deviceIdentifier: AudioDeviceID) -> Bool {
        var inputStreamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceIdentifier, &inputStreamsAddress, 0, nil, &dataSize) == noErr else { return false }
        return dataSize > 0
    }

    private static func transport(of deviceIdentifier: AudioDeviceID) -> AudioInputTransport {
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceIdentifier, &transportAddress, 0, nil, &dataSize, &transportType) == noErr else { return .other }
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default: return .other
        }
    }
}
