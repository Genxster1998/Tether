//
//  Glass.swift
//  Tether
//
//  Tether's surface language: Liquid Glass on macOS 26, the system's
//  translucent materials on macOS 15, same shapes and spacing on both.
//  Glass is used for things that float over content (panels, round buttons,
//  status pills), never as a fill for whole screens.
//
//  The look is compact and squared-off: tight paddings, corner radii capped
//  at 5, and a distinct 1pt separator border so every panel reads as a panel
//  against the window background in both light and dark appearance.
//

import SwiftUI

enum GlassMetrics {
    /// The largest corner radius anywhere in the app.
    static let panelRadius: CGFloat = 5
    static let cardRadius: CGFloat = 5
    /// One pixel of border, visible in light and dark themes.
    static let borderWidth: CGFloat = 1
}

extension View {
    /// A floating panel: Liquid Glass, or a thick material with a hairline edge.
    @ViewBuilder
    func glassPanel(radius: CGFloat = GlassMetrics.panelRadius) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.8), lineWidth: GlassMetrics.borderWidth))
        } else {
            self
                .background(.regularMaterial, in: .rect(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: GlassMetrics.borderWidth))
        }
    }

    /// A text field's container: glass on macOS 26, a soft fill before.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
        } else {
            self
                .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.8), lineWidth: GlassMetrics.borderWidth))
        }
    }

    /// A small text button: glass on macOS 26, bordered before.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Glass over imagery (the phone card), where the material should stay clear.
    @ViewBuilder
    func clearGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// A round glass button with a symbol, and optionally a caption under it.
struct GlassCircleButton: View {
    let title: String
    let systemImage: String
    var showsTitle = true
    var size: CGFloat = 34
    var isProminent = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            button
            if showsTitle {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .help(title)
    }

    @ViewBuilder
    private var button: some View {
        let label = Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.38, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(.circle)
            .accessibilityLabel(title)

        if #available(macOS 26.0, *) {
            if isProminent {
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        } else {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.regularMaterial), in: .circle)
                .overlay(Circle().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}

/// A small rounded rect saying how a device is connected.
struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .green

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassPanel()
    }
}

/// A section heading over a glass panel.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pages

/// A device section laid out like the Overview: a scrolling column with a
/// title, then glass sections.
struct GlassPage<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.title2.weight(.bold))
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 4)
                content
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A titled glass panel, with an optional note under it.
struct GlassSection<Trailing: View, Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PanelHeader(title) { trailing }
            VStack(spacing: 0) { content }
                .glassPanel()
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

extension View {
    /// Padding for a row inside a glass panel.
    func glassRow() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Entrance

private struct StaggeredEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(MotionPreference.key) private var tetherReduceMotion = false
    @State private var isShown = false

    private var reduceMotion: Bool { systemReduceMotion || tetherReduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : -8)
            .onAppear {
                guard !isShown else { return }
                if reduceMotion {
                    isShown = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(Double(index) * 0.045)) {
                        isShown = true
                    }
                }
            }
    }
}

extension View {
    /// Fades and settles in after the ones before it, e.g. the popover's panels.
    func staggeredEntrance(_ index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }
}

enum DeviceSymbols {
    /// A battery symbol for a level, with a bolt while charging.
    static func battery(_ percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
