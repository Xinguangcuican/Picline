import XCTest
@testable import Tendedero

/// The strip at the top of a screen that a resting pointer may bring the line
/// down from. It is the middle of the menu bar only: both ends belong to the
/// system, and a rope arriving over them takes the click that was meant for
/// the Apple menu or the clock.
final class HotZoneTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let barHeight: CGFloat = 24

    private func zone(in frame: NSRect? = nil, bar: CGFloat? = nil) -> NSRect {
        AppDelegate.hotZone(in: frame ?? screen, menuBarHeight: bar ?? barHeight)
    }

    func testItIsCentred() {
        XCTAssertEqual(zone().midX, screen.midX)
        XCTAssertEqual(zone().width, AppDelegate.hotWidth)
    }

    func testItHangsFromTheTopEdge() {
        XCTAssertEqual(zone().maxY, screen.maxY)
        XCTAssertEqual(zone().height, barHeight)
    }

    /// The Apple menu sits about thirty points in from the left edge.
    func testTheAppleMenuIsOutside() {
        XCTAssertFalse(NSMouseInRect(NSPoint(x: 30, y: screen.maxY - 10), zone(), false))
    }

    /// So does the clock and the status items at the far right.
    func testTheClockIsOutside() {
        XCTAssertFalse(NSMouseInRect(NSPoint(x: 1890, y: screen.maxY - 10), zone(), false))
    }

    func testTheNotchIsInside() {
        XCTAssertTrue(NSMouseInRect(NSPoint(x: screen.midX, y: screen.maxY - 10), zone(), false))
    }

    /// Just under the menu bar is somebody else's space: a window's title bar,
    /// usually.
    func testBelowTheMenuBarIsOutside() {
        XCTAssertFalse(NSMouseInRect(NSPoint(x: screen.midX, y: screen.maxY - barHeight - 1), zone(), false))
    }

    /// A second display starts at its own origin, and the strip follows it
    /// there rather than back to the middle of the desktop.
    func testItFollowsTheScreenItIsOn() {
        let second = NSRect(x: 1920, y: 0, width: 1512, height: 982)
        XCTAssertEqual(zone(in: second).midX, second.midX)
        XCTAssertFalse(NSMouseInRect(NSPoint(x: 1920, y: 970), zone(in: second), false))
    }

    /// A screen narrower than the strip gets a strip its own width, not one
    /// hanging off both sides.
    func testANarrowScreenGetsANarrowStrip() {
        let narrow = NSRect(x: 0, y: 0, width: 300, height: 800)
        XCTAssertEqual(zone(in: narrow).width, 300)
        XCTAssertEqual(zone(in: narrow).minX, 0)
    }
}
