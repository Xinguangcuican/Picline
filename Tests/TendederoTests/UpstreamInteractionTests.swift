import AppKit
import XCTest
@testable import Tendedero

/// The card's own layer: what a click, a shift click and a command click ask
/// for, and that letting go settles the choice without touching the clipboard.
@MainActor
final class UpstreamInteractionTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, clicks: Int = 1,
                       at point: NSPoint = NSPoint(x: 70, y: 40),
                       flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                                        modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: 0, context: nil, eventNumber: 0,
                                        clickCount: clicks, pressure: 0))
    }

    private func view() -> GrabView {
        GrabView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
    }

    func testClickPicksThePhotoOut() throws {
        let view = view()
        var presses: [(shift: Bool, command: Bool)] = []
        view.onPress = { shift, command in presses.append((shift, command)) }
        view.mouseDown(with: try event(.leftMouseDown))
        XCTAssertEqual(presses.count, 1)
        XCTAssertEqual(presses.first?.shift, false)
        XCTAssertEqual(presses.first?.command, false)
    }

    func testShiftClickAsksForARun() throws {
        let view = view()
        var presses: [(shift: Bool, command: Bool)] = []
        view.onPress = { shift, command in presses.append((shift, command)) }
        view.mouseDown(with: try event(.leftMouseDown, flags: .shift))
        XCTAssertEqual(presses.first?.shift, true)
        XCTAssertEqual(presses.first?.command, false)
    }

    func testCommandClickAsksToToggle() throws {
        let view = view()
        var presses: [(shift: Bool, command: Bool)] = []
        view.onPress = { shift, command in presses.append((shift, command)) }
        view.mouseDown(with: try event(.leftMouseDown, flags: .command))
        XCTAssertEqual(presses.first?.shift, false)
        XCTAssertEqual(presses.first?.command, true)
    }

    func testDoubleClickOpensWithoutPicking() throws {
        let view = view()
        var picks = 0
        var opens = 0
        view.onPress = { _, _ in picks += 1 }
        view.onDoubleClick = { opens += 1 }
        view.mouseDown(with: try event(.leftMouseDown, clicks: 2))
        view.mouseUp(with: try event(.leftMouseUp, clicks: 2))
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(picks, 0)
    }

    func testDiscardCornerDoesNotPick() throws {
        let view = view()
        var picks = 0
        var discards = 0
        view.onPress = { _, _ in picks += 1 }
        view.onDiscard = { discards += 1 }
        let corner = NSPoint(x: 10, y: 90)
        view.mouseDown(with: try event(.leftMouseDown, at: corner))
        view.mouseUp(with: try event(.leftMouseUp, at: corner))
        XCTAssertEqual(discards, 1)
        XCTAssertEqual(picks, 0)
    }

    func testLettingGoSettlesWithoutADrag() throws {
        let view = view()
        var settled: [Bool] = []
        view.onSettle = { dragged in settled.append(dragged) }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(settled, [false])
    }

    /// A long press looks at the photo. The pick already happened on the way
    /// down; what matters is that the long press still fires, and that letting
    /// go says nothing was dragged.
    func testLongPressLooksAtThePhoto() async throws {
        let view = view()
        var picks = 0
        var looks = 0
        var settled: [Bool] = []
        view.onPress = { _, _ in picks += 1 }
        view.onLongPress = { looks += 1 }
        view.onSettle = { dragged in settled.append(dragged) }
        view.mouseDown(with: try event(.leftMouseDown))
        try await Task.sleep(for: .milliseconds(600))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(looks, 1)
        XCTAssertEqual(picks, 1)
        XCTAssertEqual(settled, [false])
    }
}
