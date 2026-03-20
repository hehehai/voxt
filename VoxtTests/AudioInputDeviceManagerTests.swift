import XCTest
import CoreAudio
@testable import Voxt

final class AudioInputDeviceManagerTests: XCTestCase {
    func testPreferredDeviceWinsWhenAvailable() {
        let devices = [
            AudioInputDevice(id: 10, name: "Mic A"),
            AudioInputDevice(id: 20, name: "Mic B")
        ]

        let resolved = AudioInputDeviceManager.resolvedInputDeviceID(
            from: devices,
            preferredID: 20,
            defaultDeviceID: 10
        )

        XCTAssertEqual(resolved, 20)
    }

    func testDefaultDeviceFallbackIsUsedWhenPreferredMissing() {
        let devices = [
            AudioInputDevice(id: 10, name: "Mic A"),
            AudioInputDevice(id: 20, name: "Mic B")
        ]

        let resolved = AudioInputDeviceManager.resolvedInputDeviceID(
            from: devices,
            preferredID: 99,
            defaultDeviceID: 20
        )

        XCTAssertEqual(resolved, 20)
    }

    func testFirstDeviceFallbackIsUsedWhenNothingElseMatches() {
        let devices = [
            AudioInputDevice(id: 10, name: "Mic A"),
            AudioInputDevice(id: 20, name: "Mic B")
        ]

        let resolved = AudioInputDeviceManager.resolvedInputDeviceID(
            from: devices,
            preferredID: nil,
            defaultDeviceID: 99
        )

        XCTAssertEqual(resolved, 10)
    }
}

