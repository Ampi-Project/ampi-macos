// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// Checks original layouts and rejects unsafe or unusable experimental theme payloads.
final class ThemeTests: XCTestCase {
    /// Mutates a valid bundled layout's JSON to isolate one validation failure per test.
    /// - Parameter change: Mutation applied to a temporary decoded JSON object.
    /// - Returns: Encoded JSON payload containing the requested change.
    /// - Throws: Resource-loading, encoding, decoding, or fixture-unwrapping errors.
    private func modifiedTheme(_ change: (inout [String: Any]) -> Void) throws -> Data {
        /// Valid reference layout from which malformed fixtures are derived.
        let theme = try ThemeCatalog.builtin("retro")
        /// Mutable JSON dictionary changed by the caller before re-encoding.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(theme)) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Both shipped layouts must validate and demonstrate changes to surface geometry.
    func testBothOriginalLayoutsAreValidAndHaveDifferentGeometry() throws {
        /// Wide reference layout with horizontal transport controls.
        let retro = try ThemeCatalog.builtin("retro")
        /// Taller reference layout with a distinct arrangement of controls.
        let minimal = try ThemeCatalog.builtin("minimal")
        try retro.validate()
        try minimal.validate()
        XCTAssertNotEqual(retro.width, minimal.width)
        XCTAssertNotEqual(retro.height, minimal.height)
    }

    /// An unknown draft version must be rejected before rendering.
    func testUnsupportedVersionIsRejected() throws {
        XCTAssertThrowsError(try Theme.decode(modifiedTheme { $0["schemaVersion"] = 99 }))
    }

    /// Multiple elements may not share the same layout identifier.
    func testDuplicateElementIdentifiersAreRejected() throws {
        /// Payload containing two elements with a duplicated identifier.
        let data = try modifiedTheme {
            /// Mutable element fixtures whose second identifier is overwritten.
            var elements = $0["elements"] as! [[String: Any]]
            elements[1]["id"] = elements[0]["id"]
            $0["elements"] = elements
        }
        XCTAssertThrowsError(try Theme.decode(data))
    }

    /// A control extending beyond the player surface must be rejected.
    func testOutOfBoundsHitRegionIsRejected() throws {
        /// Payload with a control frame extending past the right edge.
        let data = try modifiedTheme {
            /// Mutable element fixtures whose first frame is moved out of bounds.
            var elements = $0["elements"] as! [[String: Any]]
            elements[0]["frame"] = [610, 0, 100, 100]
            $0["elements"] = elements
        }
        XCTAssertThrowsError(try Theme.decode(data))
    }

    /// A button may dispatch only the fixed player-action allowlist.
    func testUnknownPlayerActionIsRejected() throws {
        /// Payload replacing a valid button action with a forbidden operation.
        let data = try modifiedTheme {
            /// Mutable controls searched for the original Open button.
            var elements = $0["elements"] as! [[String: Any]]
            /// Open-button index selected for the invalid action mutation.
            let index = elements.firstIndex { $0["action"] as? String == "open" }!
            elements[index]["action"] = "executeShell"
            $0["elements"] = elements
        }
        XCTAssertThrowsError(try Theme.decode(data))
    }

    /// A layout cannot omit the Open control needed to add music.
    func testThemeWithoutRecoveryPlaybackControlsIsRejected() throws {
        /// Payload with all Open buttons removed from a valid layout.
        let data = try modifiedTheme {
            /// Original controls filtered to remove the required file-opening action.
            let elements = $0["elements"] as! [[String: Any]]
            $0["elements"] = elements.filter { $0["action"] as? String != "open" }
        }
        XCTAssertThrowsError(try Theme.decode(data))
    }

    /// Palette entries containing non-hexadecimal digits must be rejected.
    func testInvalidPaletteIsRejected() throws {
        /// Payload with a malformed accent color.
        let data = try modifiedTheme {
            /// Mutable palette fixture whose accent is changed to invalid digits.
            var palette = $0["palette"] as! [String: Any]
            palette["accent"] = "#GGGGGG"
            $0["palette"] = palette
        }
        XCTAssertThrowsError(try Theme.decode(data))
    }

    /// Payloads exceeding 256 KiB must fail the size guard before JSON decoding.
    func testOversizedUntrustedFileIsRejectedBeforeDecoding() {
        XCTAssertThrowsError(try Theme.decode(Data(repeating: 32, count: 256 * 1024 + 1)))
    }
}
