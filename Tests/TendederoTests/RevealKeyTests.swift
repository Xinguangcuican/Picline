import AppKit
import XCTest
@testable import Tendedero

/// The key that has to be held for the pointer in the menu bar to bring the
/// line down. `none` is the old behaviour and has to stay exactly that.
@MainActor
final class RevealKeyTests: XCTestCase {
    func testNoKeyMeansNothingHasToBeHeld() {
        XCTAssertNil(RevealKey.none.modifier)
        XCTAssertTrue(RevealKey.none.isHeld)
    }

    func testEachChoiceLooksForItsOwnModifier() {
        XCTAssertEqual(RevealKey.command.modifier, .command)
        XCTAssertEqual(RevealKey.option.modifier, .option)
        XCTAssertEqual(RevealKey.control.modifier, .control)
        XCTAssertEqual(RevealKey.shift.modifier, .shift)
    }

    /// No two choices may share a flag, or one of them would be unreachable.
    func testTheFlagsAreDistinct() {
        let flags = RevealKey.allCases.compactMap(\.modifier)
        XCTAssertEqual(Set(flags.map(\.rawValue)).count, flags.count)
        XCTAssertEqual(flags.count, RevealKey.allCases.count - 1)
    }

    func testEveryChoiceIsNamed() {
        for key in RevealKey.allCases {
            XCTAssertFalse(key.title.isEmpty, "\(key) has no title")
        }
    }

    /// What is stored is the raw value, so a build that adds a key does not
    /// break a saved choice and an unknown one falls back to no key at all.
    func testAnUnknownStoredChoiceFallsBackToNoKey() {
        XCTAssertEqual(RevealKey(rawValue: "option"), .option)
        XCTAssertNil(RevealKey(rawValue: "hyper"))
    }
}
