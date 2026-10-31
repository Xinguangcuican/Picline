import AppKit
import XCTest
@testable import Tendedero

@MainActor
final class CaptureIntakeTests: XCTestCase {
    private var directory: URL!
    private var watchers: [ScreenshotWatcher] = []

    override func setUp() async throws {
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/intake-tests/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        watchers.forEach { $0.stop() }
        watchers = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func image(_ color: NSColor = .red, type: NSBitmapImageRep.FileType = .png) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var pixel = color == .blue ? [0, 0, 255, 255] : [255, 0, 0, 255]
        for y in 0..<8 { for x in 0..<12 { rep.setPixel(&pixel, atX: x, y: y) } }
        return rep.representation(using: type, properties: [:])!
    }

    private func eventually(_ predicate: () -> Bool, timeout: TimeInterval = 6,
                            file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    func testFolderAndMixedClipboardProduceOneCardAndPreserveOriginal() async throws {
        let file = directory.appendingPathComponent("Snapzy.png")
        try image().write(to: file)
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        receiver.receive(CaptureInput(payload: .file(file, .copy), source: .clipboard))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.url, file)
        XCTAssertEqual(try Data(contentsOf: file), image())
    }

    func testClipboardFirstKeepsManagedCopyWhenFolderReportsSameFile() async throws {
        let file = directory.appendingPathComponent("Snapzy.png")
        try image().write(to: file)
        let inbox = directory.appendingPathComponent("inbox")
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: inbox, isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .file(file, .copy), source: .clipboard))
        receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 1)
        let saved = try XCTUnwrap(captures.first?.url)
        XCTAssertNotEqual(saved, file)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try Data(contentsOf: saved), image())
        let attrs = try FileManager.default.attributesOfItem(atPath: saved.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testTIFFClipboardAndPNGFileDeduplicateByPixels() async throws {
        let file = directory.appendingPathComponent("shottr.png")
        try image().write(to: file)
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .image(image(type: .tiff)), source: .clipboard))
        receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 1)
    }

    func testIdenticalCapturesFromSameFolderShareOneCard() async throws {
        var visible: Set<URL> = []
        var count = 0
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: { visible.insert($0.url); count += 1 })
        for name in ["first.png", "second.png"] {
            let file = directory.appendingPathComponent(name)
            try image().write(to: file)
            receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        }
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(count, 1)
    }

    func testSlowWriteIsRetriedAndOverwriteUpdatesSameCard() async throws {
        let file = directory.appendingPathComponent("slow.png")
        try Data([0x89]).write(to: file)
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertTrue(captures.isEmpty)
        try image().write(to: file)
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 1)
        try image(.blue).write(to: file, options: .atomic)
        receiver.receive(CaptureInput(payload: .file(file, .reference), source: .folder))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 2)
        guard captures.count == 2 else { return }
        XCTAssertTrue(captures[1].isUpdate)
        XCTAssertEqual(captures[1].url, captures[0].url)
    }

    func testInvalidImageIsNotSaved() async {
        var count = 0
        let inbox = directory.appendingPathComponent("inbox")
        let receiver = CaptureReceiver(inbox: inbox, isPresent: { _ in false }, onCapture: { _ in count += 1 })
        receiver.receive(CaptureInput(payload: .image(Data("not an image".utf8)), source: .clipboard))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    }

    func testCopyingOriginalAgainAfterEditingManagedCopyIsNotSuppressed() async throws {
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .image(image()), source: .clipboard))
        await eventually { !receiver.isProcessing }
        let saved = try XCTUnwrap(captures.first?.url)
        try image(.blue).write(to: saved, options: .atomic)
        receiver.receive(CaptureInput(payload: .file(saved, .reference), source: .folder))
        await eventually { !receiver.isProcessing }
        receiver.receive(CaptureInput(payload: .image(image()), source: .clipboard))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 3)
        XCTAssertEqual(visible.count, 2)
    }

    func testClipboardAcceptsImageFilesFromAnyFolderAndFiltersPrivacyMarkers() {
        let png = image()
        let mixed = NSPasteboardItem()
        mixed.setData(png, forType: .png)
        mixed.setString(directory.appendingPathComponent("capture.png").absoluteString, forType: .fileURL)
        XCTAssertEqual(ClipboardWatcher.inputs(from: [mixed]).count, 1)
        let sibling = NSPasteboardItem()
        sibling.setString(URL(fileURLWithPath: directory.path + "-outside/image.png").absoluteString, forType: .fileURL)
        XCTAssertEqual(ClipboardWatcher.inputs(from: [sibling]).count, 1)
        for type in [ClipboardWatcher.ownType,
                     .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
                     .init("org.nspasteboard.AutoGeneratedType")] {
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setString("ignored", forType: type)
            XCTAssertTrue(ClipboardWatcher.inputs(from: [item]).isEmpty)
        }
    }

    func testClipboardBatchAndPureImages() {
        let first = NSPasteboardItem()
        first.setString(directory.appendingPathComponent("display1.png").absoluteString, forType: .fileURL)
        let second = NSPasteboardItem()
        second.setString(directory.appendingPathComponent("display2.png").absoluteString, forType: .fileURL)
        XCTAssertEqual(ClipboardWatcher.inputs(from: [first, second]).count, 2)
        let pure = NSPasteboardItem()
        pure.setData(image(type: .tiff), forType: .tiff)
        XCTAssertEqual(ClipboardWatcher.inputs(from: [pure]).count, 1)
    }

    func testClipboardAcceptsImageWithAccompanyingTextButIgnoresTextOnly() {
        let mixed = NSPasteboardItem()
        mixed.setData(image(), forType: .png)
        mixed.setString("image description", forType: .string)
        mixed.setString("<img src='image.png'>", forType: .html)
        XCTAssertEqual(ClipboardWatcher.inputs(from: [mixed]).count, 1)
        let text = NSPasteboardItem()
        text.setString("/somewhere/image.png", forType: .string)
        XCTAssertTrue(ClipboardWatcher.inputs(from: [text]).isEmpty)
    }

    func testFinderImageFileTakesPriorityOverItsTIFFRepresentation() async throws {
        let file = directory.appendingPathComponent("Finder image.png")
        try image(.blue).write(to: file)
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setString(file.path, forType: .string)
        item.setData(image(type: .tiff), forType: .tiff)
        let inputs = ClipboardWatcher.inputs(from: [item])
        XCTAssertEqual(inputs.count, 1)
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { _ in false }, onCapture: { captures.append($0) })
        inputs.forEach(receiver.receive)
        await eventually { !receiver.isProcessing }
        let capture = try XCTUnwrap(captures.first)
        XCTAssertEqual(capture.originalURL, file)
        XCTAssertNotEqual(capture.url, file)
        XCTAssertEqual(try Data(contentsOf: capture.url), image(.blue))
        XCTAssertEqual(try Data(contentsOf: file), image(.blue))
    }

    func testWeChatFileURLAndTIFFRemainUsableAfterTemporaryFileExpires() async throws {
        let item = NSPasteboardItem()
        item.setString(directory.appendingPathComponent("expired/WeChat.png").absoluteString, forType: .fileURL)
        item.setData(image(type: .tiff), forType: .tiff)
        // Format names observed on the user's Mac; no real clipboard content
        // is read or retained by this fixture.
        item.setData(Data(), forType: .init("com.trolltech.anymime.application--x-qt-image"))
        item.setData(Data(), forType: .init("com.trolltech.anymime.text--uri-list"))
        let inputs = ClipboardWatcher.inputs(from: [item])
        XCTAssertEqual(inputs.count, 1)
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { _ in false }, onCapture: { captures.append($0) })
        inputs.forEach(receiver.receive)
        await eventually { !receiver.isProcessing }
        let capture = try XCTUnwrap(captures.first)
        XCTAssertNil(capture.originalURL)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: capture.url)))
        XCTAssertEqual(bitmap.pixelsWide, 12)
        XCTAssertEqual(bitmap.pixelsHigh, 8)
        let pixel = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.redComponent, 0.99)
        XCTAssertLessThan(pixel.blueComponent, 0.01)
    }

    func testClipboardDoesNotReceiveFileIconsOrRemoteFileURLs() {
        for raw in [directory.appendingPathComponent("document.pdf").absoluteString,
                    directory.appendingPathComponent("notes.txt").absoluteString,
                    "https://example.com/image.png", "not a URL"] {
            let item = NSPasteboardItem()
            item.setString(raw, forType: .fileURL)
            item.setData(image(type: .tiff), forType: .tiff)
            XCTAssertTrue(ClipboardWatcher.inputs(from: [item]).isEmpty, raw)
        }
    }

    func testInvalidClipboardFallbackCannotCreateACard() async {
        let item = NSPasteboardItem()
        item.setString(directory.appendingPathComponent("missing.png").absoluteString, forType: .fileURL)
        item.setData(Data("not a TIFF".utf8), forType: .tiff)
        let inputs = ClipboardWatcher.inputs(from: [item])
        var count = 0
        let inbox = directory.appendingPathComponent("inbox")
        let receiver = CaptureReceiver(inbox: inbox, isPresent: { _ in false }, onCapture: { _ in count += 1 })
        inputs.forEach(receiver.receive)
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    }

    func testWatcherFindsNestedImagesAndInPlaceChangesWithoutImportingHistory() async throws {
        let old = directory.appendingPathComponent("old.png")
        try image().write(to: old)
        try await Task.sleep(for: .milliseconds(30))
        var events: [URL] = []
        let watcher = ScreenshotWatcher(folder: directory, anyImage: true, recursive: true,
                                        onNew: { events.append($0) }, onChange: {})
        watchers.append(watcher)
        watcher.start()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(events.isEmpty)
        let child = directory.appendingPathComponent("2026/10", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let file = child.appendingPathComponent("new.png")
        try image().write(to: file)
        await eventually { events.count == 1 }
        try image(.blue).write(to: file)
        await eventually { events.count == 2 }
        XCTAssertEqual(events, [file, file])
        watcher.stop()
        try image().write(to: child.appendingPathComponent("stopped.png"))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(events.count, 2)
    }

    func testNonrecursiveWatcherIgnoresNestedFilesAndStopDuringStart() async throws {
        var events: [URL] = []
        let watcher = ScreenshotWatcher(folder: directory, anyImage: true,
                                        onNew: { events.append($0) }, onChange: {})
        watchers.append(watcher)
        watcher.start()
        watcher.stop()
        watcher.start()
        try await Task.sleep(for: .milliseconds(500))
        let child = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try image().write(to: child.appendingPathComponent("ignored.png"))
        let direct = directory.appendingPathComponent("direct.png")
        try image().write(to: direct)
        await eventually { !events.isEmpty }
        XCTAssertEqual(events, [direct])
    }

    func testTemporaryStoragePolicyDoesNotChangeOrdinaryFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home.appendingPathComponent("Library/Containers/cc.ffitch.shottr/Data")
        XCTAssertEqual(CaptureInput.Storage.forFolder(container.appendingPathComponent("tmp/cc.ffitch.shottr")), .copy)
        XCTAssertEqual(CaptureInput.Storage.forFolder(container.appendingPathComponent("tmp")), .copy)
        XCTAssertEqual(CaptureInput.Storage.forFolder(FileManager.default.temporaryDirectory), .copy)
        XCTAssertEqual(CaptureInput.Storage.forFolder(URL(fileURLWithPath: "/tmp/captureline")), .copy)
        XCTAssertEqual(CaptureInput.Storage.forFolder(URL(fileURLWithPath: "/private/var/tmp/captureline")), .copy)
        XCTAssertEqual(CaptureInput.Storage.forFolder(container.appendingPathComponent("tmp-exports")), .reference)
        XCTAssertEqual(CaptureInput.Storage.forFolder(home.appendingPathComponent("Documents/tmp")), .reference)
        XCTAssertEqual(CaptureInput.Storage.forFolder(home.appendingPathComponent("Desktop/Snapzy")), .reference)
        XCTAssertEqual(CaptureInput.Storage.forFolder(Inbox.folder), .reference)
    }

    func testPiclineRenameKeepsExistingInboxAndItsFiles() throws {
        let base = directory.appendingPathComponent("Application Support")
        let legacy = base.appendingPathComponent("CaptureLine Preview/Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let saved = legacy.appendingPathComponent("existing.png")
        try image().write(to: saved)
        // A new folder left by an earlier launch must not hide the old cards.
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Picline/Screenshots"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(Inbox.storageFolder(in: base), legacy)
        XCTAssertEqual(try Data(contentsOf: saved), image())
    }

    func testNewPiclineInstallationUsesItsOwnInboxName() {
        let base = directory.appendingPathComponent("Application Support")
        XCTAssertEqual(Inbox.storageFolder(in: base), base.appendingPathComponent("Picline/Screenshots", isDirectory: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
    }

    func testShortLivedTemporaryCaptureSurvivesDeletionAndRealLinePrune() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("captureline-ephemeral-\(UUID())")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let source = sourceRoot.appendingPathComponent("SCR-transient.png")
        try image().write(to: source)
        let suite = "captureline.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = Line(defaults: defaults)
        let inbox = directory.appendingPathComponent("inbox")
        let receiver = CaptureReceiver(inbox: inbox,
                                       isPresent: { url in line.items.contains { $0.url == url && !$0.falling } },
                                       onCapture: { line.hang($0.url, quietly: true, thumbnail: $0.thumbnail) })
        receiver.receive(CaptureInput(payload: .file(source, .forFolder(sourceRoot)), source: .folder))
        // Shottr removes a staging capture almost immediately. The old
        // reference path lost it during its initial 200 ms stability wait.
        try await Task.sleep(for: .milliseconds(80))
        try FileManager.default.removeItem(at: source)
        await eventually { !receiver.isProcessing }
        line.prune()
        XCTAssertEqual(line.liveCount, 1)
        let saved = try XCTUnwrap(line.items.first?.url)
        XCTAssertTrue(saved.path.hasPrefix(inbox.path + "/"))
        XCTAssertEqual(try Data(contentsOf: saved), image())
        XCTAssertEqual(defaults.stringArray(forKey: "pegged"), [saved.path])
    }

    func testPermanentReferenceStillLeavesLineWhenOriginalIsRemoved() async throws {
        let suite = "captureline.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = Line(defaults: defaults)
        let source = directory.appendingPathComponent("persistent.png")
        try image().write(to: source)
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { url in line.items.contains { $0.url == url && !$0.falling } },
                                       onCapture: { line.hang($0.url, quietly: true, thumbnail: $0.thumbnail) })
        receiver.receive(CaptureInput(payload: .file(source, .forFolder(directory)), source: .folder))
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(line.items.first?.url, source)
        try FileManager.default.removeItem(at: source)
        line.prune()
        XCTAssertEqual(line.liveCount, 0)
    }

    func testTemporaryCopyStillWaitsForACompleteImage() async throws {
        let source = directory.appendingPathComponent("partial.png")
        try Data([0x89]).write(to: source)
        var visible: Set<URL> = []
        var captures: [ReceivedCapture] = []
        let receiver = CaptureReceiver(inbox: directory.appendingPathComponent("inbox"),
                                       isPresent: { visible.contains($0) }, onCapture: {
            visible.insert($0.url); captures.append($0)
        })
        receiver.receive(CaptureInput(payload: .file(source, .copy), source: .folder))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(captures.isEmpty)
        try image().write(to: source)
        await eventually { !receiver.isProcessing }
        XCTAssertEqual(captures.count, 1)
        let saved = try XCTUnwrap(captures.first?.url)
        XCTAssertNotEqual(saved, source)
        XCTAssertEqual(try Data(contentsOf: saved), image())
    }
}
