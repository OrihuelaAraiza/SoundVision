import XCTest
@testable import SoundVision

final class VoiceRenderHealthTests: XCTestCase {
    func testHealthyRootDoesNotHideAStalledBranch() {
        var root = VoiceRenderHealth()
        var branch = VoiceRenderHealth()
        XCTAssertFalse(root.needsRestart(blocks: 100, isPlaying: true, now: 0))
        XCTAssertFalse(branch.needsRestart(blocks: 0, isPlaying: true, now: 0))
        XCTAssertFalse(root.needsRestart(blocks: 200, isPlaying: true, now: 2))
        XCTAssertTrue(branch.needsRestart(blocks: 0, isPlaying: true, now: 2))
        XCTAssertFalse(root.isStalled)
        XCTAssertTrue(branch.isStalled)
        XCTAssertFalse(branch.needsRestart(blocks: 30, isPlaying: true, now: 3))
        XCTAssertFalse(branch.isStalled)
    }

    func testStoppedControllerRecoversImmediatelyAndRetriesAreBounded() {
        var health = VoiceRenderHealth()
        XCTAssertTrue(health.needsRestart(blocks: 0, isPlaying: false, now: 0))
        XCTAssertFalse(health.needsRestart(blocks: 0, isPlaying: false, now: 1))
        XCTAssertTrue(health.needsRestart(blocks: 0, isPlaying: false, now: 2))
        XCTAssertFalse(health.needsRestart(blocks: 0, isPlaying: false, now: 4))
        XCTAssertTrue(health.isStalled)
    }
}
