import Foundation
@testable import SaneBar
import Testing

/// Behavioral coverage for the single-instance launch decision that prevents the
/// "-47 / fBsyErr (resource busy)" collision a customer hit when a freshly downloaded
/// SaneBar copy launched alongside the already-running login-item instance.
///
/// These assert the PURE decision logic, not source structure: each test fails if the
/// real decision regresses (e.g. if a duplicate stops terminating, or the surviving
/// instance stops being activated). The live double-launch runtime proof is run by the
/// orchestrator on the Mac Mini — see the report's repro/proof section.
struct DuplicateLaunchDecisionTests {
    typealias Resolution = SaneBarAppDelegate.DuplicateLaunchResolution

    // MARK: - duplicateLaunchResolution

    @Test("Another instance still alive after the grace window, no version info → terminate the current launch")
    func anotherInstanceAfterGraceTerminatesCurrent() {
        // Snapshot: one other instance was present at launch AND remains after the grace window.
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: 1
        )
        #expect(resolution == .terminateCurrent)
    }

    // MARK: - version-aware resolution (the update / "stuck on old version" fix)

    @Test("This launch is a NEWER build than the survivor → terminate the stale instance, keep the update")
    func newerBuildTerminatesStaleOthers() {
        // Sparkle relaunched build 2181 while a wedged 2180 instance is still alive
        // past the grace window. The new build must win, not be killed.
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: 1,
            currentBuild: 2181,
            maxSurvivingBuild: 2180
        )
        #expect(resolution == .terminateOthers)
    }

    @Test("This launch is an OLDER build than the survivor → yield to the newer running instance")
    func olderBuildTerminatesCurrent() {
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: 1,
            currentBuild: 2180,
            maxSurvivingBuild: 2181
        )
        #expect(resolution == .terminateCurrent)
    }

    @Test("Same build on both sides → yield (keep the already-running instance, first-wins)")
    func equalBuildKeepsExisting() {
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: 1,
            currentBuild: 2181,
            maxSurvivingBuild: 2181
        )
        #expect(resolution == .terminateCurrent)
    }

    @Test("Newest wins even against multiple stale survivors (max build is what matters)")
    func newerBuildBeatsHighestSurvivor() {
        // Two stale instances (2179 and 2180) linger; current 2181 is newer than the max.
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 2,
            othersAfterGrace: 2,
            currentBuild: 2181,
            maxSurvivingBuild: 2180
        )
        #expect(resolution == .terminateOthers)
    }

    @Test("No other instance at launch → continue launching (self is the only instance)")
    func onlySelfContinuesLaunch() {
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 0,
            othersAfterGrace: nil
        )
        #expect(resolution == .noConflict)
    }

    @Test("Other instance present at launch but gone after grace → keep current (handoff, e.g. Sparkle relaunch)")
    func handoffWindowKeepsCurrentWhenOtherExits() {
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: 0
        )
        #expect(resolution == .noConflict)
    }

    @Test("Other instance present at launch, grace not yet evaluated → wait for handoff before deciding")
    func presentAtLaunchWaitsForHandoff() {
        let resolution = SaneBarAppDelegate.duplicateLaunchResolution(
            othersAtLaunch: 1,
            othersAfterGrace: nil
        )
        #expect(resolution == .waitForHandoff)
    }

    // MARK: - activationTargetPID

    @Test("Activation target excludes the current (self) pid")
    func activationTargetExcludesSelf() {
        // Snapshot contains only self → there is no other instance to activate.
        let target = SaneBarAppDelegate.activationTargetPID(
            amongOtherPIDs: [4242],
            currentPID: 4242
        )
        #expect(target == nil)
    }

    @Test("Activation target is the earliest-launched survivor (lowest pid), never self")
    func activationTargetPicksOldestSurvivor() {
        let target = SaneBarAppDelegate.activationTargetPID(
            amongOtherPIDs: [900, 101, 555],
            currentPID: 900
        )
        // 101 is the lowest other pid; 900 (self) is excluded even though it is lower than 555.
        #expect(target == 101)
    }

    @Test("No other instances → no activation target")
    func activationTargetNilWhenAlone() {
        let target = SaneBarAppDelegate.activationTargetPID(
            amongOtherPIDs: [],
            currentPID: 4242
        )
        #expect(target == nil)
    }
}
