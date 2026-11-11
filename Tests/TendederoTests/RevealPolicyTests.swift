import XCTest
@testable import Tendedero

/// What has to be true for the pointer in the menu bar to bring the line down.
/// The rules are one sentence, and every part of it gets pinned here because
/// two of them were reversed at some point in this app's life.
final class RevealPolicyTests: XCTestCase {
    /// Everything in favour, with three photos hanging.
    private func ready(hanging: Int = 3, carrying: Bool = false) -> RevealPolicy {
        RevealPolicy(allowed: true, keyHeld: true, suppressed: false,
                     overFullScreen: false, hanging: hanging, carrying: carrying)
    }

    func testAPhotoOnTheLineComesDown() {
        XCTAssertTrue(ready().bringsTheLineDown)
    }

    /// An empty line stays away: reaching for the Wi-Fi menu should not bring
    /// a bare rope down every single time.
    func testAnEmptyLineStaysAway() {
        XCTAssertFalse(ready(hanging: 0).bringsTheLineDown)
    }

    /// Unless a picture is being carried to it. The button is down and the
    /// pointer is at the top of the screen, so the line comes down to catch
    /// what is about to be dropped.
    func testADragBringsAnEmptyLineDown() {
        XCTAssertTrue(ready(hanging: 0, carrying: true).bringsTheLineDown)
    }

    /// The button alone is not enough on its own terms: the switches still
    /// apply, so nobody who turned this off gets a line for a drag.
    func testTheSwitchStillAppliesWhileCarrying() {
        var policy = ready(hanging: 0, carrying: true)
        policy.allowed = false
        XCTAssertFalse(policy.bringsTheLineDown)
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

    // MARK: Overviews

    /// Mission Control, App Exposé and Launchpad belong to the Dock while they
    /// are up: the pointer at the top of the screen is working the spaces bar,
    /// and a window dragged towards another Space crosses the band a picture
    /// would. Whatever is hanging, the line stays away.
    func testAnOverviewKeepsItAway() {
        var policy = ready()
        policy.overview = true
        XCTAssertFalse(policy.bringsTheLineDown)
    }

    /// Including the one case the line normally makes an exception for: a
    /// picture carried towards an empty line.
    func testAnOverviewKeepsAnEmptyLineAwayWhileCarrying() {
        var policy = ready(hanging: 0, carrying: true)
        policy.overview = true
        XCTAssertFalse(policy.bringsTheLineDown)
    }

    /// The overview is the only thing holding it back: take that away and the
    /// same state brings the line down again.
    func testWithNoOverviewItComesDownAgain() {
        XCTAssertTrue(ready(carrying: true).bringsTheLineDown)
    }

    // MARK: Press and hold

    /// A click is a press too. It must not count as carrying anything, or the
    /// line drops down every time somebody reaches for a menu.
    func testAClickIsNotACarry() {
        let down = Date()
        XCTAssertFalse(AppDelegate.carrying(buttonDown: true, since: down, travel: 40,
                                            at: down.addingTimeInterval(0.05)))
    }

    /// A picture dragged up from Finder has been held far longer than the
    /// threshold, and has crossed far more than the travel threshold, by the
    /// time it reaches the top.
    func testAHeldButtonIsACarry() {
        let down = Date()
        XCTAssertTrue(AppDelegate.carrying(buttonDown: true, since: down, travel: 120,
                                           at: down.addingTimeInterval(0.4)))
    }

    /// Holding still on the strip is not a drag. There is nothing to hang, and
    /// a line that drops for a finger resting on the top edge is in the way of
    /// whatever the user is actually doing.
    func testHoldingStillIsNotACarry() {
        let down = Date()
        XCTAssertFalse(AppDelegate.carrying(buttonDown: true, since: down, travel: 1,
                                            at: down.addingTimeInterval(2)))
    }

    /// A shake of a pixel or two is not travel either: hands are not still,
    /// and the threshold has to swallow that.
    func testJustUnderTheTravelThresholdIsNotACarry() {
        let down = Date()
        XCTAssertFalse(AppDelegate.carrying(buttonDown: true, since: down, travel: 4.9,
                                            at: down.addingTimeInterval(2)))
    }

    /// Letting go stops it, however long it was held and however far it went.
    func testReleasingTheButtonStopsIt() {
        let down = Date()
        XCTAssertFalse(AppDelegate.carrying(buttonDown: false, since: down, travel: 500,
                                            at: down.addingTimeInterval(5)))
    }

    func testNoPressAtAllIsNotACarry() {
        XCTAssertFalse(AppDelegate.carrying(buttonDown: true, since: nil, travel: 500,
                                            at: Date()))
    }
}
