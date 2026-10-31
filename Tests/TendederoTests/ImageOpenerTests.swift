import AppKit
import XCTest
@testable import Tendedero

@MainActor
final class ImageOpenerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "captureline.opening-tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testUnconfiguredImagesUseSystemDefault() {
        let file = URL(fileURLWithPath: "/screenshots/image #1.png")
        var opened: [URL] = []
        let opener = ImageOpener(defaults: defaults,
                                 resolve: { _ in XCTFail("Should not resolve an application"); return nil },
                                 openDefault: { opened.append($0); return true },
                                 openApplication: { _, _, _ in XCTFail("Should use system default") },
                                 onFailure: { _, _ in XCTFail("Should succeed") })
        opener.open(file)
        XCTAssertEqual(opened, [file])
    }

    func testEachSuggestedEditorReceivesTheExactDocumentURL() {
        let file = URL(fileURLWithPath: "/screenshots/截图 with spaces #1.png")
        for application in ImageOpeningApplication.suggested {
            let appURL = URL(fileURLWithPath: "/Applications/\(application.name).app")
            var requests: [(URL, URL)] = []
            let opener = ImageOpener(defaults: defaults,
                                     resolve: { candidate in XCTAssertEqual(candidate, application); return appURL },
                                     openDefault: { _ in XCTFail("Should use the selected editor"); return false },
                                     openApplication: { file, app, done in requests.append((file, app)); done(nil) },
                                     onFailure: { _, _ in XCTFail("Should succeed") })
            opener.selected = application
            opener.open(file)
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.0, file)
            XCTAssertEqual(requests.first?.1, appURL)
        }
    }

    func testCustomChoicePersistsAndSystemDefaultClearsIt() {
        let custom = ImageOpeningApplication(name: "Custom Editor", bundleIdentifier: "local.test.editor",
                                              path: "/Applications/Custom Editor.app")
        let opener = ImageOpener(defaults: defaults)
        opener.selected = custom
        let restored = ImageOpener(defaults: defaults)
        XCTAssertEqual(restored.selected, custom)
        restored.selected = nil
        XCTAssertNil(opener.selected)
        XCTAssertNil(defaults.object(forKey: "imageOpeningApplication"))
    }

    func testInvalidPreferenceUsesSystemDefault() {
        for value in [["name": "Incomplete"], ["name": "", "bundleIdentifier": "local.test.editor"],
                      ["name": "Editor", "path": "relative/path.app"]] {
            defaults.set(value, forKey: "imageOpeningApplication")
            XCTAssertNil(ImageOpener(defaults: defaults).selected)
        }
    }

    func testApplicationMatchingUsesIdentityRatherThanLocalizedName() {
        let customPreview = ImageOpeningApplication(name: "预览", bundleIdentifier: "com.apple.Preview",
                                                     path: "/System/Applications/Preview.app")
        XCTAssertTrue(customPreview.matches(.preview))
        XCTAssertFalse(customPreview.matches(.shottr))
    }

    func testMissingEditorReportsFailureWithoutChangingPreference() {
        var failures: [ImageOpeningApplication?] = []
        let opener = ImageOpener(defaults: defaults, resolve: { _ in nil },
                                 openDefault: { _ in XCTFail("Fallback requires the user's choice"); return false },
                                 openApplication: { _, _, _ in XCTFail("Missing application") },
                                 onFailure: { _, application in failures.append(application) })
        opener.selected = .shottr
        XCTAssertFalse(opener.isAvailable(.shottr))
        opener.open(URL(fileURLWithPath: "/screenshots/image.png"))
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first ?? nil, .shottr)
        XCTAssertEqual(opener.selected, .shottr)
    }

    func testFailedHandoffReportsFailureOnMainActor() async throws {
        var failed = false
        let opener = ImageOpener(defaults: defaults,
                                 resolve: { _ in URL(fileURLWithPath: "/Applications/Snapzy.app") },
                                 openApplication: { _, _, done in done(NSError(domain: NSOSStatusErrorDomain, code: -10814)) },
                                 onFailure: { _, application in XCTAssertEqual(application, .snapzy); failed = true })
        opener.selected = .snapzy
        opener.open(URL(fileURLWithPath: "/screenshots/image.png"))
        for _ in 0..<20 where !failed { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(failed)
    }

    func testRecordingsContinueToUseDefaultPlayer() {
        var opened: [URL] = []
        let opener = ImageOpener(defaults: defaults,
                                 resolve: { _ in XCTFail("Video should not resolve an image editor"); return nil },
                                 openDefault: { opened.append($0); return true },
                                 openApplication: { _, _, _ in XCTFail("Video should not go to image editor") })
        opener.selected = .shottr
        let files = ["recording.mov", "recording.mp4"].map { URL(fileURLWithPath: "/recordings/" + $0) }
        files.forEach(opener.open)
        XCTAssertEqual(opened, files)
        XCTAssertEqual(opener.selected, .shottr)
    }

    func testLineOpenRoutesTheSelectedCardAndIgnoresUnknownIDs() throws {
        let file = URL(fileURLWithPath: "/screenshots/hanging.png")
        var opened: [URL] = []
        let opener = ImageOpener(defaults: defaults,
                                 resolve: { _ in URL(fileURLWithPath: "/Applications/Shottr.app") },
                                 openApplication: { file, _, done in opened.append(file); done(nil) })
        opener.selected = .shottr
        let line = Line(defaults: defaults, imageOpener: opener)
        let id = try XCTUnwrap(line.hang(file, quietly: true, thumbnail: NSImage(size: NSSize(width: 12, height: 8))))
        line.open(UUID())
        XCTAssertTrue(opened.isEmpty)
        line.open(id)
        XCTAssertEqual(opened, [file])
        XCTAssertEqual(line.liveCount, 1)
    }
}
