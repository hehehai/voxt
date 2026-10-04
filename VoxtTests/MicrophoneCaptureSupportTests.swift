// MicrophoneCaptureSupportTests.swift
// Covers microphone availability, signal health and device description helpers.

import XCTest
import CoreAudio
@testable import Voxt

final class MicrophoneCaptureSupportTests: XCTestCase {
    // MARK: Availability

    func testInternalMicrophoneIsUnavailableWhileLidIsClosed() {
        XCTAssertFalse(
            MicrophoneAvailabilityPolicy.isAvailable(
                transport: .builtIn,
                uid: "BuiltInMicrophoneDevice",
                inputDataSource: nil,
                lidState: .closed
            )
        )
    }

    func testInternalMicrophoneIdentifiedByDataSourceIsUnavailableWhileLidIsClosed() {
        XCTAssertFalse(
            MicrophoneAvailabilityPolicy.isAvailable(
                transport: .builtIn,
                uid: "AppleHDAEngineInput:1B,0,1,0:1",
                inputDataSource: AudioDeviceInspector.internalMicrophoneDataSource,
                lidState: .closed
            )
        )
    }

    func testInternalMicrophoneIsAvailableWhileLidIsOpenOrUnknown() {
        for lidState in [LaptopLidState.open, .unavailable] {
            XCTAssertTrue(
                MicrophoneAvailabilityPolicy.isAvailable(
                    transport: .builtIn,
                    uid: "BuiltInMicrophoneDevice",
                    inputDataSource: nil,
                    lidState: lidState
                )
            )
        }
    }

    func testWiredHeadsetOnBuiltInJackStaysAvailableWhileLidIsClosed() {
        let externalMicrophoneDataSource: UInt32 = 0x656D_6963 // 'emic'
        XCTAssertTrue(
            MicrophoneAvailabilityPolicy.isAvailable(
                transport: .builtIn,
                uid: "AppleHDAEngineInput:1B,0,1,1:2",
                inputDataSource: externalMicrophoneDataSource,
                lidState: .closed
            )
        )
    }

    func testExternalMicrophonesStayAvailableWhileLidIsClosed() {
        for transport in [AudioDeviceTransport.bluetooth, .usb, .continuityCapture, .virtual] {
            XCTAssertTrue(
                MicrophoneAvailabilityPolicy.isAvailable(
                    transport: transport,
                    uid: "BuiltInMicrophoneDevice",
                    inputDataSource: AudioDeviceInspector.internalMicrophoneDataSource,
                    lidState: .closed
                )
            )
        }
    }

    // MARK: Signal health

    func testDigitalSilenceIsReportedOnceAfterThreshold() {
        var monitor = CaptureSignalHealthMonitor(silenceThresholdSeconds: 1.5)

        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.5))
        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.5))
        XCTAssertEqual(monitor.observe(peak: 0, durationSeconds: 0.5), .digitalSilenceDetected(durationMs: 1500))
        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.5))
        XCTAssertEqual(monitor.totalSilenceSeconds, 2.0, accuracy: 0.0001)
    }

    func testQuietButRealSignalIsNotDigitalSilence() {
        var monitor = CaptureSignalHealthMonitor(silenceThresholdSeconds: 1.0)

        for _ in 0..<10 {
            XCTAssertNil(monitor.observe(peak: 0.0004, durationSeconds: 0.5))
        }
        XCTAssertEqual(monitor.totalSilenceSeconds, 0)
        XCTAssertEqual(monitor.maximumPeak, 0.0004, accuracy: 0.000001)
    }

    func testSignalRecoveryIsReportedAfterSilence() {
        var monitor = CaptureSignalHealthMonitor(silenceThresholdSeconds: 1.0)

        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.6))
        XCTAssertEqual(monitor.observe(peak: 0, durationSeconds: 0.6), .digitalSilenceDetected(durationMs: 1200))
        XCTAssertEqual(monitor.observe(peak: 0.2, durationSeconds: 0.1), .signalRecovered(afterSilenceMs: 1200))
        XCTAssertFalse(monitor.isReportingSilence)
        XCTAssertNil(monitor.observe(peak: 0.2, durationSeconds: 0.1))
    }

    func testShortSilenceBetweenSpeechDoesNotAccumulate() {
        var monitor = CaptureSignalHealthMonitor(silenceThresholdSeconds: 1.0)

        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.8))
        XCTAssertNil(monitor.observe(peak: 0.1, durationSeconds: 0.1))
        XCTAssertNil(monitor.observe(peak: 0, durationSeconds: 0.8))
        XCTAssertEqual(monitor.currentSilenceSeconds, 0.8, accuracy: 0.0001)
    }

    func testNegativeZeroAndNonFiniteValuesCountAsSilence() {
        var monitor = CaptureSignalHealthMonitor(silenceThresholdSeconds: 0.2)

        XCTAssertNil(monitor.observe(peak: -0.0, durationSeconds: 0.1))
        XCTAssertEqual(monitor.observe(peak: .nan, durationSeconds: 0.1), .digitalSilenceDetected(durationMs: 200))
    }

    // MARK: Bluetooth route

    func testBluetoothHeadsetInputAndOutputShareDeviceAddress() {
        XCTAssertEqual(BluetoothAudioRoute.deviceAddress(fromUID: "7C-C1-80-21-87-97:input"), "7C-C1-80-21-87-97")
        XCTAssertTrue(
            BluetoothAudioRoute.sharesHeadset(
                inputID: 601,
                inputUID: "7C-C1-80-21-87-97:input",
                inputTransport: .bluetooth,
                outputID: 602,
                outputUID: "7C-C1-80-21-87-97:output",
                outputTransport: .bluetooth
            )
        )
    }

    func testDifferentBluetoothDevicesDoNotShareHeadset() {
        XCTAssertFalse(
            BluetoothAudioRoute.sharesHeadset(
                inputID: 113,
                inputUID: "EC-72-F7-5A-28-2A:input",
                inputTransport: .bluetooth,
                outputID: 602,
                outputUID: "7C-C1-80-21-87-97:output",
                outputTransport: .bluetooth
            )
        )
    }

    func testNonBluetoothRoutesNeverShareHeadset() {
        XCTAssertFalse(
            BluetoothAudioRoute.sharesHeadset(
                inputID: 85,
                inputUID: "BuiltInMicrophoneDevice",
                inputTransport: .builtIn,
                outputID: 85,
                outputUID: "BuiltInMicrophoneDevice",
                outputTransport: .builtIn
            )
        )
        XCTAssertNil(BluetoothAudioRoute.deviceAddress(fromUID: "BuiltInMicrophoneDevice"))
    }

    // MARK: Device description

    func testTransportTypesMapToLabels() {
        XCTAssertEqual(AudioDeviceTransport(rawValue: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(AudioDeviceTransport(rawValue: kAudioDeviceTransportTypeBluetooth).label, "bluetooth")
        XCTAssertEqual(AudioDeviceTransport(rawValue: kAudioDeviceTransportTypeAutoAggregate), .aggregate)
        XCTAssertEqual(AudioDeviceTransport(rawValue: nil), .unknown)
        XCTAssertEqual(AudioDeviceTransport(rawValue: 0x7465_7374).label, "test")
    }

    func testFourCharacterCodeFallsBackToNumberForUnprintableValues() {
        XCTAssertEqual(AudioDeviceInspector.fourCharacterCode(0x696D_6963), "imic")
        XCTAssertEqual(AudioDeviceInspector.fourCharacterCode(1), "1")
    }

    func testInputOnlyDeviceDescription() {
        let snapshot = AudioDeviceSnapshot(
            id: 113,
            uid: "EC-72-F7-5A-28-2A:input",
            name: "DJI Mic 2",
            transport: .bluetooth,
            inputChannels: 1,
            outputChannels: 0,
            nominalSampleRate: 16000,
            inputDataSource: nil,
            isAlive: true
        )

        XCTAssertTrue(snapshot.isInputOnly)
        XCTAssertEqual(
            snapshot.diagnosticDescription,
            "DJI Mic 2{uid=EC-72-F7-5A-28-2A:input,id=113,transport=bluetooth,in=1,out=0,rate=16000,alive=true}"
        )
    }
}
