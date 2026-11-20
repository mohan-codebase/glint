import CoreGraphics
import Foundation

enum SnapArea: CaseIterable {
    case fill, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    // All layout math uses the display's usable rectangle in AppKit coordinates.
    static func target(at point: CGPoint, on screen: CGRect, portrait: Bool) -> Self? {
        guard screen.width > 0, screen.height > 0 else { return nil }
        // Include the menu bar and Dock strips in the adjacent edge's hit area.
        let x = min(1, max(0, (point.x - screen.minX) / screen.width))
        let y = min(1, max(0, (screen.maxY - point.y) / screen.height))
        let edge: CGFloat = 0.15
        guard x <= edge || x >= 1 - edge || y <= edge || y >= 1 - edge else { return nil }

        let anchors: [(Self, CGFloat, CGFloat)] = [
            (.topLeft, 0, 0), (.topRight, 1, 0),
            (.bottomLeft, 0, 1), (.bottomRight, 1, 1),
            (portrait ? .top : .fill, 0.5, 0),
            (portrait ? .bottom : .fill, 0.5, 1),
            (portrait ? .fill : .left, 0, 0.5),
            (portrait ? .fill : .right, 1, 0.5)
        ]
        return anchors.min { a, b in
            hypot(x - a.1, y - a.2) < hypot(x - b.1, y - b.2)
        }?.0
    }

    func frame(in bounds: CGRect, gap: CGFloat = 0) -> CGRect {
        let midX = bounds.minX + floor(bounds.width / 2)
        let midY = bounds.minY + floor(bounds.height / 2)
        var x = bounds.minX, right = bounds.maxX, y = bounds.minY, top = bounds.maxY
        switch self {
        case .left, .topLeft, .bottomLeft: right = midX
        case .right, .topRight, .bottomRight: x = midX
        default: break
        }
        switch self {
        case .top, .topLeft, .topRight: y = midY
        case .bottom, .bottomLeft, .bottomRight: top = midY
        default: break
        }
        return spacedFrame(CGRect(x: x, y: y, width: right - x, height: top - y), in: bounds, gap: gap)
    }
}

private func spacedFrame(_ tile: CGRect, in bounds: CGRect, gap: CGFloat) -> CGRect {
    let spacing = min(max(0, gap.rounded()), max(0, floor((min(tile.width, tile.height) - 1) / 2)))
    let left = tile.minX == bounds.minX ? spacing : floor(spacing / 2)
    let bottom = tile.minY == bounds.minY ? spacing : floor(spacing / 2)
    let right = tile.maxX == bounds.maxX ? spacing : ceil(spacing / 2)
    let top = tile.maxY == bounds.maxY ? spacing : ceil(spacing / 2)
    return CGRect(x: tile.minX + left, y: tile.minY + bottom, width: tile.width-left-right, height: tile.height-bottom-top)
}

func accessibilityFrame(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
}

/// Where a window that refused the target size should go so it stays inside `bounds`.
/// Each axis keeps the target's edge when it fits and otherwise slides back inside,
/// so a right-hand zone ends flush with the right edge. Works in any coordinate space.
func fittedOrigin(for size: CGSize, target: CGRect, within bounds: CGRect) -> CGPoint {
    func fit(_ start: CGFloat, _ length: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        length >= high - low ? low : min(max(start, low), high - length)
    }
    return CGPoint(x: fit(target.minX, size.width, bounds.minX, bounds.maxX),
                   y: fit(target.minY, size.height, bounds.minY, bounds.maxY))
}

extension CGRect {
    /// The area a snapped window may occupy: the usable display minus the outer gap.
    func insetForGap(_ gap: CGFloat) -> CGRect {
        let inset = min(max(0, gap.rounded()), max(0, floor((min(width, height) - 1) / 2)))
        return insetBy(dx: inset, dy: inset)
    }
}

func layoutPickerFrame(size: CGSize, centerX: CGFloat, in visibleFrame: CGRect) -> CGRect {
    let margin: CGFloat = 6
    let minX = visibleFrame.minX + margin
    let maxX = visibleFrame.maxX - margin - size.width
    return CGRect(x: max(minX, min(centerX - size.width / 2, maxX)),
                  y: visibleFrame.maxY - margin - size.height,
                  width: size.width, height: size.height)
}

/// Grid coordinates share AppKit's bottom-left origin.
struct GridZone: Codable, Hashable {
    static let columns = 12, rows = 6
    let x: Int, y: Int, width: Int, height: Int

    var cells: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var isValid: Bool {
        (0..<Self.columns).contains(x) && (0..<Self.rows).contains(y) &&
        (1...(Self.columns - x)).contains(width) && (1...(Self.rows - y)).contains(height)
    }

    func frame(in bounds: CGRect) -> CGRect {
        // Interior grid lines land on whole points; the outer edges are the display's own,
        // so a zone on the edge keeps the full outer gap even when the usable area is fractional.
        func line(_ index: Int, _ count: Int, _ low: CGFloat, _ length: CGFloat) -> CGFloat {
            index == 0 ? low : index == count ? low + length : low + floor(length * CGFloat(index) / CGFloat(count))
        }
        let left = line(x, Self.columns, bounds.minX, bounds.width)
        let right = line(x + width, Self.columns, bounds.minX, bounds.width)
        let bottom = line(y, Self.rows, bounds.minY, bounds.height)
        let top = line(y + height, Self.rows, bounds.minY, bounds.height)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    func overlaps(_ other: GridZone) -> Bool { !cells.intersection(other.cells).isEmpty }

    /// Keeps zones in order, dropping any that overlap one already kept, the same rule the editor enforces.
    static func nonOverlapping(_ zones: [GridZone]) -> [GridZone] {
        zones.reduce(into: []) { kept, zone in
            if !kept.contains(where: zone.overlaps) { kept.append(zone) }
        }
    }

    func snapFrame(in bounds: CGRect, gap: CGFloat) -> CGRect {
        spacedFrame(frame(in: bounds), in: bounds, gap: gap)
    }
}

struct WindowLayout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var zones: [GridZone]

    func target(at point: CGPoint, in bounds: CGRect, gap: CGFloat) -> CGRect? {
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        let hit = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX.nextDown),
                          y: min(max(point.y, bounds.minY), bounds.maxY.nextDown))
        for zone in zones {
            let tile = zone.frame(in: bounds)
            if tile.contains(hit) { return spacedFrame(tile, in: bounds, gap: gap) }
        }
        return nil
    }
}

/// Where layouts are kept. `UserDefaults` in the app; an in-memory store in tests.
protocol LayoutStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: LayoutStore {}

/// Decodes one element without failing the surrounding array.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(Value.self) }
}

extension WindowLayout {
    private enum CodingKeys: String, CodingKey { case id, name, zones }

    // Older saves have no `id`; keep their layouts instead of rejecting the library.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Layout"
        zones = GridZone.nonOverlapping(
            try container.decode([Lossy<GridZone>].self, forKey: .zones).compactMap(\.value).filter(\.isValid))
    }
}

struct LayoutLibrary: Codable {
    var layouts: [WindowLayout]
    var selected: UUID?
    var active: WindowLayout? { layouts.first { $0.id == selected } }

    private enum CodingKeys: String, CodingKey { case layouts, selected }

    init(layouts: [WindowLayout], selected: UUID? = nil) {
        self.layouts = layouts
        self.selected = selected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var seen = Set<UUID>()
        layouts = try container.decode([Lossy<WindowLayout>].self, forKey: .layouts)
            .compactMap(\.value).filter { !$0.zones.isEmpty }
            .map { layout in
                // A repeated id would make two layouts edit and select as one; keep both apart.
                var layout = layout
                if !seen.insert(layout.id).inserted { layout.id = UUID(); seen.insert(layout.id) }
                return layout
            }
        selected = try? container.decodeIfPresent(UUID.self, forKey: .selected)
    }

    struct Loaded {
        var library: LayoutLibrary
        /// True when the saved data was unreadable or anything in it was skipped.
        var lostData: Bool
    }

    /// Reads saved layouts, keeping everything that is still usable.
    static func decode(_ data: Data?) -> Loaded {
        guard let data else { return Loaded(library: starter, lostData: false) }
        guard let saved = try? JSONDecoder().decode(Self.self, from: data) else {
            return Loaded(library: starter, lostData: true)
        }
        let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let rawLayouts = raw?["layouts"] as? [[String: Any]]
        let rawZoneCount = rawLayouts?.reduce(0) { $0 + (($1["zones"] as? [Any])?.count ?? 0) }
        let keptZoneCount = saved.layouts.reduce(0) { $0 + $1.zones.count }
        let lost = rawLayouts?.count != saved.layouts.count || rawZoneCount != keptZoneCount
        return Loaded(library: saved, lostData: lost)
    }

    static let starter = LayoutLibrary(layouts: [
        WindowLayout(name: "Three Columns", zones: [0,4,8].map { GridZone(x: $0, y: 0, width: 4, height: 6) }),
        WindowLayout(name: "Main & Sidebar", zones: [
            GridZone(x: 0, y: 0, width: 8, height: 6), GridZone(x: 8, y: 0, width: 4, height: 6)
        ])
    ])

    static let storageKey = "layoutLibrary"

    /// Loads layouts. When anything is unreadable, the original bytes are copied to a
    /// dated backup key first, so a later save can never destroy them.
    static func load(from defaults: LayoutStore = UserDefaults.standard, now: Date = Date()) -> Loaded {
        let data = defaults.data(forKey: storageKey)
        let loaded = decode(data)
        if loaded.lostData, let data {
            let stamp = ISO8601DateFormatter().string(from: now)
            defaults.set(data, forKey: "\(storageKey).backup.\(stamp)")
        }
        return loaded
    }

    func save(to defaults: LayoutStore = UserDefaults.standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// The drag-to-snap decisions, kept free of AppKit and Accessibility so they can be tested.
/// Frames are read lazily through closures because each read is an Accessibility round trip.
struct DragTracker {
    enum Decision: Equatable {
        /// Nothing to change.
        case none
        /// Show the preview for the pointer's target.
        case showPreview
        /// Hide the preview but keep tracking (Shift held, pointer outside every zone).
        case hidePreview
        /// Snap the window to the pointer's target.
        case place
        /// Stop tracking this press and hide the preview.
        case cancel
    }

    /// Frame-check interval before the window is known to be moving (60 Hz).
    static let checkInterval: TimeInterval = 1.0 / 60
    /// How far the window must move before a drag counts as moving it.
    static let moveThreshold: CGFloat = 3

    private(set) var original: CGRect?
    private(set) var moving = false
    private var nextCheck: TimeInterval?

    var isTracking: Bool { original != nil }

    mutating func reset() {
        original = nil
        moving = false
        nextCheck = nil
    }

    private func sameSize(_ frame: CGRect) -> Bool {
        guard let original else { return false }
        return abs(frame.width - original.width) <= 1 && abs(frame.height - original.height) <= 1
    }

    private func hasMoved(_ frame: CGRect) -> Bool {
        guard let original else { return false }
        return hypot(frame.minX - original.minX, frame.minY - original.minY) >= Self.moveThreshold
    }

    /// A press began over a window with this frame (nil when it is not a manageable window).
    mutating func mouseDown(windowFrame: CGRect?) {
        reset()
        original = windowFrame
    }

    /// The pointer moved with the button held (`isDrag`), or modifier keys changed during a press.
    mutating func pointerChanged(isDrag: Bool, timestamp: TimeInterval, suppressed: Bool,
                                 frame: () -> CGRect?, hasTarget: () -> Bool) -> Decision {
        guard isTracking else { return .none }
        if !moving {
            guard isDrag, timestamp >= (nextCheck ?? timestamp) else { return .none }
            nextCheck = timestamp + Self.checkInterval
            guard let current = frame() else { return .none }
            // A resize or a drag inside the document must never tile its window.
            guard sameSize(current) else {
                reset()
                return .cancel
            }
            guard hasMoved(current) else { return .none }
            moving = true
        }
        return !suppressed && hasTarget() ? .showPreview : .hidePreview
    }

    /// The button was released. Tracking always ends here.
    mutating func mouseUp(suppressed: Bool, frame: () -> CGRect?, hasTarget: () -> Bool) -> Decision {
        defer { reset() }
        guard !suppressed, isTracking, nextCheck != nil, hasTarget(), let current = frame(),
              sameSize(current), moving || hasMoved(current) else { return .cancel }
        return .place
    }
}
