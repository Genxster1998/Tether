//
//  OverviewPane.swift
//  Tether
//
//  A connected device's home: who it is and how it's doing, the things you do
//  to it, then what it's playing, what it has told you lately, and the files
//  that went back and forth.
//

import SwiftUI

struct OverviewPane: View {
    @Bindable var device: DeviceViewModel
    let onSelectSection: (DeviceSection) -> Void

    var body: some View {
        ScrollView {
            details
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Header and actions

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: device.deviceType.systemImageName)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.light)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 46)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(device.name)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        StatusPill(
                            text: device.isViaTailscale ? "Tailscale" : "Wi-Fi",
                            systemImage: device.isViaTailscale ? "point.3.connected.trianglepath.dotted" : "wifi"
                        )
                        if let battery = device.batteryPercent {
                            StatusPill(text: "\(battery)%", systemImage: DeviceSymbols.battery(battery, charging: device.isCharging),
                                       tint: battery < 20 && !device.isCharging ? .red : (device.isCharging ? .green : .secondary))
                        }
                        if let network = device.networkType, !network.isEmpty {
                            StatusPill(text: network, systemImage: "cellularbars", tint: .secondary)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                GlassCircleButton(title: "Find", systemImage: "speaker.wave.3.fill") { device.findMyPhone() }
                GlassCircleButton(title: "Clipboard", systemImage: "doc.on.clipboard") { device.sendClipboard() }
                GlassCircleButton(title: "Send Files", systemImage: "arrow.up.doc") {
                    device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                }
                if device.canLock {
                    GlassCircleButton(title: "Lock", systemImage: "lock.fill") { device.lockDevice() }
                }
            }
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if device.hasNowPlaying {
                NowPlayingPanel(device: device)
            }

            if !device.notifications.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    PanelHeader("Notifications") {
                        if device.notifications.count > 3 {
                            Button("Show All") { onSelectSection(.notifications) }
                                .buttonStyle(.link)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(device.notifications.prefix(3).enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 10) }
                            NotificationPreviewRow(item: item)
                        }
                    }
                    .glassPanel()
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                PanelHeader("Files") {
                    if device.transfers.count > 3 {
                        Button("Show All") { onSelectSection(.files) }
                            .buttonStyle(.link)
                    }
                }
                Group {
                    if device.transfers.isEmpty {
                        Label("Drop files anywhere in this window to send them to \(device.name). Files it sends you are saved in Downloads.", systemImage: "arrow.down.doc")
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(device.transfers.prefix(3).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, 10) }
                                TransferRow(item: item)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                        }
                    }
                }
                .glassPanel()
            }

            RemoteInputRow()
        }
    }
}

// MARK: - Now playing

private struct NowPlayingPanel: View {
    @Bindable var device: DeviceViewModel
    @State private var draftVolume: Float = 0.5
    @State private var isEditingVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PanelHeader("Now Playing")
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.nowPlayingTitle ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 14) {
                        Button("Previous", systemImage: "backward.fill") { device.previousMedia() }
                        Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                               systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                            device.playPauseMedia()
                        }
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        Button("Next", systemImage: "forward.fill") { device.nextMedia() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                }

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $draftVolume, in: 0...1) { Text("Volume") } onEditingChanged: { editing in
                        isEditingVolume = editing
                        // Send once when the drag ends rather than on every tick.
                        if !editing { device.setVolume(draftVolume) }
                    }
                    .labelsHidden()
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(!device.canSetVolume)
                .help(device.canSetVolume ? "Media volume on \(device.name)" : "Start playing something on \(device.name) to change its volume")
            }
            .padding(10)
            .glassPanel()
        }
        .onAppear { draftVolume = device.volume }
        .onChange(of: device.volume) {
            if !isEditingVolume { draftVolume = device.volume }
        }
    }

    private var subtitle: String? {
        let parts = [device.nowPlayingArtist, device.nowPlayingAlbum].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = device.albumArt {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Notifications

private struct NotificationPreviewRow: View {
    let item: PhoneNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.appName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .fontWeight(.semibold)
                .lineLimit(1)
            if !item.text.isEmpty {
                // The message is the content, so it's not greyed out.
                Text(item.text)
                    .lineLimit(2)
            }
            if let code = item.code {
                CopyCodeButton(code: code)
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Remote input

/// Shown only while Accessibility access is missing; once granted there's nothing to say.
private struct RemoteInputRow: View {
    @State private var isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Group {
            if !isTrusted {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use your phone as a trackpad")
                            .fontWeight(.semibold)
                        Text("Tether needs Accessibility access to move the pointer and type for your phone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Allow…") { InputSynthesizer.shared.openAccessibilitySettings() }
                }
                .padding(10)
                .glassPanel()
            }
        }
        // Re-check when the window regains focus, e.g. after visiting System Settings.
        .onChange(of: controlActiveState) {
            isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
        }
    }
}

#if DEBUG
#Preview {
    OverviewPane(device: .mockConnectedPhone()) { _ in }
        .frame(width: 900, height: 760)
}
#endif
