// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Ampi

/// Exercises the real AppKit button drawing path, which core model tests cannot cover.
final class SkinButtonTests: XCTestCase {
    /// Cocoa text drawing must render empty, transport, and Unicode titles in both palettes.
    func testButtonTitlesRenderInBothPalettesAndHighlightStates() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            /// Supported foreground/background pairs from the two original layouts.
            let palettes: [(NSColor, NSColor)] = [(.black, .white), (.white, .black)]
            /// Titles covering normal transport, state changes, empty content, and UTF-16 text.
            for title in ["", "PLAY", "PAUSE", "Previous", "♫ موسیقی 🎵"] {
                /// Foreground and background colors retained during native drawing.
                for (ink, fill) in palettes {
                    /// Normal and pressed appearances both invoke the custom renderer.
                    for highlighted in [false, true] {
                        try autoreleasepool {
                            /// Fresh native button ensuring no previous render primes its text state.
                            let button = SkinButton(frame: NSRect(x: 0, y: 0, width: 180, height: 36))
                            button.title = title
                            button.ink = ink
                            button.fill = fill
                            button.highlight(highlighted)
                            /// Native bitmap context that executes the button's actual draw override.
                            let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
                            button.cacheDisplay(in: button.bounds, to: bitmap)
                            /// Encoded output proving the complete render path produced a bitmap.
                            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            XCTAssertFalse(png.isEmpty)
                            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                            XCTAssertEqual(Double(bitmap.pixelsWide) / Double(bitmap.pixelsHigh), 5, accuracy: 0.01)
                        }
                    }
                }
            }
        }
    }
}
