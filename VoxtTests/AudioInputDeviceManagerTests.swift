import XCTest
@testable import Voxt

final class AudioInputDeviceManagerTests: XCTestCase {
    func testSnapshotFilteringExcludesCoreAudioAggregateDevices() {
        XCTAssertFalse(
            AudioInputDeviceManager.shouldIncludeInSnapshot(
                uid: "CADefaultDeviceAggregate-72904-0",
                name: "CADefaultDeviceAggregate-72904-0"
            )
        )
    }

    func testSnapshotFilteringKeepsRegularMicrophones() {
        XCTAssertTrue(
            AudioInputDeviceManager.shouldIncludeInSnapshot(
                uid: "BuiltInMicrophoneDevice",
                name: "MacBook Pro Mic"
            )
        )
    }

    func testPreferredDeviceWinsWhenAvailable() {
        let devices = [
            AudioInputDevice(id: 10, uid: "mic-a", name: "Mic A"),
            AudioInputDevice(id: 20, uid: "mic-b", name: "Mic B")
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
            AudioInputDevice(id: 10, uid: "mic-a", name: "Mic A"),
            AudioInputDevice(id: 20, uid: "mic-b", name: "Mic B")
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
            AudioInputDevice(id: 10, uid: "mic-a", name: "Mic A"),
            AudioInputDevice(id: 20, uid: "mic-b", name: "Mic B")
        ]

        let resolved = AudioInputDeviceManager.resolvedInputDeviceID(
            from: devices,
            preferredID: nil,
            defaultDeviceID: 99
        )

        XCTAssertEqual(resolved, 10)
    }

    func testSnapshotFilterExcludesVoxtProcessTapDevice() {
        XCTAssertFalse(
            AudioInputDeviceManager.shouldIncludeInSnapshot(
                uid: "voxt-process-tap-2B3C106D-E5A2-4C0C-B910-23275522F843",
                name: "VoxtProcessTap"
            )
        )
    }

    func testSnapshotFilterExcludesAnonymousCoreAudioAggregateDevice() {
        XCTAssertFalse(
            AudioInputDeviceManager.shouldIncludeInSnapshot(
                uid: "CADefaultDeviceAggregate-8135-0",
                name: "CADefaultDeviceAggregate-8135-0"
            )
        )
    }

    func testSnapshotFilterKeepsRealMicrophoneDevices() {
        XCTAssertTrue(
            AudioInputDeviceManager.shouldIncludeInSnapshot(
                uid: "BuiltInMicrophoneDevice",
                name: "MacBook Air麦克风"
            )
        )
    }
}
