// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Common main-actor bindings for native layouts and the Classic main player.
@MainActor protocol PlayerSurface: AnyObject {
    /// Native content installed in the existing player window.
    var view: NSView { get }
    /// Stable presentation identity used by diagnostics and developer checks.
    var presentationID: String { get }
    /// Human-readable layout name displayed in the native title bar.
    var displayName: String { get }
    /// Receives a transport command without retaining the window controller.
    var onAction: ((String) -> Void)? { get set }
    /// Receives local dropped files for routing through the common importer.
    var onDrop: (([URL]) -> Void)? { get set }
    /// Updates labels and controls from the persistent playback session.
    func refresh()
}
