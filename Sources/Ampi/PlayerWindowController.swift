// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import UniformTypeIdentifiers

/// Hosts replaceable skin views around one persistent playback session.
@MainActor final class PlayerWindowController: NSWindowController {
    /// Queue and transport model shared by every replacement surface.
    let session: PlaybackSession
    /// Currently displayed native skin surface.
    private(set) var surface: SkinView
    /// Refreshes playback time every 0.2 seconds, since offset changes have no observer event.
    private var timer: Timer?
    /// Most recently opened Classic inspector, retained separately from the active skin.
    private(set) var classicPreview: ClassicSkinPreviewController?
    /// Cancellable background inspection; a newer import supersedes a pending one.
    private var inspectionTask: Task<Void, Never>?

    /// Builds a fixed-size player window for a previously validated layout.
    /// - Parameters:
    ///   - session: Persistent queue and playback state to display.
    ///   - theme: Validated initial layout; callers must validate before constructing controls.
    init(session: PlaybackSession, theme: Theme) {
        self.session = session
        self.surface = SkinView(theme: theme, session: session)
        /// Native titled window sized to the layout's content surface.
        let window = NSWindow(contentRect: surface.bounds, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Ampi — \(theme.name)"
        window.contentView = surface
        window.isReleasedWhenClosed = false
        super.init(window: window)
        connectSurface()
        window.center()
        /// Refreshes the current surface after model changes without retaining the controller.
        session.onChange = { [weak self] in self?.surface.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.surface.refresh() }
        }
    }

    /// Rejects archive/storyboard construction; a session and validated theme are required.
    required init?(coder: NSCoder) { fatalError("Use init(session:theme:)") }

    /// Validates and replaces the surface without replacing the playback session.
    /// - Throws: A validation error, leaving the current surface installed.
    func apply(_ theme: Theme) throws {
        try theme.validate()
        /// New surface attached only after its layout passes validation.
        let replacement = SkinView(theme: theme, session: session)
        surface = replacement
        connectSurface()
        window?.contentView = replacement
        window?.setContentSize(replacement.bounds.size)
        window?.title = "Ampi — \(theme.name)"
    }

    /// Routes the current surface's actions and file drops through this controller.
    private func connectSurface() {
        /// Action is the validated button command emitted by the current skin.
        surface.onAction = { [weak self] action in self?.perform(action) }
        /// URLs are local files extracted by the current skin's drag-and-drop handler.
        surface.onDrop = { [weak self] urls in self?.open(urls) }
    }

    /// Presents a native audio picker and appends accepted files to the queue.
    func openFiles() {
        /// Sheet restricted to audio files, with multiple selection enabled.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Queue"
        /// Response indicates acceptance or cancellation; accepted panel URLs are appended.
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK else { return }
            self?.open(panel.urls)
        }
    }

    /// Applies a lone JSON layout, previews a Classic package/folder, or queues audio files.
    /// Modern skins and mixed audio/skin selections produce a diagnostic.
    /// - Parameter urls: Files selected, dropped, or delivered by macOS.
    func open(_ urls: [URL]) {
        if urls.count == 1, urls[0].pathExtension.lowercased() == "json" {
            importTheme(urls[0]); return
        }
        /// Skin candidates are handled separately so their bytes never reach the audio decoder.
        let skinInputs = urls.filter { url in
            ["wsz", "wal", "zip"].contains(url.pathExtension.lowercased()) ||
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        if !skinInputs.isEmpty {
            guard urls.count == 1 else { showError("Inspect one skin package or folder at a time, separately from audio files."); return }
            previewClassicSkin(urls[0])
            return
        }
        /// First appended queue index, used to start playback when no track is selected.
        let first = session.tracks.count
        session.enqueue(urls)
        if session.currentTrack == nil, first < session.tracks.count {
            do { try session.play(index: first) } catch { session.report(error); showError(error.localizedDescription) }
        }
    }

    /// Presents a native picker for Ampi JSON layouts, Classic archives, and extracted folders.
    func openTheme() {
        /// Sheet accepting supported skin inputs; directories remain inspection-only.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .zip, UTType(filenameExtension: "wsz") ?? .data]
        panel.canChooseDirectories = true
        panel.prompt = "Open Skin"
        /// Response indicates whether the user accepted a layout selection.
        panel.beginSheetModal(for: window!) { [weak self] response in
            /// Accepted layout file URL; cancellation or an absent URL leaves the skin unchanged.
            guard response == .OK, let url = panel.url else { return }
            self?.open([url])
        }
    }

    /// Inspects Classic input off the main actor and opens a preview without changing playback.
    /// - Parameter url: ZIP/.wsz file or extracted folder; Modern input is rejected by structure.
    func previewClassicSkin(_ url: URL) {
        inspectionTask?.cancel()
        /// Weak controller capture prevents the import task from keeping a closed controller alive.
        inspectionTask = Task { [weak self] in
            do {
                /// Worker performs bounded file reads, decompression, and bitmap checks off the UI thread.
                let worker = Task.detached(priority: .userInitiated) { try ClassicSkinPackage.load(url) }
                /// Cancellation is forwarded to the worker, whose read/decompression loops check it.
                let package = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                /// Available controller, retained only while attaching the completed preview.
                guard let self else { return }
                /// New inspector is constructed before closing a previously valid preview.
                let preview = try ClassicSkinPreviewController(package: package)
                self.classicPreview?.close()
                self.classicPreview = preview
                preview.showWindow(nil)
            } catch is CancellationError {
                // A newer inspection superseded this one; no user-facing error is needed.
            } catch { self?.showError(error.localizedDescription) }
        }
    }

    /// Loads and applies a local layout, displaying any failure without replacing the skin.
    private func importTheme(_ url: URL) {
        do { try apply(ThemeCatalog.load(url)) }
        catch { showError(error.localizedDescription) }
    }

    /// Dispatches a supported skin/menu action and presents transport failures.
    /// - Parameter action: Open, previous, playPause, stop, or next; unknown values are ignored.
    func perform(_ action: String) {
        do {
            switch action {
            case "open": openFiles()
            case "previous": try session.previous()
            case "playPause": try session.togglePlayback()
            case "stop": session.stop()
            case "next": try session.next()
            default: break
            }
        } catch { session.report(error); showError(error.localizedDescription) }
    }

    /// Presents a warning sheet when the player window is available.
    /// - Parameter message: User-facing explanation of the failed action.
    func showError(_ message: String) {
        /// Native warning displaying a common heading and the supplied diagnostic.
        let alert = NSAlert()
        alert.messageText = "Ampi could not complete that action"
        alert.informativeText = message
        alert.alertStyle = .warning
        /// Available player window to which the nonblocking warning sheet is attached.
        if let window { alert.beginSheetModal(for: window) }
    }

    /// Renders the current native surface to PNG for developer layout inspection.
    /// - Parameter url: Destination file, overwritten by the generated PNG data.
    /// - Throws: A bitmap creation, PNG encoding, or file-writing error.
    func exportPreview(to url: URL) throws {
        surface.layoutSubtreeIfNeeded()
        /// Bitmap sized for caching the full native content surface.
        guard let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else {
            throw ThemeError.invalid("Could not create a preview bitmap.")
        }
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        /// Encoded PNG payload to write to the requested destination.
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ThemeError.invalid("Could not encode the preview.")
        }
        try png.write(to: url)
    }
}
