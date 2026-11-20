import Cocoa
import QuartzCore

private final class Preview: NSPanel {
    private let tile = CALayer()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        tile.cornerRadius = 12
        let champagne = NSColor(srgbRed: 0.83, green: 0.69, blue: 0.49, alpha: 1)
        tile.backgroundColor = champagne.withAlphaComponent(0.16).cgColor
        tile.borderWidth = 2
        tile.borderColor = champagne.withAlphaComponent(0.85).cgColor
        view.layer?.addSublayer(tile)
        contentView = view
    }
    func display(tile rect: CGRect, on screen: CGRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sameDisplay = isVisible && frame == screen
        let current = tile.presentation() ?? tile
        let position = current.position, bounds = current.bounds
        let opacity = sameDisplay ? current.opacity : 0
        if frame != screen { setFrame(screen, display: false) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tile.removeAllAnimations()
        tile.frame = rect.offsetBy(dx: -screen.minX, dy: -screen.minY)
        tile.opacity = 1
        if !reduceMotion {
            if sameDisplay && opacity > 0 {
                // Start from the on-screen geometry when a drag retargets mid-flight.
                for (key, from, to) in [("position", NSValue(point: position), NSValue(point: tile.position)),
                                         ("bounds", NSValue(rect: bounds), NSValue(rect: tile.bounds))] {
                    let spring = CASpringAnimation(keyPath: key)
                    let frequency = 2 * Double.pi / 0.25
                    spring.mass = 1
                    spring.stiffness = frequency * frequency
                    spring.damping = 2 * 0.85 * frequency
                    spring.duration = spring.settlingDuration
                    spring.fromValue = from
                    spring.toValue = to
                    tile.add(spring, forKey: key)
                }
            }
            fade(from: opacity, to: 1)
        }
        CATransaction.commit()
        if !isVisible { orderFrontRegardless() }
    }

    private func fade(from: Float, to: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.09
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        tile.add(animation, forKey: "opacity")
    }

    func dismiss() {
        guard isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            orderOut(nil)
            return
        }
        let current = (tile.presentation() ?? tile).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.tile.opacity == 0 else { return }
            self.orderOut(nil)
        }
        tile.opacity = 0
        fade(from: current, to: 0)
        CATransaction.commit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SnapController {
    var layout: WindowLayout? { didSet { cancel() } }
    var gap: CGFloat = 8
    /// When true, a custom layout only snaps while Option is held (Classic Edges is unaffected).
    var layoutNeedsOption = false
    private var monitor: Any?
    private let preview = Preview()
    private var window: ManagedWindow?
    private var tracker = DragTracker()
    private var destination: CGRect?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancel()
    }

    /// Abandons the current drag, for example when the displays change under it.
    func cancel() {
        window = nil
        tracker.reset()
        show(nil)
    }

    private func show(_ frame: CGRect?, on screen: CGRect? = nil) {
        guard destination != frame else { return }
        destination = frame
        if let frame, let screen {
            preview.display(tile: frame, on: screen)
        } else {
            preview.dismiss()
        }
    }

    private func target(at pointer: CGPoint) -> (tile: CGRect, screen: CGRect, usable: CGRect)? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else {
            return nil
        }
        let bounds = screen.visibleFrame
        let tile: CGRect?
        if let layout {
            tile = layout.target(at: pointer, in: bounds, gap: gap)
        } else {
            let portrait = screen.frame.height > screen.frame.width
            tile = SnapArea.target(at: pointer, on: bounds, portrait: portrait)?.frame(in: bounds, gap: gap)
        }
        guard let tile, !tile.isEmpty else { return nil }
        return (tile, screen.frame, bounds)
    }

    private func suppressed(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.shift) || (layout != nil && layoutNeedsOption && !flags.contains(.option))
    }

    private func handle(_ event: NSEvent) {
        guard let primary = NSScreen.screens.first, let cgEvent = event.cgEvent else { cancel(); return }
        let location = cgEvent.location
        let pointer = event.type == .flagsChanged ? NSEvent.mouseLocation
            : CGPoint(x: location.x, y: primary.frame.maxY - location.y)
        let frame = { [window] in window?.frame }
        let hasTarget = { [unowned self] in self.target(at: pointer) != nil }
        switch event.type {
        case .leftMouseDown:
            cancel()
            guard let candidate = ManagedWindow.at(location), let start = candidate.frame else { return }
            window = candidate
            tracker.mouseDown(windowFrame: start)
        case .leftMouseUp:
            let decision = tracker.mouseUp(suppressed: suppressed(event.modifierFlags), frame: frame, hasTarget: hasTarget)
            let window = self.window, target = target(at: pointer)
            cancel()
            guard decision == .place, let window, let target else { return }
            CATransaction.flush()
            let top = primary.frame.maxY
            window.place(in: accessibilityFrame(target.tile, primaryTop: top),
                         within: accessibilityFrame(target.usable.insetForGap(gap), primaryTop: top))
        case .leftMouseDragged, .flagsChanged:
            switch tracker.pointerChanged(isDrag: event.type == .leftMouseDragged, timestamp: event.timestamp,
                                          suppressed: suppressed(event.modifierFlags), frame: frame, hasTarget: hasTarget) {
            case .showPreview:
                if let target = target(at: pointer) { show(target.tile, on: target.screen) }
            case .hidePreview: show(nil)
            case .cancel: cancel()
            case .none, .place: break
            }
        default: break
        }
    }
}
