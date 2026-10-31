import AppKit
import XCTest
@testable import Tendedero

@MainActor
final class CaptureDeduplicationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/intake-tests/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "captureline.deduplication-tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func image(_ color: NSColor = .red) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var pixel = color == .blue ? [0, 0, 255, 255] : [255, 0, 0, 255]
        for y in 0..<8 { for x in 0..<12 { rep.setPixel(&pixel, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }

    private func file(_ name: String, color: NSColor = .red) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image(color).write(to: url, options: .atomic)
        return url
    }

    @MainActor
    private final class Intake {
        let line: Line
        let inbox: URL
        var events: [ReceivedCapture] = []
        lazy var receiver = CaptureReceiver(inbox: inbox,
            isPresent: { [weak self] url in self?.line.items.contains { $0.url == url && !$0.falling } ?? false },
            currentURLs: { [weak self] in self?.line.items.filter { !$0.falling }.map(\.url) ?? [] },
            onRemove: { [weak self] in self?.line.removeDuplicateOrMissingFile($0) },
            onCapture: { [weak self] capture in
                guard let self else { return }
                events.append(capture)
                if let previous = capture.replacingURL {
                    line.replaceFile(at: previous, with: capture.url, thumbnail: capture.thumbnail)
                } else if capture.isUpdate {
                    line.reloadThumbnail(for: capture.url, thumbnail: capture.thumbnail)
                } else { line.hang(capture.url, quietly: true, thumbnail: capture.thumbnail) }
            })

        init(defaults: UserDefaults, inbox: URL) {
            line = Line(defaults: defaults)
            line.maxItems = 100
            self.inbox = inbox
        }

        var live: [Pegged] { line.items.filter { !$0.falling } }
        var newCards: Int { events.filter { !$0.isUpdate }.count }

        func receive(_ url: URL, storage: CaptureInput.Storage = .reference,
                     source: CaptureInput.Source = .folder) {
            receiver.receive(CaptureInput(payload: .file(url, storage), source: source))
        }
    }

    private func intake() -> Intake { Intake(defaults: defaults, inbox: directory.appendingPathComponent("inbox")) }

    private func drain(_ intake: Intake, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(6)
        while intake.receiver.isProcessing, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(intake.receiver.isProcessing, file: file, line: line)
    }

    func testDelayedShottrExportAndRepeatedDragsKeepOneManagedCard() async throws {
        let intake = intake()
        let transient = try file("Shottr/SCR-transient.png")
        intake.receive(transient, storage: .copy)
        await drain(intake)
        let original = try XCTUnwrap(intake.live.first)
        try FileManager.default.removeItem(at: transient)
        // Longer than the old cross-channel two-second window.
        try await Task.sleep(for: .milliseconds(2200))
        for name in ["Shottr/SCR-export.png", "Shottr/SCR-export-2.png"] {
            intake.receive(try file(name), storage: .copy)
            await drain(intake)
        }
        XCTAssertEqual(intake.newCards, 1)
        XCTAssertEqual(intake.events.count, 1) // no repeated peek/update
        XCTAssertEqual(intake.live.map(\.id), [original.id])
        XCTAssertEqual(try Data(contentsOf: original.url), image())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: intake.inbox.path).count, 1)
    }

    func testDifferentDirectoriesAndClipboardShareTheSameCard() async throws {
        let intake = intake()
        let first = try file("Snapzy/saved.png")
        let second = try file("OtherTool/drag.png")
        intake.receive(first)
        intake.receive(second)
        intake.receiver.receive(CaptureInput(payload: .image(image()), source: .clipboard))
        await drain(intake)
        XCTAssertEqual(intake.newCards, 1)
        XCTAssertEqual(intake.live.map(\.url), [first])
        XCTAssertEqual(try Data(contentsOf: first), image())
        XCTAssertEqual(try Data(contentsOf: second), image())
    }

    func testTakingDownCardAllowsIdenticalImageToHangAgain() async throws {
        let intake = intake()
        let first = try file("first.png")
        intake.receive(first)
        await drain(intake)
        let id = try XCTUnwrap(intake.live.first?.id)
        intake.line.drop(id, quietly: true)
        let next = try file("next.png")
        intake.receive(next)
        await drain(intake)
        XCTAssertEqual(intake.newCards, 2)
        XCTAssertEqual(intake.live.map(\.url), [next])
        XCTAssertNotEqual(intake.live.first?.id, id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testRestartRebuildsIdentityFromPersistedCardsBeforeNewInput() async throws {
        let firstRun = intake()
        let original = try file("original.png")
        firstRun.receive(original, storage: .copy)
        await drain(firstRun)
        let saved = try XCTUnwrap(firstRun.live.first?.url)
        let restarted = intake()
        XCTAssertEqual(restarted.live.map(\.url), [saved])
        restarted.receive(try file("later-export.png"))
        await drain(restarted)
        XCTAssertEqual(restarted.newCards, 0)
        XCTAssertEqual(restarted.live.map(\.url), [saved])
    }

    func testStartupFoldsOldDuplicateCardsWithoutDeletingTheirFiles() async throws {
        let first = try file("first.png")
        let second = try file("second.png")
        defaults.set([first.path, second.path], forKey: "pegged")
        let intake = intake()
        let id = try XCTUnwrap(intake.live.first?.id)
        intake.receiver.refresh()
        await drain(intake)
        XCTAssertEqual(intake.live.map(\.id), [id])
        XCTAssertEqual(intake.newCards, 0)
        XCTAssertEqual(defaults.stringArray(forKey: "pegged"), [first.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testEditingMergedAliasCreatesNewCardWithoutOverwritingOriginal() async throws {
        let intake = intake()
        let original = try file("original.png")
        let alias = try file("alias.png")
        intake.receive(original)
        intake.receive(alias)
        await drain(intake)
        try image(.blue).write(to: alias, options: .atomic)
        intake.receive(alias)
        await drain(intake)
        XCTAssertEqual(intake.live.map(\.url), [original, alias])
        XCTAssertEqual(try Data(contentsOf: original), image())
        XCTAssertEqual(try Data(contentsOf: alias), image(.blue))
    }

    func testEditingBackingFileInvalidatesOldFingerprintAndAliases() async throws {
        let intake = intake()
        let original = try file("original.png")
        let alias = try file("alias.png")
        intake.receive(original)
        intake.receive(alias)
        await drain(intake)
        try image(.blue).write(to: original, options: .atomic)
        // No explicit file-change input: a later incoming image must still
        // compare against the actual current contents of the backing file.
        intake.receive(alias)
        await drain(intake)
        XCTAssertEqual(intake.live.map(\.url), [original, alias])
        XCTAssertEqual(intake.newCards, 2)
        XCTAssertTrue(intake.events.contains { $0.url == original && $0.isUpdate })
    }

    func testEditingManagedSnapshotDoesNotSuppressOriginalClipboardPixels() async throws {
        let intake = intake()
        intake.receiver.receive(CaptureInput(payload: .image(image()), source: .clipboard))
        await drain(intake)
        let saved = try XCTUnwrap(intake.live.first?.url)
        try image(.blue).write(to: saved, options: .atomic)
        intake.receiver.receive(CaptureInput(payload: .image(image()), source: .clipboard))
        await drain(intake)
        XCTAssertEqual(intake.live.count, 2)
        XCTAssertEqual(intake.newCards, 2)
        XCTAssertEqual(try Data(contentsOf: saved), image(.blue))
    }

    func testUpdatingCopiedPrimaryDetachesUnchangedAliases() async throws {
        let intake = intake()
        let original = try file("temporary.png")
        let alias = try file("export.png")
        intake.receive(original, storage: .copy)
        intake.receive(alias)
        await drain(intake)
        let saved = try XCTUnwrap(intake.live.first?.url)
        try image(.blue).write(to: original, options: .atomic)
        intake.receive(original, storage: .copy)
        await drain(intake)
        XCTAssertEqual(intake.live.count, 1)
        XCTAssertEqual(try Data(contentsOf: saved), image(.blue))
        XCTAssertEqual(try Data(contentsOf: alias), image())
        intake.receive(alias)
        await drain(intake)
        XCTAssertEqual(intake.live.count, 2)
    }

    func testDeletedBackingFileRecoversFromMatchingAliasPreservingCardIdentity() async throws {
        let intake = intake()
        let original = try file("original.png")
        let alias = try file("export.png")
        intake.receive(original)
        intake.receive(alias)
        await drain(intake)
        let id = try XCTUnwrap(intake.live.first?.id)
        try FileManager.default.removeItem(at: original)
        intake.receiver.refresh()
        await drain(intake)
        let saved = try XCTUnwrap(intake.live.first?.url)
        XCTAssertEqual(intake.live.map(\.id), [id])
        XCTAssertEqual(intake.newCards, 1)
        XCTAssertTrue(saved.path.hasPrefix(intake.inbox.path + "/"))
        XCTAssertEqual(defaults.stringArray(forKey: "pegged"), [saved.path])
        try FileManager.default.removeItem(at: alias)
        intake.receiver.refresh()
        await drain(intake)
        XCTAssertEqual(intake.live.count, 1)
        XCTAssertEqual(try Data(contentsOf: saved), image())
    }

    func testChangedAliasCannotRecoverDeletedBackingFileWithWrongPixels() async throws {
        let intake = intake()
        let original = try file("original.png")
        let alias = try file("export.png")
        intake.receive(original)
        intake.receive(alias)
        await drain(intake)
        try image(.blue).write(to: alias, options: .atomic)
        try FileManager.default.removeItem(at: original)
        intake.receiver.refresh()
        await drain(intake)
        XCTAssertTrue(intake.live.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: intake.inbox.path))
        XCTAssertEqual(try Data(contentsOf: alias), image(.blue))
    }

    func testEditThatMatchesAnotherCardMergesDisplayWithoutDeletingFiles() async throws {
        let intake = intake()
        let first = try file("first.png")
        let second = try file("second.png", color: .blue)
        intake.receive(first)
        intake.receive(second)
        await drain(intake)
        XCTAssertEqual(intake.live.count, 2)
        try image().write(to: second, options: .atomic)
        intake.receive(second)
        await drain(intake)
        XCTAssertEqual(intake.live.map(\.url), [first])
        XCTAssertEqual(try Data(contentsOf: second), image())
    }

    func testUnmatchedDeletedReferenceStillLeavesLine() async throws {
        let intake = intake()
        let original = try file("original.png")
        intake.receive(original)
        await drain(intake)
        try FileManager.default.removeItem(at: original)
        intake.receiver.refresh()
        await drain(intake)
        XCTAssertTrue(intake.live.isEmpty)
    }

    func testFileVersionAlwaysReadsCurrentMetadataForTheSameURLInstance() throws {
        let original = try file("original.png")
        let before = try XCTUnwrap(CaptureFileVersion(at: original))
        try FileManager.default.setAttributes([.modificationDate: before.modified.addingTimeInterval(10)],
                                             ofItemAtPath: original.path)
        XCTAssertNotEqual(CaptureFileVersion(at: original), before)
        try FileManager.default.removeItem(at: original)
        XCTAssertNil(CaptureFileVersion(at: original))
    }
}
