import Testing
@testable import Plume

/// The version line that `plume doctor` prints and the log writes at launch: it names the
/// commit of a dev build, so it must keep both numbers and never print a lone build number.
@Suite("Version line")
struct UpdatesTests {
    @Test func devBuildShowsLabelAndBuildNumber() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0.2-dev+8553033", "CFBundleVersion": "202610071530"]
        #expect(Updates.versionLine(info: info) == "1.0.2-dev+8553033 (202610071530)")
    }

    @Test func shortVersionAloneIsShownAsIs() {
        #expect(Updates.versionLine(info: ["CFBundleShortVersionString": "1.0.1"]) == "1.0.1")
    }

    @Test func noInfoPlistGivesDash() {
        #expect(Updates.versionLine(info: [:]) == "—")
    }

    /// A bare `.build/release/Plume` may carry a build number without a version.
    @Test func buildNumberWithoutShortVersionGivesDash() {
        #expect(Updates.versionLine(info: ["CFBundleVersion": "1"]) == "—")
    }
}
