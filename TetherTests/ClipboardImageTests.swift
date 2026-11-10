//
//  ClipboardImageTests.swift
//  TetherTests
//

import Testing
import AppKit
import Foundation
@testable import Tether

struct ClipboardImageTests {

    // MARK: - Capability advertisement

    @Test func testClipboardFileCapabilityAdvertised() {
        #expect(DeviceInfo.defaultIncomingCapabilities.contains(ClipboardPlugin.clipboardFileType))
        #expect(DeviceInfo.defaultOutgoingCapabilities.contains(ClipboardPlugin.clipboardFileType))
    }

    // MARK: - Packet construction (plan §5.1)

    /// The announcement `broadcastImage` sends must survive a serialize
    /// round-trip with its filename, timestamp, payload size, and integer
    /// port intact.
    @Test func testClipboardFileAnnouncementRoundTrip() throws {
        let packet = NetworkPacket(
            type: ClipboardPlugin.clipboardFileType,
            body: [
                "filename": AnyCodable("1234567890123.png"),
                "timestamp": AnyCodable(Int64(1_794_340_139_939))
            ],
            payloadSize: 123_456,
            payloadTransferInfo: ["port": AnyCodable(Int(1739))]
        )

        let decoded = try NetworkPacket.unserialize(from: packet.serialize())
        #expect(decoded.type == "kdeconnect.clipboard.file")
        #expect(decoded.string(for: "filename") == "1234567890123.png")
        #expect(decoded.int64(for: "timestamp") == 1_794_340_139_939)
        #expect(decoded.payloadSize == 123_456)
        // The port travels in payloadTransferInfo, not the body (int(for:)
        // reads only the body).
        #expect(decoded.payloadTransferInfo?["port"]?.value as? Int == 1739)
    }

    @Test func testImageSizeCapMatchesAndroid() {
        #expect(ClipboardPlugin.maximumImagePayloadSize == 50 * 1_048_576)
    }

    // MARK: - Pasteboard image detection (plan §5.2)

    @Test func testPngOnlyPasteboardIsImageCopy() {
        #expect(ClipboardPlugin.isImageCopy(types: [.png]))
        #expect(ClipboardPlugin.isImageCopy(types: [.tiff]))
    }

    @Test func testFileURLPasteboardIsNotImageCopy() {
        // Finder copies put a TIFF icon next to the file URL; the icon must
        // not be synced as an image.
        #expect(!ClipboardPlugin.isImageCopy(types: [.fileURL, .tiff]))
        #expect(!ClipboardPlugin.isImageCopy(types: [.fileURL, .png, .string]))
    }

    @Test func testTextOnlyPasteboardIsNotImageCopy() {
        #expect(!ClipboardPlugin.isImageCopy(types: [.string]))
        #expect(!ClipboardPlugin.isImageCopy(types: []))
    }

    // MARK: - Echo suppression (plan §5.3)

    @Test func testReceivedImageIsNotRebroadcast() throws {
        let png = try pngFixture()
        // handlePayload records the applied image as both received and sent;
        // checkPasteboard must not broadcast it again.
        #expect(!ClipboardPlugin.shouldBroadcastImage(
            png,
            lastReceivedImageData: png,
            lastSentImageData: png
        ))
    }

    @Test func testFreshImageIsBroadcast() throws {
        let png = try pngFixture()
        #expect(ClipboardPlugin.shouldBroadcastImage(
            png,
            lastReceivedImageData: nil,
            lastSentImageData: nil
        ))
        #expect(!ClipboardPlugin.shouldBroadcastImage(
            png,
            lastReceivedImageData: nil,
            lastSentImageData: png
        ))
        #expect(!ClipboardPlugin.shouldBroadcastImage(
            png,
            lastReceivedImageData: png,
            lastSentImageData: nil
        ))
    }

    // MARK: - Capability gating (plan §5.4)

    @Test func testCanReceiveImagesGatesOnPeerCapability() {
        let forkedPhone = DeviceInfo(
            deviceId: "abcdef0123456789abcdef0123456789",
            deviceName: "Forked Phone",
            deviceType: .phone,
            incomingCapabilities: ["kdeconnect.clipboard.file"],
            outgoingCapabilities: []
        )
        #expect(ClipboardPlugin.canReceiveImages(forkedPhone))

        let stockPhone = DeviceInfo(
            deviceId: "abcdef0123456789abcdef0123456789",
            deviceName: "Stock Phone",
            deviceType: .phone,
            incomingCapabilities: ["kdeconnect.clipboard"],
            outgoingCapabilities: []
        )
        #expect(!ClipboardPlugin.canReceiveImages(stockPhone))
        #expect(!ClipboardPlugin.canReceiveImages(nil))
    }

    // MARK: - Timestamp arbitration (connect-time resend)

    /// The peer resends its current clipboard image on reconnect; a stale one
    /// must not clobber newer local clipboard content.
    @Test func testStaleRemoteImageIsIgnored() {
        // A packet without a timestamp (older peer) is always applied.
        #expect(ClipboardPlugin.shouldApplyRemoteImage(packetTimestamp: 0, lastLocalClipboardTimestamp: 999))
        // A newer or equal remote clip wins.
        #expect(ClipboardPlugin.shouldApplyRemoteImage(packetTimestamp: 1000, lastLocalClipboardTimestamp: 999))
        #expect(ClipboardPlugin.shouldApplyRemoteImage(packetTimestamp: 999, lastLocalClipboardTimestamp: 999))
        // An older remote clip — the reconnect resend — is dropped.
        #expect(!ClipboardPlugin.shouldApplyRemoteImage(packetTimestamp: 500, lastLocalClipboardTimestamp: 999))
    }

    // MARK: - TIFF to PNG conversion

    @Test func testTiffToPngProducesPngBytes() throws {
        let tiff = try #require(makeImage().tiffRepresentation)
        let png = try #require(ClipboardPlugin.tiffToPng(tiff))
        // PNG magic number.
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(NSBitmapImageRep(data: png) != nil)
    }

    // MARK: - Helpers

    private func makeImage() -> NSImage {
        let size = NSSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func pngFixture() throws -> Data {
        let tiff = try #require(makeImage().tiffRepresentation)
        return try #require(ClipboardPlugin.tiffToPng(tiff))
    }
}
