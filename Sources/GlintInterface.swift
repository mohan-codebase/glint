import SwiftUI

private func glintAccent(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(red: 0.85, green: 0.72, blue: 0.54)
                         : Color(red: 0.48, green: 0.32, blue: 0.17)
}

func glintSurface(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(red: 0.14, green: 0.13, blue: 0.12)
                         : Color(red: 0.98, green: 0.96, blue: 0.93)
}

struct GlintSettingsView: View {
    @ObservedObject var model: AppDelegate
    @Environment(\.colorScheme) private var colorScheme

    private static let githubProfile = URL(string: "https://github.com/mohan-codebase")!
    private static let githubMark = Bundle.main.url(forResource: "GitHubMark", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }

    private var accent: Color { glintAccent(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glint")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(accent)
                        .accessibilityAddTraits(.isHeader)
                    Text("Window settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 11) {
                    symbol("rectangle.and.hand.point.up.left")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drag to snap").fontWeight(.medium)
                        Text(model.layoutNeedsOption && model.library.active != nil
                             ? "Hold Option to snap to your layout. Shift skips snapping."
                             : "Hold Shift to skip snapping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Drag to snap", isOn: $model.dragToSnap)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(accent)
                }
                .padding(14)

                Divider().padding(.leading, 51)

                HStack(spacing: 11) {
                    symbol("arrow.left.and.right")
                    VStack(spacing: 7) {
                        HStack {
                            Text("Window gap").fontWeight(.medium)
                            Spacer()
                            Text("\(Int(model.gap)) pt")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                        Slider(value: $model.gap, in: 0...32, step: 1) { Text("Window gap") }
                            .labelsHidden()
                            .controlSize(.small)
                            .tint(accent)
                            .accessibilityValue("\(Int(model.gap)) points")
                    }
                }
                .padding(14)

                Divider().padding(.leading, 51)

                HStack(alignment: .top, spacing: 11) {
                    symbol("rectangle.split.2x2")
                    DragLayoutSettings(library: model.library, accent: accent,
                                       partlyUnreadable: model.layoutsPartlyUnreadable,
                                       needsOption: $model.layoutNeedsOption, select: model.selectLayout,
                                       add: model.newLayout, edit: model.editLayout, delete: model.deleteLayout)
                }
                .padding(14)

                Divider().padding(.leading, 51)

                HStack(alignment: .top, spacing: 11) {
                    symbol("power")
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Start at login").fontWeight(.medium)
                                .accessibilityHidden(true)
                            Spacer()
                            Toggle("Start at login", isOn: Binding(get: { model.startsAtLogin },
                                                                  set: { model.setStartsAtLogin($0) }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                                .tint(accent)
                        }
                        .frame(minHeight: 26)

                        if model.needsLoginItemApproval {
                            Text("Approve Glint in Login Items to start it automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Login Items…", action: model.openLoginItemSettings)
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
            }
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(.primary.opacity(0.09))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Label(model.trusted ? "Accessibility enabled" : "Accessibility required",
                          systemImage: model.trusted ? "checkmark.circle" : "lock")
                        .font(.caption)
                        .foregroundStyle(model.trusted ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                    if !model.trusted {
                        Button("Allow Access…", action: model.authorize)
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Quit Glint") { NSApp.terminate(nil) }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut("q", modifiers: .command)
                }

                HStack(spacing: 5) {
                    Text("Made")
                        .foregroundStyle(.secondary)
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("by Mohan")
                        .foregroundStyle(.secondary)
                    Link(destination: Self.githubProfile) {
                        if let mark = Self.githubMark {
                            Image(nsImage: mark)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        } else {
                            Text("GitHub")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Mohan’s GitHub profile")
                    .help("Open Mohan’s GitHub profile")
                }
                .font(.caption)
            }
        }
        .padding(22)
        .frame(width: 468)
        .background(glintSurface(for: colorScheme))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: 26, height: 26)
            .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

private struct DragLayoutSettings: View {
    var library: LayoutLibrary
    var accent: Color
    var partlyUnreadable: Bool
    @Binding var needsOption: Bool
    var select: (UUID?) -> Void
    var add: () -> Void
    var edit: () -> Void
    var delete: () -> Void
    @State private var showingLayouts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Drag layout").fontWeight(.medium)
                Spacer()
                Button(action: add) {
                    Label("New layout", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("New layout")

                Menu {
                    Button("Edit Layout…", action: edit)
                    Button("Delete Layout…", role: .destructive, action: delete)
                } label: {
                    Label("Manage layout", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 25, height: 25)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(library.active == nil)
                .help("Manage selected layout")
            }
            .frame(minHeight: 26)

            Button {
                showingLayouts.toggle()
            } label: {
                layoutRow(library.active, indicator: "chevron.down")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(.primary.opacity(0.09))
                            .allowsHitTesting(false)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose drag layout")
            .accessibilityValue(library.active?.name ?? "Classic Edges")
            .popover(isPresented: $showingLayouts, arrowEdge: .bottom) {
                ScrollView {
                    VStack(spacing: 2) {
                        layoutOption(nil)
                        ForEach(library.layouts) { layout in
                            layoutOption(layout)
                        }
                    }
                    .padding(6)
                }
                .frame(width: 258, height: min(264, CGFloat(library.layouts.count + 1) * 42 + 12))
            }

            Toggle(isOn: $needsOption) {
                Text("Snap to custom layouts only while holding ⌥ Option")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(library.active == nil)
            .help(library.active == nil ? "Choose a custom layout to use this." :
                  "When on, dragging a window moves it freely unless you hold Option.")

            if partlyUnreadable {
                Text("Some saved layouts couldn’t be read and were skipped. The original data is kept as a backup in Glint’s preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func layoutOption(_ layout: WindowLayout?) -> some View {
        let isSelected = library.active?.id == layout?.id
        return Button {
            select(layout?.id)
            showingLayouts = false
        } label: {
            layoutRow(layout, indicator: isSelected ? "checkmark" : nil)
                .padding(.horizontal, 7)
                .frame(height: 40)
                .background(isSelected ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func layoutRow(_ layout: WindowLayout?, indicator: String?) -> some View {
        HStack(spacing: 9) {
            LayoutSwatch(zones: layout?.zones, accent: accent)
            Text(layout?.name ?? "Classic Edges")
                .lineLimit(1)
            Spacer(minLength: 3)
            if let indicator {
                Image(systemName: indicator)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(indicator == "checkmark" ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct LayoutSwatch: View {
    var zones: [GridZone]?
    var accent: Color

    private var regions: [PickerRegion] {
        if let zones { return zones.map(PickerRegion.custom) }
        return [SnapArea.topLeft, .topRight, .bottomLeft, .bottomRight].map(PickerRegion.standard)
    }

    var body: some View {
        let bounds = CGRect(x: 0, y: 0, width: 36, height: 24)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.10))
            ForEach(regions, id: \.self) { region in
                let rect = region.frame(in: bounds, gap: 2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent.opacity(0.48))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: bounds.height - rect.midY)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .accessibilityHidden(true)
    }
}

enum PickerRegion: Hashable {
    case standard(SnapArea)
    case custom(GridZone)

    func frame(in bounds: CGRect, gap: CGFloat) -> CGRect {
        switch self {
        case let .standard(area): return area.frame(in: bounds, gap: gap)
        case let .custom(zone): return zone.snapFrame(in: bounds, gap: gap)
        }
    }

    var label: String {
        switch self {
        case .standard(.fill): return "Fill display"
        case .standard(.left): return "Left half"
        case .standard(.right): return "Right half"
        case .standard(.top): return "Top half"
        case .standard(.bottom): return "Bottom half"
        case .standard(.topLeft): return "Top-left quarter"
        case .standard(.topRight): return "Top-right quarter"
        case .standard(.bottomLeft): return "Bottom-left quarter"
        case .standard(.bottomRight): return "Bottom-right quarter"
        case .custom: return "Layout zone"
        }
    }
}

struct LayoutPickerView: View {
    var trusted: Bool
    var targetName: String?
    var activeLayout: WindowLayout?
    var snap: (PickerRegion) -> Bool
    var settings: () -> Void
    var authorize: () -> Void
    @State private var placementFailed = false
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { glintAccent(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snap window")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(placementFailed ? "This window can’t be moved." :
                        targetName ?? (trusted ? "Focus a resizable window first." : "Allow Accessibility to move windows."))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 10)
                Button(action: settings) {
                    Label("Glint Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PickerButtonStyle(accent: accent, cornerRadius: 7))
                .help("Glint Settings")
                .accessibilityLabel("Glint Settings")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    diagram("Fill", [.fill])
                    diagram("Columns", [.left, .right])
                }
                GridRow {
                    diagram("Rows", [.top, .bottom])
                    diagram("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight])
                }
            }
            .disabled(targetName == nil)

            if let activeLayout {
                LayoutDiagram(title: activeLayout.name, regions: activeLayout.zones.map(PickerRegion.custom),
                              height: 96, accent: accent, action: choose)
                    .disabled(targetName == nil)
            }

            if !trusted {
                Button("Allow Access…", action: authorize)
                    .tint(accent)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(glintSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(accent.opacity(0.23))
                .allowsHitTesting(false)
        }
    }

    private func diagram(_ title: String, _ regions: [SnapArea]) -> some View {
        LayoutDiagram(title: title, regions: regions.map(PickerRegion.standard), height: 72, accent: accent, action: choose)
    }

    private func choose(_ region: PickerRegion) { placementFailed = !snap(region) }
}

private struct LayoutDiagram: View {
    var title: String
    var regions: [PickerRegion]
    var height: CGFloat
    var accent: Color
    var action: (PickerRegion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                let bounds = CGRect(origin: .zero, size: geometry.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.075))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.13))
                        }
                        .accessibilityHidden(true)
                    ForEach(regions, id: \.self) { region in
                        let frame = region.frame(in: bounds, gap: 4)
                        let label = regionLabel(region)
                        Button { action(region) } label: {
                            Color.clear
                                .contentShape(Rectangle())
                                .overlay {
                                    if regions.count == 1 {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .foregroundStyle(accent)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                        .buttonStyle(PickerButtonStyle(accent: accent, cornerRadius: 5))
                        .accessibilityLabel(label)
                        .help(label)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: bounds.height - frame.midY)
                    }
                }
            }
            .frame(height: height)
            Text(title).font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func regionLabel(_ region: PickerRegion) -> String {
        guard case .custom = region, let index = regions.firstIndex(of: region) else { return region.label }
        return "\(title), zone \(index + 1)"
    }
}

private struct PickerButtonStyle: ButtonStyle {
    var accent: Color
    var cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        PickerButton(configuration: configuration, accent: accent, cornerRadius: cornerRadius)
    }

    private struct PickerButton: View {
        var configuration: Configuration
        var accent: Color
        var cornerRadius: CGFloat
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let highlighted = enabled && (hovered || configuration.isPressed)
            let outline = RoundedRectangle(cornerRadius: cornerRadius)
            configuration.label
                .background {
                    outline.fill(accent.opacity(highlighted ? (configuration.isPressed ? 0.42 : 0.31) : 0.16))
                }
                .overlay {
                    outline.strokeBorder(accent.opacity(highlighted ? 0.67 : 0.21))
                        .allowsHitTesting(false)
                }
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}
