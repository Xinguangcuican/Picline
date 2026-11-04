import XCTest
@testable import Tendedero

/// Telling a newer release from the one that is running. Small rules, but every
/// one of them has a wrong version that looks right: `0.2.9` vs `0.2.10` is the
/// one that bites, because as text the second is shorter.
final class UpdateCheckerTests: XCTestCase {
    func testANewerPatchIsNewer() {
        XCTAssertTrue(isNewer("0.2.10", than: "0.2.9"))
        XCTAssertTrue(isNewer("0.2.5", than: "0.2.4"))
    }

    func testAnOlderVersionIsNot() {
        XCTAssertFalse(isNewer("0.2.8", than: "0.2.9"))
        XCTAssertFalse(isNewer("0.1.9", than: "0.2.0"))
    }

    func testTheSameVersionIsNotNewer() {
        XCTAssertFalse(isNewer("0.2.9", than: "0.2.9"))
        XCTAssertFalse(isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(isNewer("0.2", than: "0.2.0"))
    }

    /// The carry rule the versions now follow: after 0.2.9 comes 0.3.0, and it
    /// has to count as later.
    func testCarryingIntoTheNextMiddleNumber() {
        XCTAssertTrue(isNewer("0.3.0", than: "0.2.9"))
        XCTAssertFalse(isNewer("0.2.9", than: "0.3.0"))
    }

    /// Whatever else is in the tag, the number is what counts.
    func testTagsWithAPrefixOrSuffixStillCompare() {
        XCTAssertTrue(isNewer("v0.3.0".dropFirst().description, than: "0.2.9"))
        XCTAssertFalse(isNewer("0.2.9-beta", than: "0.2.9"))
    }

    /// The field out of a release payload, which is all this needs from GitHub.
    func testTheTagIsReadOutOfTheRelease() throws {
        let json = #"{"url":"https://api.github.com/x","tag_name":"v0.3.0","name":"Picline 0.3.0"}"#
        XCTAssertEqual(UpdateChecker.tag(in: Data(json.utf8)), "v0.3.0")
    }

    /// The cheap route: `/releases/latest` redirects to `/releases/tag/v0.3.0`,
    /// and the last part of that address is the answer.
    func testTheTagIsReadOffTheRedirect() {
        XCTAssertEqual(UpdateChecker.tag(inPath: "v0.3.0"), "v0.3.0")
        XCTAssertEqual(UpdateChecker.tag(inPath: "latest"), nil)
        XCTAssertEqual(UpdateChecker.tag(inPath: "v"), nil)
        XCTAssertEqual(UpdateChecker.tag(inPath: "vNext"), nil)
    }

    func testSomethingThatIsNotAReleaseHasNoTag() {
        XCTAssertNil(UpdateChecker.tag(in: Data(#"{"message":"Not Found"}"#.utf8)))
        XCTAssertNil(UpdateChecker.tag(in: Data()))
    }
}
