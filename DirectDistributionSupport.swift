#if os(macOS) && !APP_STORE && !SETAPP
import AppKit
import SaneUI

enum SaneAppMover {
    typealias Prompt = SaneApplicationMover.Prompt

    @MainActor
    @discardableResult
    static func moveToApplicationsFolderIfNeeded(prompt: Prompt) -> Bool {
        SaneApplicationMover.moveToApplicationsFolderIfNeeded(prompt: prompt)
    }
}
#endif
