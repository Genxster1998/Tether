//
//  MenuBarView.swift
//  Tether
//
//  Menu bar popover: floating glass panels, the connected phone first (wearing
//  the same picture as the phone card in the window), then menu-style rows.
//

import SwiftUI
import AppKit

public struct MenuBarView: View {
    @Bindable var appModel: TetherAppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false

    public init(appModel: TetherAppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .staggeredEntrance(0)

            if let request = appModel.incomingPairRequest {
                pairRequestCard(request)
                    .staggeredEntrance(1)
            }

            if let device = appModel.primaryDevice {
                deviceCard(device)
                    .staggeredEntrance(1)
                if device.hasNowPlaying {
                    nowPlayingCard(device)
                        .staggeredEntrance(2)
                }
            } else {
                emptyCard
                    .staggeredEntrance(1)
            }

            if !appModel.availableDevices.isEmpty {
                nearbyCard
                    .staggeredEntrance(3)
            }

            VStack(spacing: 0) {
                if let release = UpdateController.shared.availableRelease {
                    MenuRow(title: "Update to Tether \(release.version)…", systemImage: "arrow.down.circle") {
                        UpdateController.shared.showWindow()
                    }
                }
                MenuRow(title: "Open Tether", systemImage: "macwindow") { openMainWindow() }
                MenuRow(title: "Settings…", systemImage: "gearshape") {
                    openSettings()
                    NSApp.activate()
                }
                MenuRow(title: "Quit Tether", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(6)
        .frame(width: 320)
        .background(PopoverWindowCornerRadius(radius: GlassMetrics.panelRadius).frame(width: 0, height: 0))
        .dropDestination(for: URL.self) { urls, _ in
            guard let device = appModel.primaryDevice else { return false }
            let files = urls.filter(\.isFileURL)
            device.sendFiles(files)
            return !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted, let device = appModel.primaryDevice {
                RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .overlay {
                        Label("Send to \(device.name)", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 1))
                    }
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        // Just the routine announcement: a thorough one makes a connected phone reconnect.
        .onAppear { appModel.refreshDiscovery(thorough: false) }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tether")
                .font(.headline.weight(.bold))
            Spacer()
            let connected = !appModel.connectedDevices.isEmpty
            Label(connected ? "Connected" : "Not Connected", systemImage: "circle.fill")
                .labelStyle(StatusDotLabelStyle(color: connected ? .green : .secondary))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func deviceCard(_ device: DeviceViewModel) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: device.deviceType.systemImageName)
                    .font(.system(size: 20, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let battery = device.batteryPercent {
                            Label("\(battery)%", systemImage: DeviceSymbols.battery(battery, charging: device.isCharging))
                        }
                        if let network = device.networkType, !network.isEmpty {
                            Label(network, systemImage: "cellularbars")
                        }
                        if device.isViaTailscale {
                            Label("Tailscale", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if appModel.connectedDevices.count > 1 { deviceSwitcher }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                TintedActionButton(title: "Find", systemImage: "speaker.wave.3.fill") { device.findMyPhone() }
                if device.canLock {
                    TintedActionButton(title: "Lock", systemImage: "lock.fill") { device.lockDevice() }
                }
                TintedActionButton(title: "Clipboard", systemImage: "doc.on.clipboard") { device.sendClipboard() }
                TintedActionButton(title: "Send Files", systemImage: "arrow.up.doc") {
                    NSApp.activate()
                    device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                }
            }
        }
        .padding(6)
        .glassPanel()
    }

    private var deviceSwitcher: some View {
        Menu {
            Picker("Device", selection: $appModel.selectedDeviceId) {
                ForEach(appModel.connectedDevices) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Text("Switch")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.14), in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                .strokeBorder(.tint.opacity(0.35), lineWidth: 1))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Choose device")
    }

    private func nowPlayingCard(_ device: DeviceViewModel) -> some View {
        PopoverCard {
            HStack(spacing: 8) {
                Group {
                    if let image = device.albumArt {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(.rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(device.nowPlayingTitle ?? "")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(device.nowPlayingArtist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 10) {
                    Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                           systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                        device.playPauseMedia()
                    }
                    .contentTransition(.symbolEffect(.replace))
                    Button("Next", systemImage: "forward.fill") { device.nextMedia() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.body)
            }
        }
    }

    private func pairRequestCard(_ request: PairRequestViewModel) -> some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    DeviceSymbol(type: request.deviceType)
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pairing Request")
                            .font(.subheadline.weight(.semibold))
                        Text("\(request.deviceName) wants to pair")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        appModel.rejectIncomingPairRequest()
                    } label: {
                        Text("Decline").frame(maxWidth: .infinity)
                    }
                    Button {
                        appModel.acceptIncomingPairRequest(request)
                    } label: {
                        Text("Pair").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var emptyCard: some View {
        PopoverCard {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appModel.offlineDevices.isEmpty ? "No Devices" : "Not Connected")
                        .font(.subheadline.weight(.medium))
                    Text(appModel.offlineDevices.isEmpty
                         ? "Open KDE Connect on your phone to pair."
                         : "Looking for \(appModel.offlineDevices.map(\.name).formatted(.list(type: .or)))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var nearbyCard: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nearby")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(appModel.availableDevices) { device in
                    HStack(spacing: 10) {
                        DeviceSymbol(type: device.deviceType, isActive: false)
                            .frame(width: 20)
                        Text(device.name)
                            .lineLimit(1)
                        Spacer()
                        if device.isAwaitingPairing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Pair") { device.pair() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - Pieces

private struct PopoverCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
    }
}

/// A translucent, tinted, slightly raised action button for the popover.
private struct TintedActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                    .fill(isHovering ? AnyShapeStyle(tint.opacity(0.85)) : AnyShapeStyle(tint.opacity(0.14)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)
                    .strokeBorder(isHovering ? AnyShapeStyle(tint.opacity(0.9)) : AnyShapeStyle(tint.opacity(0.32)), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0.10), radius: 1.5, y: 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

/// Squashes the menu bar popover's window corners to Tether's radius; the
/// system picks its own otherwise.
private struct PopoverWindowCornerRadius: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view, radius: radius) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(to: view, radius: radius) }
    }

    private static func apply(to view: NSView, radius: CGFloat) {
        guard let frameView = view.window?.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = radius
        frameView.layer?.cornerCurve = .continuous
        frameView.layer?.masksToBounds = true
    }
}

/// A label whose icon is a small coloured status dot.
private struct StatusDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

/// A full-width row that highlights on hover, like an NSMenu item.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(isHovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#if DEBUG
#Preview("Connected") {
    MenuBarView(appModel: .mock())
}

#Preview("Pair request") {
    MenuBarView(appModel: .mockPairRequest())
}

#Preview("Empty") {
    MenuBarView(appModel: .mockEmpty())
}
#endif
