import Cocoa
import ApplicationServices

enum Placement: Equatable {
    /// The window now has exactly the requested frame.
    case exact
    /// The app kept a larger minimum size; the window was moved to stay on the display.
    case adjusted
    /// The window could not be moved, closed, or its app did not answer in time.
    case failed

    var succeeded: Bool { self != .failed }
}

struct ManagedWindow {
    let element: AXUIElement

    /// Longest Glint waits for another app to answer one Accessibility request.
    /// The system default is about 6 s, which freezes Glint while that app is hung.
    static let messagingTimeout: Float = 0.25

    /// Applies `messagingTimeout` to every Accessibility element this process uses.
    static func configureTimeouts() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        copy(element, name).value
    }

    private static func copy(_ element: AXUIElement, _ name: String) -> (value: CFTypeRef?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (error == .success ? value : nil, error)
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return application
    }

    static func at(_ point: CGPoint) -> Self? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, messagingTimeout)
        let window: AXUIElement
        if attribute(hit, kAXRoleAttribute) as? String == kAXWindowRole {
            window = hit
        } else {
            guard let value = attribute(hit, kAXWindowAttribute),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            window = value as! AXUIElement
        }
        return manageable(window)
    }

    static func focused(in app: NSRunningApplication) -> Self? {
        guard !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = application(app.processIdentifier)
        let focused = copy(application, kAXFocusedWindowAttribute)
        // An app that timed out once will time out again; skip the fallback request.
        guard focused.error != .cannotComplete,
              let value = focused.value ?? attribute(application, kAXMainWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return manageable(value as! AXUIElement)
    }

    private static func manageable(_ window: AXUIElement) -> Self? {
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        guard attribute(window, "AXFullScreen") as? Bool != true,
              attribute(window, kAXMinimizedAttribute) as? Bool != true else { return nil }
        var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable) == .success,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success,
              movable.boolValue, resizable.boolValue else { return nil }
        return Self(element: window)
    }

    var frame: CGRect? {
        let attributes = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let pair = values as? [AnyObject], pair.count == 2 else { return nil }
        let position = pair[0], dimensions = pair[1]
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(dimensions as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func set(_ attribute: String, _ value: AXValue) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private func setPosition(_ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return set(kAXPositionAttribute, value)
    }

    /// Moves and resizes the window to `rect`, both in Accessibility (top-left origin)
    /// coordinates. If the app refuses that size, the window is moved so it stays inside
    /// `bounds` instead of hanging off the display.
    @discardableResult
    func place(in rect: CGRect, within bounds: CGRect) -> Placement {
        var size = rect.size
        guard let dimensions = AXValueCreate(.cgSize, &size) else { return .failed }
        // Some apps animate each AX write when enhanced UI is active. Scope the
        // override to this placement and restore only a value we actually changed.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return .failed }
        let app = Self.application(pid)
        let enhanced = "AXEnhancedUserInterface"
        let current = Self.copy(app, enhanced)
        guard current.error != .cannotComplete else { return .failed }
        let restore = current.value as? Bool == true &&
            AXUIElementSetAttributeValue(app, enhanced as CFString, kCFBooleanFalse) == .success
        defer {
            if restore { AXUIElementSetAttributeValue(app, enhanced as CFString, kCFBooleanTrue) }
        }
        // A timed-out or invalid window will not answer the remaining writes either;
        // stop instead of waiting once per write.
        var positioned = setPosition(rect.origin)
        guard positioned != .cannotComplete, positioned != .invalidUIElement else { return .failed }
        var resized = set(kAXSizeAttribute, dimensions)
        guard resized != .cannotComplete, resized != .invalidUIElement,
              var actual = frame else { return positioned == .success && resized == .success ? .exact : .failed }
        if actual.size != size {
            resized = set(kAXSizeAttribute, dimensions)
            actual = frame ?? actual
        }
        // Retrying the size can move a window when the app constrains it to the display,
        // and a window that kept a larger minimum size must slide back onto the display.
        let origin = actual.size == size ? rect.origin
            : fittedOrigin(for: actual.size, target: rect, within: bounds)
        if actual.origin != origin {
            positioned = setPosition(origin)
        }
        guard positioned == .success, resized == .success else { return .failed }
        return actual.size == size ? .exact : .adjusted
    }
}
