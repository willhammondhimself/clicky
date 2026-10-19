import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct MicrophoneSelectionTests {

    private let macBookMicrophone = AudioInputDeviceInfo(deviceIdentifier: 81, name: "MacBook Pro Microphone", transport: .builtIn)
    private let airPodsMicrophone = AudioInputDeviceInfo(deviceIdentifier: 117, name: "Jump AirPods", transport: .bluetooth)
    private let usbMicrophone = AudioInputDeviceInfo(deviceIdentifier: 140, name: "Shure MV7", transport: .other)

    @Test func defaultPreferenceIsTheBuiltInMicrophone() {
        #expect(MicrophonePreference.defaultPreference == .builtIn)
        #expect(MicrophonePreference.allCases.map(\.rawValue) == ["builtIn", "systemDefault"])
        #expect(MicrophonePreference.allCases.map(\.displayName) == ["MacBook mic", "System default"])
    }

    @Test func builtInPreferenceUsesTheMacBookMicEvenWhenAirPodsAreConnected() {
        // AirPods as macOS's default input would switch them to their
        // low-quality headset mode and drop Lumen's recording.
        let chosenDeviceIdentifier = MicrophoneSelection.inputDeviceIdentifier(
            preference: .builtIn,
            availableInputDevices: [airPodsMicrophone, macBookMicrophone]
        )
        #expect(chosenDeviceIdentifier == 81)
    }

    @Test func systemDefaultPreferenceLeavesTheChoiceToMacOS() {
        let chosenDeviceIdentifier = MicrophoneSelection.inputDeviceIdentifier(
            preference: .systemDefault,
            availableInputDevices: [airPodsMicrophone, macBookMicrophone]
        )
        #expect(chosenDeviceIdentifier == nil)
    }

    @Test func withTheLidClosedThereIsNoBuiltInMicSoMacOSChooses() {
        // Clamshell mode: the built-in mic disappears, so fall back to
        // whatever macOS uses (an external mic, or the AirPods).
        let chosenDeviceIdentifier = MicrophoneSelection.inputDeviceIdentifier(
            preference: .builtIn,
            availableInputDevices: [airPodsMicrophone, usbMicrophone]
        )
        #expect(chosenDeviceIdentifier == nil)
    }
}
