import AppKit
import XCTest
@testable import Tendedero

/// What the card's menu offers, and to how many photos: the menu is built from
/// the line, so it can be inspected without a window.
@MainActor
final class CardMenuTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var line: Line!
    private var ids: [UUID] = []

    override func setUp() async throws {
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/card-menu-tests/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "captureline.card-menu-tests.\(UUID())"
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

    private func menu(for index: Int) throws -> NSMenu {
        let item = try XCTUnwrap(line.items.first { $0.id == ids[index] })
        return CardMenu.make(for: item, on: line)
    }

    private func item(_ menu: NSMenu, _ english: String) -> NSMenuItem? {
        menu.items.first { $0.title == L(english) }
    }

    /// Three photos picked: clearing one side cannot mean anything, so both
    /// items are there but unusable.
    func testBothSidesAreGreyedOutForAGroup() throws {
        pick(0)
        shiftPick(2)
        let menu = try menu(for: 1)
        XCTAssertEqual(item(menu, "Take down everything to the left")?.isEnabled, false)
        XCTAssertEqual(item(menu, "Take down everything to the right")?.isEnabled, false)
    }

    func testBothSidesAreAvailableForOnePhotoInTheMiddle() throws {
        pick(1)
        let menu = try menu(for: 1)
        XCTAssertEqual(item(menu, "Take down everything to the left")?.isEnabled, true)
        XCTAssertEqual(item(menu, "Take down everything to the right")?.isEnabled, true)
    }

    /// The ends of the line have nothing on one side, whatever is picked.
    func testTheEndOfTheLineHasNoSideToClear() throws {
        pick(0)
        let menu = try menu(for: 0)
        XCTAssertEqual(item(menu, "Take down everything to the left")?.isEnabled, false)
        XCTAssertEqual(item(menu, "Take down everything to the right")?.isEnabled, true)
    }

    /// Right-clicking a photo outside the group offers what a single photo
    /// offers, sides included.
    func testAPhotoOutsideTheGroupIsTreatedAsOne() throws {
        pick(0)
        shiftPick(2)
        let menu = try menu(for: 3)
        XCTAssertEqual(item(menu, "Take down everything to the left")?.isEnabled, true)
        XCTAssertEqual(item(menu, "Take down everything to the right")?.isEnabled, false)
    }

    func testTheMenuSaysHowManyArePicked() throws {
        pick(0)
        shiftPick(2)
        let menu = try menu(for: 1)
        let copy = try XCTUnwrap(menu.items.first { $0.title.hasPrefix(L("Copy")) })
        XCTAssertTrue(copy.title.contains("3"), "expected a count in \(copy.title)")
    }

    func testASinglePickGetsPlainTitles() throws {
        pick(1)
        let menu = try menu(for: 1)
        XCTAssertNotNil(item(menu, "Copy"), "a single pick should not be counted")
    }

    /// Quick Look and Markup work on one file, so they never carry a count.
    func testTheOnePhotoItemsStayUncounted() throws {
        pick(0)
        shiftPick(2)
        let menu = try menu(for: 1)
        XCTAssertNotNil(item(menu, "Quick Look"))
        XCTAssertNotNil(item(menu, "Markup"))
    }
}
