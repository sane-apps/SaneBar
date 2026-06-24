import Foundation
@testable import SaneBar
import Testing

/// Plan A — CHANGE B2 regression lock.
///
/// A failed zone move used to call `setMovingAppID(nil)` and nothing else, so the
/// Second Menu Bar silently cleared the in-flight indicator with zero feedback
/// (#166's "literally nothing happens"). `observeMoveResult` now ALSO records the
/// failed app via `recordFailedMove` so the UI can offer a retry. This is
/// informational only — it synthesizes no input and mutates no geometry.
@MainActor
@Suite("Browse Panel — Move Failure Surfacing")
struct BrowsePanelMoveFailureSurfacingTests {
    @Test("A failed zone move clears the in-flight indicator AND records a retryable failure")
    func failedMoveRecordsRetryableFailure() async {
        var movingAppID: String? = "com.example.icon"
        var failedAppID: String?

        let failingTask = Task<Bool, Never> { false }

        BrowsePanelMoveQueue.observeMoveResult(
            failingTask,
            appID: "com.example.icon",
            setMovingAppID: { movingAppID = $0 },
            recordFailedMove: { failedAppID = $0 }
        )

        // `observeMoveResult` spawns a nested @MainActor Task that awaits the
        // move result before recording the failure. Await the task value, then
        // yield so the nested observation Task is allowed to run to completion.
        _ = await failingTask.value
        for _ in 0 ..< 10 where failedAppID == nil {
            await Task.yield()
        }

        #expect(movingAppID == nil, "A failed move must clear the in-flight indicator")
        #expect(failedAppID == "com.example.icon", "A failed move must record the retryable failure")
    }

    @Test("A successful zone move neither clears nor records a failure")
    func successfulMoveDoesNotRecordFailure() async {
        var movingAppID: String? = "com.example.icon"
        var recordFailedMoveCalled = false

        let succeedingTask = Task<Bool, Never> { true }

        BrowsePanelMoveQueue.observeMoveResult(
            succeedingTask,
            appID: "com.example.icon",
            setMovingAppID: { movingAppID = $0 },
            recordFailedMove: { _ in recordFailedMoveCalled = true }
        )
        _ = await succeedingTask.value
        await Task.yield()
        await Task.yield()

        #expect(movingAppID == "com.example.icon", "A successful move must not clear the indicator from the failure path")
        #expect(!recordFailedMoveCalled, "A successful move must not record a failure")
    }
}
