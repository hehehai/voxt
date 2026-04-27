import XCTest
import Carbon
import IOKit.hidsystem
@testable import Voxt

final class HotkeySupportTests: XCTestCase {
    func testUpdatingKeepsModifierSetWhenDuplicatePressEventArrives() {
        let afterFirstPress = SidedModifierFlags.updating(
            from: [],
            keyCode: UInt16(kVK_RightShift),
            isPressed: true
        )
        let afterDuplicatePress = SidedModifierFlags.updating(
            from: afterFirstPress,
            keyCode: UInt16(kVK_RightShift),
            isPressed: true
        )

        XCTAssertEqual(afterDuplicatePress, [.rightShift])
    }

    func testUpdatingClearsModifierWhenDuplicateReleaseEventArrives() {
        let afterRelease = SidedModifierFlags.updating(
            from: [.rightShift],
            keyCode: UInt16(kVK_RightShift),
            isPressed: false
        )
        let afterDuplicateRelease = SidedModifierFlags.updating(
            from: afterRelease,
            keyCode: UInt16(kVK_RightShift),
            isPressed: false
        )

        XCTAssertEqual(afterDuplicateRelease, [])
    }

    func testUpdatingClearsOnlyReleasedSideWhenOppositeSideStaysDown() {
        let updated = SidedModifierFlags.updating(
            from: [.leftShift, .rightShift],
            keyCode: UInt16(kVK_Shift),
            isPressed: false
        )

        XCTAssertEqual(updated, [.rightShift])
    }

    func testFilteredDropsSidedModifiersWhenBaseModifierIsMissing() {
        let filtered = SidedModifierFlags([.rightShift, .rightCommand]).filtered(by: [.command])

        XCTAssertEqual(filtered, [.rightCommand])
    }

    func testHotkeyMatchesRequiresMatchingSideWhenDistinguishingEnabled() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.rightShift],
                distinguishModifierSides: true
            )
        )
        XCTAssertFalse(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.leftShift],
                distinguishModifierSides: true
            )
        )
    }

    func testHotkeyMatchesIgnoresSideWhenDistinguishingDisabled() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.leftShift],
                distinguishModifierSides: false
            )
        )
    }

    func testHotkeyMatchesAllowsAdditionalSidedModifiersWhenRequiredSideIsPresent() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command, .shift],
            sidedModifiers: [.rightCommand, .rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskCommand, .maskShift],
                sidedModifiers: [.leftShift, .rightShift, .rightCommand],
                distinguishModifierSides: true
            )
        )
    }

    func testHotkeyMatchesRequiresMatchingSideForCustomNonModifierHotkey() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: [.option],
            sidedModifiers: [.rightOption]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskAlternate],
                sidedModifiers: [.rightOption],
                distinguishModifierSides: true
            )
        )
        XCTAssertFalse(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskAlternate],
                sidedModifiers: [.leftOption],
                distinguishModifierSides: true
            )
        )
    }

    func testSidedModifierFlagsFromEventFlagsParsesDeviceSpecificBits() {
        let flags = CGEventFlags(rawValue: UInt64(NX_COMMANDMASK | NX_DEVICERCMDKEYMASK | NX_DEVICERSHIFTKEYMASK))

        XCTAssertEqual(
            SidedModifierFlags.from(eventFlags: flags),
            [.rightCommand, .rightShift]
        )
    }

    func testDisplayStringShowsRightShiftWhenSideIsAvailable() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertEqual(
            HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: true),
            "Right Shift"
        )
    }

    func testDisplayStringFallsBackToGenericShiftWhenBothSidesArePresent() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.leftShift, .rightShift]
        )

        XCTAssertEqual(
            HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: true),
            "Shift"
        )
    }
}
