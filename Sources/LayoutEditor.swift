import Cocoa

/// The 12 × 6 grid where zones are drawn. Works with the mouse, the keyboard
/// (arrows move a cell cursor, Shift-arrows extend a selection, Return adds or selects,
/// Delete removes, Escape clears) and VoiceOver (each zone is its own element).
private final class ZoneCanvas: NSView {
    var zones: [GridZone] = [] { didSet { NSAccessibility.post(element: self, notification: .layoutChanged) } }
    var selection: Int? { didSet { needsDisplay = true; onChange?() } }
    var onChange: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    private var anchor: (Int, Int)?
    private var draft: GridZone?
    private var replacing: Int?
    /// Keyboard cursor cell and, while Shift-extending, the cell the selection started from.
    private var cursor = (x: 0, y: GridZone.rows - 1)
    private var keyboardAnchor: (x: Int, y: Int)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; keyboardAnchor = nil; draft = nil; return true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for col in 0...GridZone.columns {
            let x = bounds.width * CGFloat(col) / CGFloat(GridZone.columns)
            grid.move(to: CGPoint(x: x, y: 0))
            grid.line(to: CGPoint(x: x, y: bounds.height))
        }
        for row in 0...GridZone.rows {
            let y = bounds.height * CGFloat(row) / CGFloat(GridZone.rows)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.line(to: CGPoint(x: bounds.width, y: y))
        }
        grid.stroke()
        for (i, zone) in zones.enumerated() where draft == nil || replacing != i {
            paint(zone, color: i == selection ? .controlAccentColor : .systemBrown)
        }
        if let draft { paint(draft, color: accepts(draft) ? .controlAccentColor : .systemRed) }
        if window?.firstResponder === self {
            let ring = NSBezierPath(rect: cellZone(cursor.x, cursor.y).frame(in: bounds).insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 3
            NSColor.keyboardFocusIndicatorColor.setStroke()
            ring.stroke()
        }
    }

    private func paint(_ zone: GridZone, color: NSColor) {
        let path = NSBezierPath(roundedRect: zone.frame(in: bounds).insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        color.withAlphaComponent(0.23).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func cellZone(_ x: Int, _ y: Int) -> GridZone { GridZone(x: x, y: y, width: 1, height: 1) }

    private func cell(_ event: NSEvent) -> (Int, Int) {
        let point = convert(event.locationInWindow, from: nil)
        return (min(GridZone.columns - 1, max(0, Int(point.x / bounds.width * CGFloat(GridZone.columns)))),
                min(GridZone.rows - 1, max(0, Int(point.y / bounds.height * CGFloat(GridZone.rows)))))
    }

    private func zoneIndex(at x: Int, _ y: Int) -> Int? {
        zones.firstIndex { $0.cells.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }
    }

    private func accepts(_ zone: GridZone) -> Bool {
        zones.enumerated().allSatisfy { i, existing in i == replacing || !existing.overlaps(zone) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let (x, y) = cell(event)
        anchor = (x,y)
        keyboardAnchor = nil
        cursor = (x, y)
        draft = nil
        replacing = zoneIndex(at: x, y)
        selection = replacing
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (a,b) = anchor else { return }
        let (x,y) = cell(event)
        cursor = (x, y)
        draft = GridZone(x: min(a,x), y: min(b,y), width: abs(x-a)+1, height: abs(y-b)+1)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let (x,y) = anchor else { return }
        if draft != nil { mouseDragged(with: event) }
        if let zone = draft ?? (replacing == nil ? GridZone(x: x, y: y, width: 1, height: 1) : nil) {
            commit(zone)
        }
        anchor = nil
        draft = nil
        replacing = nil
        needsDisplay = true
        onChange?()
    }

    /// Adds `zone`, or replaces the zone being redrawn; beeps and announces when it would overlap.
    private func commit(_ zone: GridZone) {
        guard accepts(zone) else {
            NSSound.beep()
            announce("That zone overlaps another zone.")
            return
        }
        if let replacing {
            zones[replacing] = zone
            announce("Zone \(replacing + 1) redrawn: \(Self.describe(zone)).")
        } else {
            zones.append(zone)
            selection = zones.count - 1
            announce("Zone \(zones.count) added: \(Self.describe(zone)).")
        }
    }

    func removeSelected() {
        guard let selection, zones.indices.contains(selection) else { return }
        anchor = nil
        draft = nil
        replacing = nil
        zones.remove(at: selection)
        self.selection = nil
        announce("Zone \(selection + 1) removed.")
    }

    // MARK: Keyboard

    // The window's default button ("Save Layout") also answers Return; while the grid has
    // focus, Return belongs to the grid. Cmd-Return still saves.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, [36, 76].contains(event.keyCode) else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            onCommandReturn?()
        } else if flags.isDisjoint(with: [.option, .control]) {
            activateCursor()
        } else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: moveCursor(dx: -1, dy: 0, extend: extend)   // ←
        case 124: moveCursor(dx: 1, dy: 0, extend: extend)    // →
        case 125: moveCursor(dx: 0, dy: -1, extend: extend)   // ↓ (grid rows count up from the bottom)
        case 126: moveCursor(dx: 0, dy: 1, extend: extend)    // ↑
        case 36, 76, 49: activateCursor()                     // Return, Enter, Space
        case 51, 117: removeSelected()                        // Delete, Forward Delete
        case 53:                                              // Escape
            if keyboardAnchor != nil || draft != nil {
                keyboardAnchor = nil
                draft = nil
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        default: super.keyDown(with: event)
        }
    }

    private func moveCursor(dx: Int, dy: Int, extend: Bool) {
        if extend, keyboardAnchor == nil { keyboardAnchor = cursor }
        if !extend { keyboardAnchor = nil; draft = nil }
        cursor = (min(GridZone.columns - 1, max(0, cursor.x + dx)), min(GridZone.rows - 1, max(0, cursor.y + dy)))
        if let a = keyboardAnchor {
            draft = GridZone(x: min(a.x, cursor.x), y: min(a.y, cursor.y),
                             width: abs(cursor.x - a.x) + 1, height: abs(cursor.y - a.y) + 1)
        } else if let index = zoneIndex(at: cursor.x, cursor.y) {
            selection = index
        } else if selection != nil {
            selection = nil
        }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    /// Return: add the Shift-extended selection, select the zone under the cursor, or add a one-cell zone.
    private func activateCursor() {
        replacing = nil
        if let draft {
            commit(draft)
        } else if let index = zoneIndex(at: cursor.x, cursor.y) {
            selection = index
            announce("Zone \(index + 1) selected: \(Self.describe(zones[index])). Press Delete to remove it.")
        } else {
            commit(cellZone(cursor.x, cursor.y))
        }
        keyboardAnchor = nil
        draft = nil
        needsDisplay = true
        onChange?()
    }

    // MARK: Accessibility

    /// "columns 1–4, rows 1–6 from the top" — rows are counted from the top as people read them.
    static func describe(_ zone: GridZone) -> String {
        let firstRow = GridZone.rows - (zone.y + zone.height) + 1, lastRow = GridZone.rows - zone.y
        let columns = zone.width == 1 ? "column \(zone.x + 1)" : "columns \(zone.x + 1)–\(zone.x + zone.width)"
        let rows = zone.height == 1 ? "row \(firstRow)" : "rows \(firstRow)–\(lastRow)"
        return "\(columns), \(rows) from the top"
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp.mainWindow ?? self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .layoutArea }
    override func accessibilityLabel() -> String? { "Zone grid, \(GridZone.columns) columns by \(GridZone.rows) rows" }
    override func accessibilityHelp() -> String? {
        "Use the arrow keys to move. Hold Shift with the arrows to stretch a zone, then press Return to add it. "
            + "Press Return on a zone to select it, and Delete to remove the selected zone."
    }
    override func accessibilityValue() -> Any? {
        let row = GridZone.rows - cursor.y
        let base = "\(zones.count) zone\(zones.count == 1 ? "" : "s"). Cursor at column \(cursor.x + 1), row \(row) from the top"
        if let draft { return base + ". Selecting \(Self.describe(draft))" }
        if let index = zoneIndex(at: cursor.x, cursor.y) { return base + ", inside zone \(index + 1)" }
        return base
    }

    override func accessibilityChildren() -> [Any]? {
        zones.enumerated().map { index, zone in
            let element = NSAccessibilityElement.element(
                withRole: .layoutItem,
                frame: NSAccessibility.screenRect(fromView: self, rect: zone.frame(in: bounds)),
                label: "Zone \(index + 1), \(Self.describe(zone))\(index == selection ? ", selected" : "")",
                parent: self)
            return element
        }
    }
}

@MainActor
final class LayoutEditor: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let canvas = ZoneCanvas()
    private let nameField = NSTextField()
    private let saveButton = NSButton()
    private let removeButton = NSButton()
    private let layout: WindowLayout
    private let onSave: (WindowLayout) -> Void
    private let onClose: (UUID) -> Void

    /// The layout this window edits; each layout gets at most one editor.
    var layoutID: UUID { layout.id }

    init(layout: WindowLayout, isNew: Bool, onSave: @escaping (WindowLayout) -> Void,
         onClose: @escaping (UUID) -> Void = { _ in }) {
        self.layout = layout
        self.onSave = onSave
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 540,height: 405), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = isNew ? "New Layout" : "Edit Layout"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.autorecalculatesKeyViewLoop = true
        guard let content = window.contentView else { return }
        nameField.stringValue = layout.name
        nameField.placeholderString = "Layout name"
        nameField.setAccessibilityLabel("Layout name")
        nameField.frame = NSRect(x: 20,y: 351,width: 500,height: 28)
        nameField.delegate = self
        content.addSubview(nameField)
        let hint = NSTextField(wrappingLabelWithString: "Drag across cells to draw a zone. Drag from inside a zone to redraw it. "
            + "Keyboard: arrows move, Shift-arrows stretch, Return adds, Delete removes.")
        hint.frame = NSRect(x: 20,y: 309,width: 500,height: 34)
        content.addSubview(hint)
        canvas.frame = NSRect(x: 20,y: 77,width: 500,height: 230)
        canvas.zones = layout.zones
        canvas.onChange = { [weak self] in self?.validate() }
        content.addSubview(canvas)
        removeButton.title = "Remove Zone"
        removeButton.action = #selector(removeZone)
        saveButton.title = "Save Layout"
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        saveButton.setAccessibilityHelp("Return saves from the name field; Command-Return saves from the zone grid.")
        canvas.onCommandReturn = { [weak self] in self?.save() }
        for button in [removeButton, saveButton] {
            button.bezelStyle = .rounded
            button.target = self
            content.addSubview(button)
        }
        removeButton.frame = NSRect(x: 16,y: 21,width: 130,height: 34)
        saveButton.frame = NSRect(x: 388,y: 21,width: 136,height: 34)
        validate()
    }

    required init?(coder: NSCoder) { fatalError("Use init(layout:isNew:onSave:onClose:)") }
    func controlTextDidChange(_ obj: Notification) { validate() }
    func windowWillClose(_ notification: Notification) { onClose(layout.id) }
    private func validate() {
        removeButton.isEnabled = canvas.selection != nil
        saveButton.isEnabled = !canvas.zones.isEmpty && !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    @objc private func removeZone() { canvas.removeSelected() }
    @objc private func save() {
        var result = layout
        result.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        result.zones = canvas.zones
        guard !result.name.isEmpty, !result.zones.isEmpty else { return }
        onSave(result)
        close()
    }
}
