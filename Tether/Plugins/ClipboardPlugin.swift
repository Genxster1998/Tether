//
//  ClipboardPlugin.swift
//  Tether
//

import AppKit
import Foundation

public final class ClipboardPlugin: TetherPlugin, @unchecked Sendable {
    public static let clipboardFileType = "kdeconnect.clipboard.file"

    /// Cap for image sync in either direction, matching the Android fork and
    /// upstream KDE's default `maxClipboardFileSizeMB`.
    nonisolated public static let maximumImagePayloadSize: Int64 = 50 * 1_048_576

    public let supportedPacketTypes = [
        "kdeconnect.clipboard",
        "kdeconnect.clipboard.connect",
        ClipboardPlugin.clipboardFileType
    ]

    private var lastChangeCount: Int = 0
    private var lastReceivedContent: String = ""
    private var lastSentContent: String = ""
    private var lastLocalClipboardTimestamp: Int64 = 0
    private var lastReceivedImageData: Data?
    private var lastSentImageData: Data?
    private var timer: Timer?
    private var activeConnections: [DeviceConnection] = []
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "com.subhashh.tether.clipboard.send", qos: .userInitiated)

    public init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        if let initial = NSPasteboard.general.string(forType: .string), !initial.isEmpty {
            self.lastSentContent = initial
        }
        startMonitoring()
    }

    private func startMonitoring() {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkPasteboard()
            }
        }
    }

    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Image path: a Finder file copy puts a TIFF icon alongside the file
        // URL; sync only genuine image copies, and let them take priority over
        // any text on the same pasteboard.
        if Self.isImageCopy(types: NSPasteboard.general.types ?? []),
           let png = NSPasteboard.general.data(forType: .png)
               ?? NSPasteboard.general.data(forType: .tiff).flatMap(Self.tiffToPng) {
            if Int64(png.count) > Self.maximumImagePayloadSize {
                TetherLog("[ClipboardPlugin] Clipboard image is \(png.count) bytes, over the \(Self.maximumImagePayloadSize) byte cap; not syncing")
            } else if Self.shouldBroadcastImage(png, lastReceivedImageData: lastReceivedImageData, lastSentImageData: lastSentImageData) {
                lastSentImageData = png
                lastLocalClipboardTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
                let filename = "\(lastLocalClipboardTimestamp).png"
                TetherLog("[ClipboardPlugin] Local clipboard image changed (\(png.count) bytes); broadcasting to paired devices")
                sendQueue.async { [weak self] in
                    self?.broadcastImage(data: png, filename: filename)
                }
                return
            }
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }

        // Suppress echo if this content originated from remote device or was already sent
        if text == lastReceivedContent || text == lastSentContent {
            return
        }

        lastSentContent = text
        lastLocalClipboardTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        TetherLog("[ClipboardPlugin] Local clipboard changed: \(text.prefix(30))... Broadcasting to paired devices")
        broadcastClipboard(content: text)
    }

    public func onConnected(connection: DeviceConnection) {
        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isClipboardSyncEnabled else {
            return
        }

        lock.withLock {
            activeConnections.removeAll { $0.peerDeviceInfo?.deviceId == deviceId }
            activeConnections.append(connection)
        }
    }

    public func onDisconnected(connection: DeviceConnection) {
        lock.withLock {
            activeConnections.removeAll { $0 === connection }
        }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        // An image announcement carries nothing to apply at packet time; the
        // bytes arrive separately via handlePayload.
        guard packet.type != Self.clipboardFileType else { return }
        guard packet.type == "kdeconnect.clipboard" || packet.type == "kdeconnect.clipboard.connect" else { return }

        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isClipboardSyncEnabled else {
            return
        }

        guard let content = packet.string(for: "content") else { return }

        // If it's a connect packet, verify timestamp to prevent overwriting with stale content
        if packet.type == "kdeconnect.clipboard.connect" {
            let packetTime = packet.int64(for: "timestamp", default: 0)
            if packetTime > 0 && packetTime < lastLocalClipboardTimestamp {
                TetherLog("[ClipboardPlugin] Ignoring connect packet with older timestamp: \(packetTime) vs \(lastLocalClipboardTimestamp)")
                return
            }
        }

        guard content != lastReceivedContent && content != lastSentContent else { return }

        lastReceivedContent = content
        lastSentContent = content
        if packet.type == "kdeconnect.clipboard.connect" {
            let packetTime = packet.int64(for: "timestamp", default: 0)
            if packetTime > 0 {
                lastLocalClipboardTimestamp = packetTime
            }
        } else {
            lastLocalClipboardTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }

        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            self.lastChangeCount = NSPasteboard.general.changeCount
            TetherLog("[ClipboardPlugin] Synced clipboard from \(connection.peerDeviceInfo?.deviceName ?? "Device"): \(content.prefix(30))...")
        }
    }

    /// The bytes of a `kdeconnect.clipboard.file` payload, already downloaded
    /// to a temp file that is deleted once this returns; read them now.
    public func handlePayload(connection: DeviceConnection, packet: NetworkPacket, fileURL: URL) {
        guard packet.type == Self.clipboardFileType else { return }
        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isClipboardSyncEnabled else { return }

        guard let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation else {
            TetherLog("[ClipboardPlugin] Received clipboard image could not be decoded")
            return
        }

        let png = Self.tiffToPng(tiff)

        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            // TIFF is what most macOS apps paste; PNG keeps the format for others.
            NSPasteboard.general.setData(tiff, forType: .tiff)
            if let png { NSPasteboard.general.setData(png, forType: .png) }
            self.lastChangeCount = NSPasteboard.general.changeCount
            self.lastReceivedImageData = png ?? tiff
            self.lastSentImageData = self.lastReceivedImageData
            TetherLog("[ClipboardPlugin] Synced image from \(connection.peerDeviceInfo?.deviceName ?? "Device") (\(data.count) bytes)")
        }
    }

    public func broadcastClipboard(content: String) {
        let packet = NetworkPacket(
            type: "kdeconnect.clipboard",
            body: ["content": content]
        )
        let targets: [DeviceConnection] = lock.withLock { activeConnections }
        for connection in targets {
            if let deviceId = connection.peerDeviceInfo?.deviceId,
               let paired = TrustStore.shared.pairedDevice(for: deviceId),
               paired.isClipboardSyncEnabled {
                connection.send(packet: packet)
            }
        }
    }

    /// Offers the image on a payload port per connected device and waits for
    /// the upload to finish, mirroring `SharePlugin`'s synchronous send.
    /// Must run off the main thread; the semaphore blocks until each transfer
    /// completes (or times out inside `PayloadUploader`).
    private func broadcastImage(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tether-clipboard-\(UUID().uuidString).png")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            TetherLog("[ClipboardPlugin] Could not stage clipboard image for upload: \(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        for connection in lock.withLock({ activeConnections }) {
            guard let deviceId = connection.peerDeviceInfo?.deviceId,
                  let paired = TrustStore.shared.pairedDevice(for: deviceId),
                  paired.isClipboardSyncEnabled,
                  Self.canReceiveImages(connection.peerDeviceInfo) else {
                continue
            }

            let uploader = PayloadUploader()
            let semaphore = DispatchSemaphore(value: 0)
            uploader.start(
                fileURL: tempURL,
                expectedPeerFingerprint: connection.peerCertificateFingerprint,
                onReady: { offer in
                    let packet = NetworkPacket(
                        type: Self.clipboardFileType,
                        body: ["filename": AnyCodable(filename)],
                        payloadSize: offer.size,
                        payloadTransferInfo: ["port": AnyCodable(Int(offer.port))]
                    )
                    connection.send(packet: packet)
                    TetherLog("[ClipboardPlugin] Announced clipboard image \(filename) (\(offer.size) bytes) on port \(offer.port)")
                },
                onProgress: { _ in },
                onComplete: { result in
                    switch result {
                    case .success:
                        TetherLog("[ClipboardPlugin] Sent clipboard image to \(connection.peerDeviceInfo?.deviceName ?? "Device")")
                    case .failure(let error):
                        TetherLog("[ClipboardPlugin] Failed sending clipboard image to \(connection.peerDeviceInfo?.deviceName ?? "Device"): \(error)")
                    }
                    semaphore.signal()
                }
            )
            _ = semaphore.wait(timeout: .distantFuture)
        }
    }

    // MARK: - Image sync decisions (pure, for tests)

    /// True when the pasteboard holds an image worth syncing rather than a
    /// Finder file copy (which puts a TIFF icon alongside the file URL).
    static func isImageCopy(types: [NSPasteboard.PasteboardType]) -> Bool {
        let set = Set(types)
        guard set.contains(.png) || set.contains(.tiff) else { return false }
        return !set.contains(.fileURL)
    }

    /// Image echo suppression, mirroring the text path's comparison against
    /// the last received and last sent content.
    static func shouldBroadcastImage(_ png: Data, lastReceivedImageData: Data?, lastSentImageData: Data?) -> Bool {
        png != lastReceivedImageData && png != lastSentImageData
    }

    /// Only peers that advertise the file-clipboard type can accept images;
    /// stock KDE Connect silently skips them.
    static func canReceiveImages(_ info: DeviceInfo?) -> Bool {
        info?.incomingCapabilities.contains(clipboardFileType) == true
    }

    static func tiffToPng(_ tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
