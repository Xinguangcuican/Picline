import XCTest
@testable import Tendedero

/// Where new pictures go. The folder the user picks wins, but only while it is
/// there and writable: an external drive that has been unmounted must not stop
/// pictures from hanging, so the default folder takes over until it is back.
final class StorageFolderTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("picline-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        Inbox.chosenFolder = nil
    }

    override func tearDownWithError() throws {
        Inbox.chosenFolder = nil
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    func testTheDefaultFolderIsUsedUntilSomethingElseIsChosen() {
        XCTAssertNil(Inbox.chosenFolder)
        XCTAssertEqual(Inbox.folder.standardizedFileURL, Inbox.defaultFolder.standardizedFileURL)
    }

    func testAChosenFolderIsWherePicturesGo() throws {
        let folder = scratch.appendingPathComponent("Work Pictures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Inbox.remember(folder)

        XCTAssertEqual(Inbox.folder.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(Inbox.chosenFolder?.standardizedFileURL, folder.standardizedFileURL)
    }

    func testTheChoiceIsRemembered() throws {
        let folder = scratch.appendingPathComponent("Kept", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Inbox.remember(folder)

        // Reading it back the way a fresh launch would.
        XCTAssertEqual(Inbox.chosenFolder?.lastPathComponent, "Kept")
    }

    func testAChoiceThatIsGoneFallsBackToTheDefault() {
        let missing = scratch.appendingPathComponent("Unplugged Drive", isDirectory: true)
        Inbox.remember(missing)

        // Remembered, so it is used again when the drive comes back...
        XCTAssertEqual(Inbox.chosenFolder?.lastPathComponent, "Unplugged Drive")
        // ...but not while it is away.
        XCTAssertEqual(Inbox.folder.standardizedFileURL, Inbox.defaultFolder.standardizedFileURL)
    }

    func testAFileIsNotAFolder() throws {
        let file = scratch.appendingPathComponent("not a folder.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        Inbox.remember(file)

        XCTAssertFalse(Inbox.isUsable(file))
        XCTAssertEqual(Inbox.folder.standardizedFileURL, Inbox.defaultFolder.standardizedFileURL)
    }

    func testGoingBackToTheDefaultClearsTheChoice() throws {
        let folder = scratch.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Inbox.remember(folder)
        XCTAssertNotNil(Inbox.chosenFolder)

        Inbox.remember(nil)

        XCTAssertNil(Inbox.chosenFolder)
        XCTAssertEqual(Inbox.folder.standardizedFileURL, Inbox.defaultFolder.standardizedFileURL)
    }

    func testAnExistingFolderIsUsable() {
        XCTAssertTrue(Inbox.isUsable(scratch))
    }
}
