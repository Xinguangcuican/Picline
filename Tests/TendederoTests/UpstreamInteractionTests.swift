import AppKit
import XCTest
@testable import Tendedero

/// Isolated feasibility checks: callbacks replace all clipboard and editor actions.
@MainActor
final class UpstreamInteractionTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, clicks: Int = 1,
                       at point: NSPoint = NSPoint(x: 70, y: 40)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: 0, context: nil, eventNumber: 0,
                                        clickCount: clicks, pressure: 0))
    }

    private func view() -> GrabView {
        GrabView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
    }

    private func waitForCopy() async throws {
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.15))
    }

    func testSingleClickCopiesOnlyAfterDoubleClickWindow() async throws {
        let view = view()
        var copies = 0
        view.onClick = { copies += 1 }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(copies, 0)
        try await waitForCopy()
        XCTAssertEqual(copies, 1)
    }

    func testDoubleClickOpensWithoutCopying() async throws {
        let view = view()
        var copies = 0
        var opens = 0
        view.onClick = { copies += 1 }
        view.onDoubleClick = { opens += 1 }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseUp(with: try event(.leftMouseUp))
        view.mouseDown(with: try event(.leftMouseDown, clicks: 2))
        view.mouseUp(with: try event(.leftMouseUp, clicks: 2))
        XCTAssertEqual(opens, 1)
        try await waitForCopy()
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(opens, 1)
    }

    func testPendingCopySurvivesViewRecreation() async throws {
        var view: GrabView? = view()
        var copies = 0
        view?.onClick = { copies += 1 }
        view?.mouseDown(with: try event(.leftMouseDown))
        view?.mouseUp(with: try event(.leftMouseUp))
        view = nil
        try await waitForCopy()
        XCTAssertEqual(copies, 1)
    }

    func testLongPressDoesNotQueueCopy() async throws {
        let view = view()
        var copies = 0
        var markups = 0
        view.onClick = { copies += 1 }
        view.onLongPress = { markups += 1 }
        view.mouseDown(with: try event(.leftMouseDown))
        try await Task.sleep(for: .milliseconds(600))
        view.mouseUp(with: try event(.leftMouseUp))
        try await waitForCopy()
        XCTAssertEqual(markups, 1)
        XCTAssertEqual(copies, 0)
    }

    func testDiscardCornerDoesNotQueueCopy() async throws {
        let view = view()
        var copies = 0
        var discards = 0
        view.onClick = { copies += 1 }
        view.onDiscard = { discards += 1 }
        let corner = NSPoint(x: 10, y: 90)
        view.mouseDown(with: try event(.leftMouseDown, at: corner))
        view.mouseUp(with: try event(.leftMouseUp, at: corner))
        try await waitForCopy()
        XCTAssertEqual(discards, 1)
        XCTAssertEqual(copies, 0)
    }
}
