import ApplicationServices

enum AccessibilityBoundedAXChildFetch {
    internal nonisolated static func children(
        of element: AXUIElement,
        maxCount: Int
    ) -> (children: [AXUIElement], truncated: Bool) {
        guard maxCount > 0 else { return ([], true) }

        let requestedCount = CFIndex(maxCount)
        var childCount: CFIndex = 0
        let countResult = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &childCount)

        if countResult == .success {
            guard childCount > 0 else { return ([], false) }

            let fetchCount = min(childCount, requestedCount)
            let children = rangedChildren(of: element, fetchCount: fetchCount)
            return (children, childCount > requestedCount || children.count < Int(fetchCount))
        }

        let children = rangedChildren(of: element, fetchCount: requestedCount)
        return (children, true)
    }

    private nonisolated static func rangedChildren(
        of element: AXUIElement,
        fetchCount: CFIndex
    ) -> [AXUIElement] {
        guard fetchCount > 0 else { return [] }

        var boundedChildren: CFArray?
        let fetchResult = AXUIElementCopyAttributeValues(
            element,
            kAXChildrenAttribute as CFString,
            0,
            fetchCount,
            &boundedChildren
        )
        guard fetchResult == .success,
              let children = boundedChildren as? [AXUIElement] else {
            return []
        }
        return children
    }
}
