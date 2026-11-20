import CoreGraphics
import Foundation

let bounds = CGRect(x: -1000, y: 90, width: 999, height: 701)
func check(_ x: CGFloat, _ y: CGFloat, _ expected: SnapArea?, portrait: Bool = false) {
    let pointer = CGPoint(x: bounds.minX + x * bounds.width, y: bounds.maxY - y * bounds.height)
    precondition(SnapArea.target(at: pointer, on: bounds, portrait: portrait) == expected)
}
check(0.5, 0.5, nil)
check(0.16, 0.84, nil)
check(0.5, -0.02, .fill)
check(0, 0.5, .left)
check(1, 0.5, .right)
check(0, 0, .topLeft)
check(1, 0, .topRight)
check(0, 1, .bottomLeft)
check(1, 1, .bottomRight)
check(0.5, 0, .top, portrait: true)
check(0.5, 1, .bottom, portrait: true)
let quarters = [SnapArea.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.frame(in: bounds) }
precondition(quarters.reduce(CGFloat.zero) { $0 + $1.width * $1.height } == bounds.width * bounds.height)
for (index, rect) in quarters.enumerated() {
    precondition(bounds.contains(rect))
    for other in quarters.dropFirst(index + 1) {
        let overlap = rect.intersection(other)
        precondition(overlap.isEmpty)
    }
}
for rect in [bounds, CGRect(x: 800, y: 1000, width: 444, height: 333)] {
    let mapped = accessibilityFrame(rect, primaryTop: 900)
    precondition(mapped.minY == 900 - rect.maxY && mapped.minX == rect.minX)
    precondition(accessibilityFrame(mapped, primaryTop: 900) == rect)
}
print("Layout, portrait, odd-size tiling and display coordinate checks passed.")

let pickerSize = CGSize(width: 340, height: 384)
let leftPicker = layoutPickerFrame(size: pickerSize, centerX: bounds.minX, in: bounds)
let rightPicker = layoutPickerFrame(size: pickerSize, centerX: bounds.maxX, in: bounds)
precondition(leftPicker.minX == bounds.minX + 6 && rightPicker.maxX == bounds.maxX - 6)
precondition(leftPicker.maxY == bounds.maxY - 6 && bounds.contains(leftPicker) && bounds.contains(rightPicker))

for gap: CGFloat in [0, 1, 7, 8, 31, 32] {
    let left = SnapArea.left.frame(in: bounds, gap: gap)
    let right = SnapArea.right.frame(in: bounds, gap: gap)
    precondition(left.minX - bounds.minX == gap && bounds.maxX - right.maxX == gap)
    precondition(right.minX - left.maxX == gap)
    precondition(left.minY - bounds.minY == gap && bounds.maxY - left.maxY == gap)
    let upper = SnapArea.topLeft.frame(in: bounds, gap: gap)
    let lower = SnapArea.bottomLeft.frame(in: bounds, gap: gap)
    precondition(upper.minY - lower.maxY == gap && upper.width == left.width)
    precondition(SnapArea.fill.frame(in: bounds, gap: gap) == bounds.insetBy(dx: gap, dy: gap))
}
print("Window gap checks passed.")

var library = LayoutLibrary.starter
precondition(library.active == nil)
library.selected = library.layouts[0].id
let columns = library.active!
let middle = columns.target(at: CGPoint(x: bounds.midX, y: bounds.midY), in: bounds, gap: 8)!
precondition(middle.contains(CGPoint(x: bounds.midX, y: bounds.midY)) && middle.minY == bounds.minY + 8)
let side = columns.target(at: CGPoint(x: bounds.maxX, y: bounds.maxY), in: bounds, gap: 8)!
precondition(side.maxX == bounds.maxX - 8 && side.minX - middle.maxX == 8)
precondition(columns.zones[1].snapFrame(in: bounds, gap: 8) == middle)
precondition(columns.zones[2].snapFrame(in: bounds, gap: 8) == side)
let isolated = WindowLayout(name: "Center", zones: [GridZone(x: 4, y: 2, width: 4, height: 2)])
precondition(isolated.target(at: CGPoint(x: bounds.minX, y: bounds.minY), in: bounds, gap: 8) == nil)
library.layouts.append(isolated)
library.selected = isolated.id
let restored = try JSONDecoder().decode(LayoutLibrary.self, from: JSONEncoder().encode(library))
precondition(restored.active?.zones == isolated.zones && restored.active?.name == "Center")
print("Custom zones, shared gaps, empty space and saved selection checks passed.")

// Saved layouts: keep everything readable, never lose the original bytes.
let goodID = "7E6A8571-A852-4D04-A639-CD8E61419541"
let zoneJSON = #"{"x":0,"y":0,"width":6,"height":6}"#
func loaded(_ json: String) -> LayoutLibrary.Loaded { LayoutLibrary.decode(Data(json.utf8)) }

let older = loaded(#"{"layouts":[{"name":"Old","zones":[\#(zoneJSON)]}]}"#)
precondition(older.library.layouts.map(\.name) == ["Old"] && older.library.layouts[0].zones.count == 1 && !older.lostData,
             "a layout saved without an id must load")

let mixed = loaded(#"{"layouts":[{"id":"\#(goodID)","name":"Good","zones":[\#(zoneJSON)]},{"name":"Bad","zones":[{"x":11,"y":0,"width":2,"height":6}]}],"selected":"\#(goodID)"}"#)
precondition(mixed.library.layouts.map(\.name) == ["Good"] && mixed.library.active?.name == "Good" && mixed.lostData,
             "one invalid layout must not discard the others")

let partial = loaded(#"{"layouts":[{"id":"\#(goodID)","name":"Two","zones":[\#(zoneJSON),{"x":-1,"y":0,"width":1,"height":1}]}]}"#)
precondition(partial.library.layouts[0].zones.count == 1 && partial.lostData, "only the invalid zone is dropped")

let notAZone = loaded(#"{"layouts":[{"id":"\#(goodID)","name":"A","zones":[\#(zoneJSON),"junk"]},{"name":"Empty","zones":[]}]}"#)
precondition(notAZone.library.layouts.map(\.name) == ["A"] && notAZone.lostData)

for unreadable in ["not json", "{}", #"{"layouts":"nope"}"#] {
    let result = loaded(unreadable)
    precondition(result.lostData && result.library.layouts.map(\.name) == LayoutLibrary.starter.layouts.map(\.name))
}
precondition(LayoutLibrary.decode(nil).lostData == false && loaded(#"{"layouts":[]}"#).library.layouts.isEmpty)

let roundTrip = try JSONDecoder().decode(LayoutLibrary.self, from: JSONEncoder().encode(mixed.library))
precondition(roundTrip.layouts.map(\.id) == mixed.library.layouts.map(\.id) && roundTrip.selected == mixed.library.selected)

// load() copies unreadable data to a backup key before anything can overwrite it.
final class MemoryStore: LayoutStore {
    var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
let testDefaults = MemoryStore()
let unreadable = Data("not json".utf8)
testDefaults.set(unreadable, forKey: LayoutLibrary.storageKey)
let stamp = Date(timeIntervalSince1970: 0)
let fromDisk = LayoutLibrary.load(from: testDefaults, now: stamp)
precondition(fromDisk.lostData)
precondition(testDefaults.data(forKey: "layoutLibrary.backup.1970-01-01T00:00:00Z") == unreadable, "backup must hold the original bytes")
fromDisk.library.save(to: testDefaults)
precondition(testDefaults.data(forKey: "layoutLibrary.backup.1970-01-01T00:00:00Z") == unreadable, "saving must not touch the backup")
precondition(!LayoutLibrary.load(from: testDefaults).lostData, "data Glint saved itself reads back cleanly")
precondition(testDefaults.values.count == 2, "exactly one backup is written")
print("Saved layout migration, partial recovery and backup checks passed.")

// A window that keeps a larger minimum size must stay on the display.
let usable = CGRect(x: 0, y: 34, width: 1710, height: 1073).insetForGap(8)   // AX coordinates
precondition(usable == CGRect(x: 8, y: 42, width: 1694, height: 1057))
let big = CGSize(width: 1000, height: 832)
let topRight = CGRect(x: 859, y: 42, width: 843, height: 525)
let moved = CGRect(origin: fittedOrigin(for: big, target: topRight, within: usable), size: big)
precondition(usable.contains(moved) && moved.maxX == usable.maxX && moved.minY == topRight.minY,
             "a right-hand zone ends flush with the right edge")
let leftHalf = CGRect(x: 8, y: 42, width: 843, height: 1057)
precondition(fittedOrigin(for: CGSize(width: 1000, height: 1057), target: leftHalf, within: usable) == leftHalf.origin)
let bottomRight = CGRect(x: 859, y: 575, width: 843, height: 524)
let lifted = CGRect(origin: fittedOrigin(for: big, target: bottomRight, within: usable), size: big)
precondition(usable.contains(lifted) && lifted.maxY == usable.maxY && lifted.maxX == usable.maxX)
let tooWide = fittedOrigin(for: CGSize(width: 2000, height: 300), target: topRight, within: usable)
precondition(tooWide.x == usable.minX && tooWide.y == topRight.minY, "a window wider than the display starts at its left edge")
precondition(CGRect(x: 0, y: 0, width: 3, height: 3).insetForGap(32) == CGRect(x: 1, y: 1, width: 1, height: 1))
print("Minimum-size placement checks passed.")
