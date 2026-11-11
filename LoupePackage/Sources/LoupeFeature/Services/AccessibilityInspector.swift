import Foundation
@preconcurrency import ApplicationServices
import AppKit

/// Service that wraps macOS Accessibility APIs for UI element inspection
@MainActor
@Observable
public final class AccessibilityInspector {

    // MARK: - Published State

    public private(set) var isAccessibilityEnabled = false
    public private(set) var runningApps: [TargetApp] = []
    public private(set) var currentElement: AXElementInfo?

    // MARK: - Private State

    private var targetAppElement: AXUIElement?

    // MARK: - Initialization

    public init() {
        checkAccessibilityPermission()
        refreshRunningApps()
    }

    // MARK: - Permission Management

    /// Check if accessibility permission is granted
    public func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        print("[Loupe] Accessibility check: \(trusted ? "GRANTED" : "DENIED")")
        isAccessibilityEnabled = trusted
    }

    /// Request accessibility permission (shows system prompt)
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Check again after a short delay (user might grant permission)
        Task {
            try? await Task.sleep(for: .seconds(1))
            checkAccessibilityPermission()
        }
    }

    // MARK: - App Management

    /// Refresh the list of running applications
    public func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { TargetApp(from: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Set the target application to inspect
    public func setTargetApp(_ app: TargetApp) {
        targetAppElement = AXUIElementCreateApplication(app.id)
        currentElement = nil
    }

    /// Clear the target application
    public func clearTargetApp() {
        targetAppElement = nil
        currentElement = nil
    }

    // MARK: - Element Inspection

    /// Get the UI element at a screen position
    public func elementAt(screenPosition: CGPoint) -> AXElementInfo? {
        guard let appElement = targetAppElement else { return nil }

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            appElement,
            Float(screenPosition.x),
            Float(screenPosition.y),
            &element
        )

        guard result == .success, let element = element else {
            return nil
        }

        return extractElementInfo(from: element)
    }

    /// Update the current element based on mouse position
    public func updateElementAtPosition(_ screenPosition: CGPoint) {
        currentElement = elementAt(screenPosition: screenPosition)
    }

    // MARK: - Element Info Extraction

    private func extractElementInfo(from element: AXUIElement) -> AXElementInfo? {
        let role = getStringAttribute(element, kAXRoleAttribute as CFString)

        guard let role = role else { return nil }

        let subrole = getStringAttribute(element, kAXSubroleAttribute as CFString)
        let identifier = getStringAttribute(element, kAXIdentifierAttribute as CFString)
        let title = getStringAttribute(element, kAXTitleAttribute as CFString)
        let value = getStringAttribute(element, kAXValueAttribute as CFString)
        let frame = getFrameAttribute(element)
        let hierarchyPath = buildHierarchyPath(from: element)

        // Extended attributes
        let axDescription = getStringAttribute(element, kAXDescriptionAttribute as CFString)
        let help = getStringAttribute(element, kAXHelpAttribute as CFString)
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as CFString)
        let enabled = getBoolAttribute(element, kAXEnabledAttribute as CFString)
        let focused = getBoolAttribute(element, kAXFocusedAttribute as CFString)

        // Get siblings for context
        let siblings = getSiblings(of: element, elementFrame: frame, maxCount: 4)

        // Get window context
        let (windowFrame, windowTitle, windowLevel) = getWindowContext(for: element)

        return AXElementInfo(
            role: role,
            subrole: subrole,
            identifier: identifier,
            title: title,
            value: value,
            frame: frame,
            hierarchyPath: hierarchyPath,
            element: element,
            siblings: siblings,
            axDescription: axDescription,
            help: help,
            roleDescription: roleDescription,
            enabled: enabled,
            focused: focused,
            windowFrame: windowFrame,
            windowTitle: windowTitle,
            windowLevel: windowLevel
        )
    }

    /// Extract element info with all attributes for forensic output
    public func extractElementInfoForensic(from element: AXUIElement) -> AXElementInfo? {
        guard let info = extractElementInfo(from: element) else { return nil }

        // Get all attributes
        let allAttrs = getAllAttributes(of: element)

        // Create a new AXElementInfo with all attributes included
        return AXElementInfo(
            role: info.role,
            subrole: info.subrole,
            identifier: info.identifier,
            title: info.title,
            value: info.value,
            frame: info.frame,
            hierarchyPath: info.hierarchyPath,
            element: info.element,
            siblings: info.siblings,
            axDescription: info.axDescription,
            help: info.help,
            roleDescription: info.roleDescription,
            enabled: info.enabled,
            focused: info.focused,
            windowFrame: info.windowFrame,
            windowTitle: info.windowTitle,
            windowLevel: info.windowLevel,
            allAttributes: allAttrs
        )
    }

    private func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success, let cfValue = value else { return nil }

        if let stringValue = cfValue as? String {
            return stringValue
        }

        return nil
    }

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success, let cfValue = value else { return nil }

        if let boolValue = cfValue as? Bool {
            return boolValue
        }

        // CFBoolean handling
        if CFGetTypeID(cfValue) == CFBooleanGetTypeID() {
            return CFBooleanGetValue(cfValue as! CFBoolean)
        }

        return nil
    }

    private func getIntAttribute(_ element: AXUIElement, _ attribute: CFString) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success, let cfValue = value else { return nil }

        if let number = cfValue as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private func getFrameAttribute(_ element: AXUIElement) -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero

        if posResult == .success, let posValue = positionValue {
            var point = CGPoint.zero
            if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                position = point
            }
        }

        if sizeResult == .success, let szValue = sizeValue {
            var sz = CGSize.zero
            if AXValueGetValue(szValue as! AXValue, .cgSize, &sz) {
                size = sz
            }
        }

        return CGRect(origin: position, size: size)
    }

    private func buildHierarchyPath(from element: AXUIElement) -> [HierarchyNode] {
        var path: [HierarchyNode] = []
        var current: AXUIElement? = element

        while let el = current {
            if let role = getStringAttribute(el, kAXRoleAttribute as CFString) {
                let subrole = getStringAttribute(el, kAXSubroleAttribute as CFString)
                let identifier = getStringAttribute(el, kAXIdentifierAttribute as CFString)
                let title = getStringAttribute(el, kAXTitleAttribute as CFString)
                let description = getStringAttribute(el, kAXDescriptionAttribute as CFString)
                let node = HierarchyNode(role: role, subrole: subrole, identifier: identifier, title: title, description: description)
                path.insert(node, at: 0)
            }

            // Get parent
            var parentValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentValue)

            if result == .success, let parent = parentValue {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }

            // Safety limit to prevent infinite loops
            if path.count > 20 { break }
        }

        return path
    }

    // MARK: - Sibling Extraction

    /// Get sibling elements for disambiguation context
    /// - Parameters:
    ///   - element: The element to find siblings for
    ///   - elementFrame: The frame of the element (for position comparison)
    ///   - maxCount: Maximum number of siblings to return
    /// - Returns: Array of SiblingInfo describing nearby elements
    private func getSiblings(of element: AXUIElement, elementFrame: CGRect, maxCount: Int) -> [SiblingInfo] {
        var siblings: [SiblingInfo] = []

        // Get parent
        var parentValue: CFTypeRef?
        let parentResult = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue)

        guard parentResult == .success, let parent = parentValue else {
            return siblings
        }

        // Get children of parent
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(parent as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)

        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            return siblings
        }

        // Find our element's index in the children array
        var ourIndex: Int?
        for (index, child) in children.enumerated() {
            let childFrame = getFrameAttribute(child)
            if childFrame == elementFrame {
                ourIndex = index
                break
            }
        }

        guard let currentIndex = ourIndex else { return siblings }

        // Get before siblings (up to maxCount/2)
        let beforeCount = min(maxCount / 2, currentIndex)
        for i in stride(from: currentIndex - 1, through: max(0, currentIndex - beforeCount), by: -1) {
            if siblings.count >= maxCount { break }
            let child = children[i]
            if let info = makeSiblingInfo(from: child, relativeTo: elementFrame, isBeforeInOrder: true) {
                siblings.insert(info, at: 0)
            }
        }

        // Get after siblings (up to remaining count)
        let remainingCount = maxCount - siblings.count
        for i in (currentIndex + 1)..<min(children.count, currentIndex + 1 + remainingCount) {
            if siblings.count >= maxCount { break }
            let child = children[i]
            if let info = makeSiblingInfo(from: child, relativeTo: elementFrame, isBeforeInOrder: false) {
                siblings.append(info)
            }
        }

        return siblings
    }

    /// Create SiblingInfo from an AXUIElement
    private func makeSiblingInfo(from element: AXUIElement, relativeTo refFrame: CGRect, isBeforeInOrder: Bool) -> SiblingInfo? {
        guard let role = getStringAttribute(element, kAXRoleAttribute as CFString) else {
            return nil
        }

        let identifier = getStringAttribute(element, kAXIdentifierAttribute as CFString)
        // SwiftUI controls have no title; their text is the accessibility description
        let title = ElementKind.accessibleName(
            title: getStringAttribute(element, kAXTitleAttribute as CFString),
            description: getStringAttribute(element, kAXDescriptionAttribute as CFString)
        )
        let siblingFrame = getFrameAttribute(element)

        // Determine relative position
        let position: RelativePosition
        if isBeforeInOrder {
            // Check if it's actually above (significant Y difference)
            if siblingFrame.maxY < refFrame.minY - 10 {
                position = .above
            } else {
                position = .before
            }
        } else {
            // Check if it's actually below (significant Y difference)
            if siblingFrame.minY > refFrame.maxY + 10 {
                position = .below
            } else {
                position = .after
            }
        }

        return SiblingInfo(
            role: role,
            identifier: identifier,
            title: title,
            relativePosition: position
        )
    }

    // MARK: - Window Context

    /// Get window context information for an element
    private func getWindowContext(for element: AXUIElement) -> (frame: CGRect?, title: String?, level: Int?) {
        // Walk up the hierarchy to find the window
        var current: AXUIElement? = element

        while let el = current {
            let role = getStringAttribute(el, kAXRoleAttribute as CFString)

            if role == "AXWindow" {
                let frame = getFrameAttribute(el)
                let title = getStringAttribute(el, kAXTitleAttribute as CFString)
                // Window level isn't directly available via AX, but we can try
                let level: Int? = nil  // Could be enhanced with CGWindowListCopyWindowInfo

                return (frame, title, level)
            }

            // Get parent
            var parentValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentValue)

            if result == .success, let parent = parentValue {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }

        return (nil, nil, nil)
    }

    // MARK: - All Attributes (Forensic)

    /// Get all accessibility attributes from an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: Dictionary of attribute names to string values
    public func getAllAttributes(of element: AXUIElement) -> [String: String] {
        var attributes: [String: String] = [:]

        // Get list of attribute names
        var namesCFArray: CFArray?
        let namesResult = AXUIElementCopyAttributeNames(element, &namesCFArray)

        guard namesResult == .success, let names = namesCFArray as? [String] else {
            return attributes
        }

        for name in names {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)

            if result == .success, let cfValue = value {
                attributes[name] = stringRepresentation(of: cfValue)
            }
        }

        return attributes
    }

    /// Convert a CFTypeRef to a string representation
    private func stringRepresentation(of value: CFTypeRef) -> String {
        // Handle common types
        if let stringValue = value as? String {
            return stringValue
        }

        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue(value as! CFBoolean) ? "true" : "false"
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if let array = value as? [Any] {
            return "[\(array.count) items]"
        }

        // AXValue (position, size, etc.)
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = value as! AXValue
            let type = AXValueGetType(axValue)

            switch type {
            case .cgPoint:
                var point = CGPoint.zero
                if AXValueGetValue(axValue, .cgPoint, &point) {
                    return "(\(Int(point.x)), \(Int(point.y)))"
                }
            case .cgSize:
                var size = CGSize.zero
                if AXValueGetValue(axValue, .cgSize, &size) {
                    return "\(Int(size.width))×\(Int(size.height))"
                }
            case .cgRect:
                var rect = CGRect.zero
                if AXValueGetValue(axValue, .cgRect, &rect) {
                    return "(\(Int(rect.origin.x)), \(Int(rect.origin.y)), \(Int(rect.width))×\(Int(rect.height)))"
                }
            case .cfRange:
                var range = CFRange(location: 0, length: 0)
                if AXValueGetValue(axValue, .cfRange, &range) {
                    return "range(\(range.location), \(range.length))"
                }
            default:
                break
            }
        }

        // Fallback: type description
        let typeID = CFGetTypeID(value)
        let typeName = CFCopyTypeIDDescription(typeID) as String? ?? "unknown"
        return "<\(typeName)>"
    }

    // MARK: - Region Selection

    /// Find all elements within a screen region
    /// - Parameter region: The region in AX coordinates (top-left origin)
    /// - Returns: Array of elements found within the region
    public func elementsInRegion(_ region: CGRect) -> [AXElementInfo] {
        guard targetAppElement != nil else { return [] }

        var elements: [AXElementInfo] = []
        var seenFrames = Set<String>()

        // Sample points in a grid pattern within the region
        let stepSize: CGFloat = 20  // Sample every 20 points
        var y = region.minY + stepSize / 2

        while y < region.maxY {
            var x = region.minX + stepSize / 2
            while x < region.maxX {
                if let element = elementAt(screenPosition: CGPoint(x: x, y: y)) {
                    // Use frame as a unique identifier to deduplicate
                    let frameKey = "\(element.frame.origin.x),\(element.frame.origin.y),\(element.frame.width),\(element.frame.height)"
                    if !seenFrames.contains(frameKey) {
                        seenFrames.insert(frameKey)
                        elements.append(element)
                    }
                }
                x += stepSize
            }
            y += stepSize
        }

        return elements
    }

    // MARK: - Search (read-only, used by Agent Link)

    /// Whether an app is selected for inspection
    public var hasTargetApp: Bool { targetAppElement != nil }

    /// Search the selected app's windows for elements whose name, identifier, description,
    /// help or value contains the query (case-insensitive), optionally limited to one role.
    /// Reads only; never presses or changes anything.
    /// - Parameters:
    ///   - query: Text to look for; empty matches every element (use with a role)
    ///   - role: An exact AX role such as "AXButton", or nil for any
    ///   - limit: Most matches to return
    ///   - maxVisited: Most elements to examine, so huge apps can't stall Loupe
    public func findElements(matching query: String, role: String?, limit: Int, maxVisited: Int = 4000) -> [AXElementInfo] {
        guard let appElement = targetAppElement else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var queue: [(element: AXUIElement, depth: Int)] = [(appElement, 0)]
        var visited = 0
        var matches: [AXElementInfo] = []

        while !queue.isEmpty, matches.count < limit, visited < maxVisited {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if depth > 0, let elementRole = getStringAttribute(element, kAXRoleAttribute as CFString),
               role == nil || elementRole == role {
                let haystack = [
                    kAXTitleAttribute, kAXIdentifierAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
                ].compactMap { getStringAttribute(element, $0 as CFString)?.lowercased() }
                if needle.isEmpty || haystack.contains(where: { $0.contains(needle) }),
                   let info = extractElementInfo(from: element) {
                    matches.append(info)
                }
            }

            guard depth < 40 else { continue }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        return matches
    }

    // MARK: - Window Tracking

    /// Get the frame of the target app's focused window
    public func getTargetWindowFrame() -> CGRect? {
        guard let appElement = targetAppElement else { return nil }

        // Get the focused window
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        if result != .success {
            // Try getting the first window instead
            var windowsValue: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )

            guard windowsResult == .success,
                  let windows = windowsValue as? [AXUIElement],
                  let firstWindow = windows.first else {
                return nil
            }

            return getFrameAttribute(firstWindow)
        }

        guard let window = windowValue else { return nil }
        return getFrameAttribute(window as! AXUIElement)
    }

    /// Get the title of the target app's focused window
    public func getTargetWindowTitle() -> String? {
        guard let appElement = targetAppElement else { return nil }

        // Get the focused window
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        let windowElement: AXUIElement

        if result == .success, let window = windowValue {
            windowElement = window as! AXUIElement
        } else {
            // Try getting the first window instead
            var windowsValue: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )

            guard windowsResult == .success,
                  let windows = windowsValue as? [AXUIElement],
                  let firstWindow = windows.first else {
                return nil
            }

            windowElement = firstWindow
        }

        return getStringAttribute(windowElement, kAXTitleAttribute as CFString)
    }
}
