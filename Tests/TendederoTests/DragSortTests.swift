import AppKit
import XCTest
@testable import Tendedero

/// Carrying a photo sideways along the line: the others make room, the order
/// is remembered, and letting go past the edge of the line puts it all back.
@MainActor
final class DragSortTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var line: Line!
    private var ids: [UUID] = []

    /// Four photos evenly spaced across a line a thousand points wide:
    /// centres at 239, 413, 587 and 761.
    private let width: CGFloat = 1000

    override func setUp() async throws {
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/drag-sort-tests/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "captureline.drag-sort-tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        line = Line(defaults: defaults)
        line.maxItems = 100
        ids = try (1...4).map { n in
            let url = directory.appendingPathComponent("\(n).png")
            try image().write(to: url, options: .atomic)
            return try XCTUnwrap(line.hang(url, quietly: true), "photo \(n) did not hang")
        }
        line.lineWidth = width
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

    /// The photos in the order the line shows them, by the number in the name.
    private var order: [Int] {
        line.items.compactMap { Int($0.url.deletingPathExtension().lastPathComponent) }
    }

    private func pick(_ index: Int) {
        line.press(ids[index], extending: false, toggling: false)
    }

    // MARK: Moving

    func testCarryingTheNewestToTheFarLeftPutsItFirst() {
        line.beginSort(ids[3])
        line.sort(ids[3], toX: 200)
        XCTAssertEqual(order, [4, 1, 2, 3])
    }

    func testThePointerBetweenTwoPhotosDropsItThere() {
        line.beginSort(ids[3])
        // Past the first two centres, short of the third: it belongs third.
        line.sort(ids[3], toX: 450)
        XCTAssertEqual(order, [1, 2, 4, 3])
    }

    func testCarryingPastTheLastPhotoPutsItLast() {
        line.beginSort(ids[0])
        line.sort(ids[0], toX: 850)
        XCTAssertEqual(order, [2, 3, 4, 1])
    }

    func testTheOrderIsremembered() {
        line.beginSort(ids[3])
        line.sort(ids[3], toX: 200)
        line.endSort(ids[3], keeping: true)
        let saved = defaults.stringArray(forKey: "pegged") ?? []
        let names = saved.compactMap { Int(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }
        XCTAssertEqual(names, [4, 1, 2, 3])
    }

    // MARK: Letting go elsewhere

    func testLeavingTheLinePutsTheOrderBack() {
        line.beginSort(ids[3])
        line.sort(ids[3], toX: 200)
        XCTAssertEqual(order, [4, 1, 2, 3])
        // The pointer left the line, so the drag became one that carries the
        // file to another app: what was left behind should not have shuffled.
        line.endSort(ids[3], keeping: false)
        XCTAssertEqual(order, [1, 2, 3, 4])
        XCTAssertNil(line.sortingID)
    }

    // MARK: A group

    func testAPickedGroupTravelsTogether() {
        pick(1)
        line.press(ids[2], extending: true, toggling: false)
        XCTAssertEqual(line.selection, [ids[1], ids[2]])
        line.beginSort(ids[1])
        line.sort(ids[1], toX: 850)
        // The pair keeps its own order and lands after the photos it passed.
        XCTAssertEqual(order, [1, 4, 2, 3])
    }

    // MARK: The card under the pointer

    func testTheCardSitsUnderThePointer() {
        line.beginSort(ids[3])
        line.sort(ids[3], toX: 300)
        // It landed second, so the slot it was carried away from is the
        // second one; the shift is the rest of the way to the pointer.
        XCTAssertEqual(order, [1, 4, 2, 3])
        let slot = Layout.x(index: 1, count: line.items.count, width: width,
                            visible: line.visibleCount, scroll: line.scroll)
        XCTAssertEqual(line.sortShift, 300 - slot, accuracy: 0.5)
    }

    func testSortingEndsWhenTheButtonComesUp() {
        line.beginSort(ids[0])
        line.sort(ids[0], toX: 700)
        line.endSort(ids[0], keeping: true)
        XCTAssertNil(line.sortingID)
        XCTAssertEqual(line.sortShift, 0)
    }

    /// A line that has not been drawn yet has no width to measure slots
    /// against, so nothing should move rather than everything landing first.
    func testWithoutAWidthNothingMoves() {
        line.lineWidth = 0
        line.beginSort(ids[3])
        line.sort(ids[3], toX: 200)
        XCTAssertEqual(order, [1, 2, 3, 4])
    }
}
