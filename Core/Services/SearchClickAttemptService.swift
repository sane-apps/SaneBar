import CoreGraphics
import Foundation

struct SearchClickAttemptResult {
    let success: Bool
    let timedOut: Bool
    let verification: String
}

struct SearchClickAttemptRequest {
    let target: RunningApp
    let fallbackCenter: CGPoint?
    let isRightClick: Bool
    let preferHardwareFirst: Bool
    let allowImmediateFallbackCenter: Bool
    let requireObservableReaction: Bool
}

enum SearchClickAttemptService {
    static func perform(
        axService: AccessibilityService,
        request: SearchClickAttemptRequest,
        baseTimeoutMs: Int
    ) async -> SearchClickAttemptResult {
        let timeoutMs = SearchServiceSupport.clickAttemptTimeoutMs(
            baseMs: baseTimeoutMs,
            requireObservableReaction: request.requireObservableReaction
        )
        return await withTaskGroup(of: SearchClickAttemptResult.self) { group in
            group.addTask(priority: .userInitiated) {
                let result = axService.clickMenuBarItemResult(
                    bundleID: request.target.bundleId,
                    menuExtraId: request.target.menuExtraIdentifier,
                    statusItemIndex: request.target.statusItemIndex,
                    fallbackCenter: request.fallbackCenter,
                    isRightClick: request.isRightClick,
                    preferHardwareFirst: request.preferHardwareFirst,
                    allowImmediateFallbackCenter: request.allowImmediateFallbackCenter
                )
                return SearchClickAttemptResult(
                    success: result.success,
                    timedOut: false,
                    verification: result.verification
                )
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                return SearchClickAttemptResult(success: false, timedOut: true, verification: "failed (timed out)")
            }

            let timeout = SearchClickAttemptResult(success: false, timedOut: true, verification: "failed (timed out)")
            let result = await group.next() ?? timeout
            group.cancelAll()
            return result
        }
    }
}
