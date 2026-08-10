import Foundation
import Testing
@testable import CmuxWorkspaces

@Suite struct RestoredPanelTitleBoundaryTests {
    @Test func internallySeededTitleStaysInertWhileGenuineAgentTitleApplies() {
        let seededInput = " internal bootstrap payload\n"
        let seededTitle = seededInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var boundary = RestoredPanelTitleBoundary(
            internallySeededInput: seededInput,
            shellState: .promptIdle
        )

        let seededTitleAppliesFirst = boundary.shouldApply(rawTitle: seededTitle)
        #expect(!seededTitleAppliesFirst)
        #expect(boundary.observe(shellState: .commandRunning) == nil)
        let seededTitleAppliesAfterRunning = boundary.shouldApply(rawTitle: seededTitle)
        #expect(!seededTitleAppliesAfterRunning)
        let resumedTitleApplies = boundary.shouldApply(rawTitle: "Resumed Codex session")
        #expect(resumedTitleApplies)
        #expect(!boundary.isReleased)
    }

    @Test func userCommandReleasesBufferedTitle() {
        var boundary = RestoredPanelTitleBoundary(
            internallySeededInput: nil,
            shellState: .promptIdle
        )

        let preexecTitleApplies = boundary.shouldApply(rawTitle: "cd /tmp/cmux")
        #expect(!preexecTitleApplies)
        #expect(boundary.observe(shellState: .commandRunning) == "cd /tmp/cmux")
        #expect(boundary.isReleased)
        let releasedTitleApplies = boundary.shouldApply(rawTitle: "/tmp/cmux")
        #expect(releasedTitleApplies)
    }

    @Test func alreadyRunningUnseededShellStartsReleased() {
        var boundary = RestoredPanelTitleBoundary(
            internallySeededInput: nil,
            shellState: .commandRunning
        )

        #expect(boundary.isReleased)
        let genuineTitleApplies = boundary.shouldApply(rawTitle: "Genuine running command")
        #expect(genuineTitleApplies)
    }
}
