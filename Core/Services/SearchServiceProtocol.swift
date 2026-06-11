struct SearchClassifiedApps {
    let visible: [RunningApp]
    let hidden: [RunningApp]
    let alwaysHidden: [RunningApp]
}

/// @mockable
protocol SearchServiceProtocol: Sendable {
    func getRunningApps() async -> [RunningApp]
    func getMenuBarApps() async -> [RunningApp]
    func getHiddenMenuBarApps() async -> [RunningApp]
    func getAlwaysHiddenMenuBarApps() async -> [RunningApp]
    @MainActor
    func cachedMenuBarApps() -> [RunningApp]
    @MainActor
    func cachedHiddenMenuBarApps() -> [RunningApp]
    @MainActor
    func cachedAlwaysHiddenMenuBarApps() -> [RunningApp]
    @MainActor
    func cachedVisibleMenuBarApps() -> [RunningApp]
    func refreshMenuBarApps() async -> [RunningApp]
    func refreshHiddenMenuBarApps() async -> [RunningApp]
    func refreshAlwaysHiddenMenuBarApps() async -> [RunningApp]
    func refreshVisibleMenuBarApps() async -> [RunningApp]
    @MainActor
    func cachedClassifiedApps() -> SearchClassifiedApps
    func refreshClassifiedApps() async -> SearchClassifiedApps
    func refreshKnownClassifiedApps() async -> SearchClassifiedApps
    func refreshKnownClassifiedAppsAllowingEstimatedFallback() async -> SearchClassifiedApps
    @MainActor
    func activate(app: RunningApp, isRightClick: Bool, origin: SearchServiceSupport.ActivationOrigin) async
}

extension SearchServiceProtocol {
    @MainActor
    func activate(app: RunningApp, isRightClick: Bool) async {
        await activate(app: app, isRightClick: isRightClick, origin: .direct)
    }
}
