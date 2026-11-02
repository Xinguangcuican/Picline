import AppKit
import XCTest
@testable import Tendedero

/// Picking photos out: one, a run of them, or any handful, and what a drag
/// from the middle of a group carries.
@MainActor
final class SelectionTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var line: Line!
    private var ids: [UUID] = []

    override func setUp() async throws {
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/selection-tests/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "captureline.selection-tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        line = Line(defaults: defaults)
        line.maxItems = 100
        ids = try (1...4).map { n in
            let url = directory.appendingPathComponent("\(n).png")
            try image().write(to: url, options: .atomic)
            return try XCTUnwrap(line.hang(url, quietly: true), "photo \(n) did not hang")
        }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func image() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var pixel = [255, 0, 0, 255]
        for y in 0..<8 { for x in 0..<12 { rep.setPixel(&pixel, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }

    private func pick(_ index: Int) {
        line.press(ids[index], extending: false, toggling: false)
    }

    private func shiftPick(_ index: Int) {
        line.press(ids[index], extending: true, toggling: false)
    }

    private func commandPick(_ index: Int) {
        line.press(ids[index], extending: false, toggling: true)
    }

    func testAClickPicksOne() {
        pick(1)
        XCTAssertEqual(line.selection, [ids[1]])
    }

    func testShiftTakesEverythingBetweenIncludingBothEnds() {
        pick(0)
        shiftPick(3)
        XCTAssertEqual(line.selection, Set(ids))
    }

    func testShiftWorksBackwardsToo() {
        pick(3)
        shiftPick(1)
        XCTAssertEqual(line.selection, Set(ids[1...3]))
    }

    func testCommandAddsAndRemovesOne() {
        pick(0)
        commandPick(2)
        XCTAssertEqual(line.selection, [ids[0], ids[2]])
        commandPick(0)
        XCTAssertEqual(line.selection, [ids[2]])
    }

    /// Pressing a photo that is already part of a group leaves the group
    /// alone, so the drag that may follow carries all of it.
    func testPressingInsideAGroupKeepsTheGroup() {
        pick(0)
        shiftPick(2)
        pick(1)
        XCTAssertEqual(line.selection, Set(ids[0...2]))
    }

    func testLettingGoInsideAGroupClosesDownToOne() {
        pick(0)
        shiftPick(2)
        pick(1)
        line.settle(ids[1], dragged: false)
        XCTAssertEqual(line.selection, [ids[1]])
    }

    func testDraggingInsideAGroupKeepsTheWholeSelection() {
        pick(0)
        shiftPick(2)
        pick(1)
        line.settle(ids[1], dragged: true)
        XCTAssertEqual(line.selection, Set(ids[0...2]))
    }

    func testDragFromAPickedPhotoCarriesTheGroupInLineOrder() {
        pick(0)
        shiftPick(2)
        let payload = line.dragPayload(including: ids[1])
        XCTAssertEqual(payload.map(\.id), Array(ids[0...2]))
    }

    func testDragFromAnUnpickedPhotoCarriesOnlyIt() {
        pick(0)
        shiftPick(2)
        let payload = line.dragPayload(including: ids[3])
        XCTAssertEqual(payload.map(\.id), [ids[3]])
    }

    func testAPickedPhotoThatGoesAwayLeavesTheSelection() async throws {
        pick(0)
        shiftPick(1)
        line.drop(ids[0], quietly: true)
        try await Task.sleep(for: .seconds(0.9))
        XCTAssertFalse(line.selection.contains(ids[0]))
        XCTAssertTrue(line.selection.contains(ids[1]))
    }

    /// What the right-click menu acts on is the same thing a drag carries:
    /// the group when the photo is part of it, that photo alone when it is not.
    func testTheMenuActsOnTheGroupThePhotoBelongsTo() {
        pick(0)
        shiftPick(2)
        XCTAssertEqual(line.targets(including: ids[1]).map(\.id), Array(ids[0...2]))
    }

    func testTheMenuActsOnOnePhotoWhenItIsOutsideTheGroup() {
        pick(0)
        shiftPick(2)
        XCTAssertEqual(line.targets(including: ids[3]).map(\.id), [ids[3]])
    }

    /// A plain click picks one out, so "just this one" needs no special case.
    func testOneClickMeansOneForTheMenuToo() {
        pick(2)
        XCTAssertEqual(line.targets(including: ids[2]).map(\.id), [ids[2]])
    }

    /// "Save to Desktop" on one of three chosen photos saves three, under
    /// names nothing is already using.
    func testSaveToDesktopKeepsEveryPickedPhoto() throws {
        pick(0)
        shiftPick(2)
        let desktop = directory.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        line.saveToDesktop(ids[1], into: desktop)
        let saved = try FileManager.default.contentsOfDirectory(atPath: desktop.path).sorted()
        XCTAssertEqual(saved, ["1.png", "2.png", "3.png"])
        XCTAssertEqual(line.liveCount, 1, "the three that were saved left the line")
    }

    func testSaveToDesktopFromOnePhotoSavesThatOne() throws {
        pick(1)
        let desktop = directory.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        line.saveToDesktop(ids[1], into: desktop)
        let saved = try FileManager.default.contentsOfDirectory(atPath: desktop.path).sorted()
        XCTAssertEqual(saved, ["2.png"])
        XCTAssertEqual(line.liveCount, 3)
    }

    /// The menu's "Take down" clears the group; the corner cross still clears
    /// only its own photo, which the next test pins down.
    func testTakeDownFromTheMenuTakesDownTheGroup() {
        pick(0)
        shiftPick(2)
        line.discardGroup(ids[1])
        XCTAssertEqual(line.items.filter { !$0.falling }.map(\.id), [ids[3]])
    }

    func testTheCornerCrossStillTakesDownOnePhoto() async throws {
        pick(0)
        shiftPick(2)
        line.discard(ids[1], quietly: true)
        try await Task.sleep(for: .seconds(0.9))
        XCTAssertEqual(line.items.map(\.id), [ids[0], ids[2], ids[3]])
    }

    func testTakingEverythingDownClearsTheSelection() {
        pick(0)
        shiftPick(2)
        line.clear()
        XCTAssertTrue(line.selection.isEmpty)
    }
}
