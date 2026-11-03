import XCTest
@testable import Tendedero

/// What has to be true for the pointer in the menu bar to bring the line down.
/// The rules are one sentence, and every part of it gets pinned here because
/// two of them were reversed at some point in this app's life.
final class RevealPolicyTests: XCTestCase {
    /// Everything in favour, with three photos hanging.
    private func ready(hanging: Int = 3) -> RevealPolicy {
        RevealPolicy(allowed: true, keyHeld: true, suppressed: false,
                     overFullScreen: false, hanging: hanging)
    }

    func testAPhotoOnTheLineComesDown() {
        XCTAssertTrue(ready().bringsTheLineDown)
    }

    /// An empty line stays away: reaching for the Wi-Fi menu should not bring
    /// a bare rope down every single time.
    func testAnEmptyLineStaysAway() {
        XCTAssertFalse(ready(hanging: 0).bringsTheLineDown)
    }

    func testTheSwitchInTheMenuStillApplies() {
        var policy = ready()
        policy.allowed = false
        XCTAssertFalse(policy.bringsTheLineDown)
    }

    func testTheKeyStillHasToBeHeld() {
        var policy = ready()
        policy.keyHeld = false
        XCTAssertFalse(policy.bringsTheLineDown)
    }

    /// After a click in the menu bar the line keeps away while the pointer is
    /// up there, whatever is hanging.
    func testAClickInTheMenuBarKeepsItAway() {
        var policy = ready()
        policy.suppressed = true
        XCTAssertFalse(policy.bringsTheLineDown)
    }

    func testAFullScreenAppKeepsItAway() {
        var policy = ready()
        policy.overFullScreen = true
        XCTAssertFalse(policy.bringsTheLineDown)
    }
}
