// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import UniformTypeIdentifiers

/// Hosts replaceable skin views around one persistent playback session.
@MainActor final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    /// Queue and transport model shared by every replacement surface.
    let session: PlaybackSession
    /// Currently displayed native skin surface.
    private(set) var surface: any PlayerSurface
    /// Refreshes playback time every 0.2 seconds, since offset changes have no observer event.
    private var timer: Timer?
    /// Most recently opened Classic inspector, retained separately from the active skin.
    private(set) var classicPreview: ClassicSkinPreviewController?
    /// Optional detachable playlist bound to the same session while a Classic presentation is active.
    private(set) var classicPlaylist: ClassicPlaylistWindowController?
    /// Detachable session-owned EQ controls; native layouts use an original backdrop.
    private(set) var equalizerPanel: EqualizerWindowController?
    /// Shared read-only metadata/artwork panel, retained across native/Classic replacements.
    private(set) var trackInfoPanel: TrackInfoWindowController?
    /// Bounded asynchronous tag reader follows live identities without accessing the playback backend.
    private let metadataCoordinator: TrackMetadataCoordinator
    /// Cancellable background inspection; a newer import supersedes a pending one.
    private var inspectionTask: Task<Void, Never>?
    /// Durable presentation, updated only after a replacement successfully installs.
    private(set) var savedSkin: SavedSkin
    /// Native persistence observer receives durable/session changes without owning the rendering observer.
    var onPersistentChange: (() -> Void)?
    /// Interactive app close request routes through the application's asynchronous final save.
    var onRequestClose: (() -> Void)?

    /// Builds a fixed-size player window for a previously validated layout.
    /// - Parameters:
    ///   - session: Persistent queue and playback state to display.
    ///   - theme: Validated initial layout; callers must validate before constructing controls.
    init(session: PlaybackSession, theme: Theme) {
        self.session = session
        self.metadataCoordinator = TrackMetadataCoordinator(session: session)
        self.surface = SkinView(theme: theme, session: session)
        self.savedSkin = .native(theme)
        /// Native titled window sized to the layout's content surface.
        let window = NSWindow(contentRect: surface.view.bounds, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Ampi — \(theme.name)"
        window.contentView = surface.view
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        connectSurface()
        window.center()
        /// Refreshes the current surface after model changes without retaining the controller.
        session.onChange = { [weak self] in
            self?.metadataCoordinator.synchronize(); self?.refreshSurfaces(); self?.onPersistentChange?()
        }
        /// Metadata completion updates text/images without saving unchanged durable session data.
        session.onMetadataChange = { [weak self] in self?.refreshSurfaces() }
        metadataCoordinator.synchronize()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSurfaces() }
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
        /// An existing EQ window gets the native backdrop without changing its curve or visibility.
        let equalizer = equalizerPanel == nil ? nil : try EqualizerWindowController(package: nil, session: session)
        /// Visibility and placement captured before closing the old skin's panels.
        let visible = equalizerPanel?.window?.isVisible == true
        /// Prior EQ origin, reused across layout changes.
        let origin = equalizerPanel?.window?.frame.origin
        install(replacement)
        if let equalizer { installEqualizer(equalizer, visible: visible, origin: origin) }
        savedSkin = .native(theme); onPersistentChange?()
    }

    /// Composes a validated Classic main surface before replacing the current interface.
    /// - Throws: Missing or undersized required sprite errors, preserving the current surface.
    func applyClassic(_ package: ClassicSkinPackage) throws {
        /// Fully constructed replacement using the same queue and audio backend.
        let replacement = try ClassicPlayerView(package: package, session: session)
        /// Playlist is validated before installing either replacement, making activation atomic.
        let playlist = try ClassicPlaylistWindowController(package: package, session: session)
        /// All three surfaces must validate before any active window is replaced.
        let equalizer = try EqualizerWindowController(package: package, session: session)
        /// First Classic activation opens EQ; later replacements preserve the user's visibility choice.
        let equalizerVisible = equalizerPanel?.window?.isVisible ?? true
        /// Previous EQ placement persists when changing Classic artwork.
        let equalizerOrigin = equalizerPanel?.window?.frame.origin
        /// Existing visibility and position persist between Classic packages; first activation opens the panel.
        let visible = classicPlaylist?.window?.isVisible ?? true
        /// Previous native panel origin; contents keep their fixed dimensions in this increment.
        let origin = classicPlaylist?.window?.frame.origin
        /// Toolbar command forwards through the same transport dispatch path as the main window.
        playlist.content.onAction = { [weak self] action in self?.perform(action) }
        /// Local dropped URLs share file/skin routing with the main player.
        playlist.content.onDrop = { [weak self] urls in self?.open(urls) }
        /// Queue row plays through the existing backend, with a corrupt replacement preserving playback.
        playlist.content.onPlay = { [weak self] index in self?.playQueueEntry(index) }
        /// Native panel close updates the main PL indicator without stopping output.
        playlist.onVisibilityChange = { [weak self] visible in self?.updatePlaylistVisibility(visible) }
        install(replacement)
        classicPlaylist = playlist
        /// Position the first playlist below the player, keeping its bottom on the current screen.
        if let frame = window?.frame, let playlistWindow = playlist.window {
            playlistWindow.setFrameOrigin(origin ?? NSPoint(x: frame.minX,
                y: max(window?.screen?.visibleFrame.minY ?? 0, frame.minY - playlistWindow.frame.height - 8)))
        }
        if visible { playlist.showWindow(nil) }
        updatePlaylistVisibility(visible)
        installEqualizer(equalizer, visible: equalizerVisible, origin: equalizerOrigin)
        savedSkin = .classic(package.sourceURL); onPersistentChange?()
    }

    /// Installs prepared content, preserving the session, observer, and refresh timer.
    private func install(_ replacement: any PlayerSurface) {
        /// Intended content size captured before AppKit resizes a newly assigned content view.
        let contentSize = replacement.view.bounds.size
        classicPlaylist?.close()
        classicPlaylist = nil
        equalizerPanel?.close()
        equalizerPanel = nil
        surface = replacement
        connectSurface()
        window?.contentView = replacement.view
        window?.setContentSize(contentSize)
        window?.title = "Ampi — \(replacement.displayName)"
        window?.recalculateKeyViewLoop()
    }

    /// Updates both surfaces through one session observer and timer; hidden playlists stay synchronized.
    private func refreshSurfaces() {
        surface.refresh()
        classicPlaylist?.content.refresh()
        equalizerPanel?.content.refresh()
        trackInfoPanel?.content.refresh()
    }

    /// Shows/hides metadata for the loaded track with either skin; browsing the queue alone never changes its content.
    func toggleTrackInfo() {
        if trackInfoPanel == nil { trackInfoPanel = TrackInfoWindowController(session: session) }
        /// Existing panel follows session selection while hidden and retains its native placement across skin switches.
        guard let panel = trackInfoPanel else { return }
        if panel.window?.isVisible == true { panel.close() }
        else { panel.content.refresh(); panel.showWindow(nil) }
    }

    /// Plays a valid highlighted queue row and reports failures without clearing the current track.
    private func playQueueEntry(_ index: Int) {
        do { try session.play(index: index) }
        catch { session.report(error); showError(error.localizedDescription) }
    }

    /// Active presentation's browsable queue, shared with native menu commands even when another panel has focus.
    var editingTable: EditableQueueTable? {
        classicPlaylist?.content.table ?? (surface as? SkinView)?.queueTable
    }

    /// Reports whether the active queue can perform a selected-row edit or a global clear.
    func canEditQueue(_ action: QueueEditAction) -> Bool {
        action == .clear ? !session.tracks.isEmpty : editingTable?.canEdit(action) == true
    }

    /// Edits the highlighted queue row; Clear also works for native layouts that omit a queue control.
    func editQueue(_ action: QueueEditAction) {
        /// Visible presentation supplies its browsed row; layouts without a table can still clear globally.
        if let table = editingTable { table.performEdit(action) }
        else if action == .clear { session.clearQueue() }
    }

    /// Shows or hides the current Classic playlist without recreating the panel or playback session.
    func togglePlaylist() {
        /// Panel is available only while a Classic presentation is active.
        guard let playlist = classicPlaylist else { return }
        if playlist.window?.isVisible == true { playlist.close() }
        else { playlist.content.refresh(); playlist.showWindow(nil) }
        updatePlaylistVisibility(playlist.window?.isVisible == true)
    }

    /// Synchronizes the native main PL button with window-menu and title-bar close actions.
    private func updatePlaylistVisibility(_ visible: Bool) {
        /// Classic surface exposes the indicator; native layouts contain their own queue.
        if let classic = surface as? ClassicPlayerView {
            classic.playlistButton.state = visible ? .on : .off
            classic.playlistButton.needsDisplay = true
            classic.playlistButton.setAccessibilityValue(visible ? "Shown" : "Hidden")
        }
    }

    /// Attaches a prepared panel, preserving its native origin and visibility across skin switches.
    private func installEqualizer(_ equalizer: EqualizerWindowController, visible: Bool, origin: NSPoint?) {
        equalizerPanel = equalizer
        /// Closing through native chrome updates the active Classic EQ indicator.
        equalizer.onVisibilityChange = { [weak self] visible in self?.updateEqualizerVisibility(visible) }
        /// Initial EQ appears alongside the main window, clamped inside the screen's visible bounds.
        if let frame = window?.frame, let panel = equalizer.window {
            /// Screen bounds account for dock and menu bar when choosing the initial panel origin.
            let screen = window?.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            panel.setFrameOrigin(origin ?? NSPoint(x: max(screen.minX, min(frame.maxX + 8, screen.maxX - panel.frame.width)),
                y: max(screen.minY, frame.maxY - panel.frame.height)))
        }
        if visible { equalizer.showWindow(nil) }
        updateEqualizerVisibility(visible)
    }

    /// Shows/hides EQ without changing DSP; native layouts lazily create the original fallback panel.
    func toggleEqualizer() {
        /// Existing hidden controls remain synchronized through the shared observer.
        if let equalizer = equalizerPanel {
            if equalizer.window?.isVisible == true { equalizer.close() }
            else { equalizer.content.refresh(); equalizer.showWindow(nil) }
            updateEqualizerVisibility(equalizer.window?.isVisible == true)
        } else {
            do { installEqualizer(try EqualizerWindowController(package: nil, session: session), visible: true, origin: nil) }
            catch { showError(error.localizedDescription) }
        }
    }

    /// Synchronizes the main EQ indicator with menu and native panel-close actions.
    private func updateEqualizerVisibility(_ visible: Bool) {
        /// Only the Classic main surface has an embedded EQ toggle; native layouts use the Window menu.
        if let classic = surface as? ClassicPlayerView {
            classic.equalizerButton.state = visible ? .on : .off
            classic.equalizerButton.needsDisplay = true
            classic.equalizerButton.setAccessibilityValue(visible ? "Shown" : "Hidden")
        }
    }

    /// Routes a primary native close request through final-save Quit, keeping the window available if saving fails.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        /// Interactive host can intercept closing; isolated previews/tests retain ordinary AppKit lifecycle.
        if let onRequestClose { onRequestClose(); return false }
        return true
    }

    /// Closes child windows and stops output after the primary window actually closes.
    func windowWillClose(_ notification: Notification) {
        inspectionTask?.cancel()
        metadataCoordinator.cancel()
        timer?.invalidate(); timer = nil
        classicPlaylist?.close()
        equalizerPanel?.close()
        trackInfoPanel?.close()
        classicPreview?.close()
        session.stop()
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
        /// Sheet accepting skin inputs; Classic packages/folders are inspected before explicit activation.
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
                /// Explicit activation applies the inspected package while keeping the preview available.
                preview.onActivate = { [weak self] in
                    do { try self?.applyClassic(package) }
                    catch { self?.showError(error.localizedDescription) }
                }
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
    /// - Parameter action: Open, playlist, equalizer, previous, play, pause, playPause, stop, or next; unknown values are ignored.
    func perform(_ action: String) {
        do {
            switch action {
            case "open": openFiles()
            case "playlist": togglePlaylist()
            case "equalizer": toggleEqualizer()
            case "previous": try session.previous()
            case "playPause": try session.togglePlayback()
            case "play": try session.resume()
            case "pause": session.pause()
            case "stop": session.stop()
            case "next": try session.next()
            case "shuffle": session.setShuffleEnabled(!session.isShuffleEnabled)
            case "repeat": session.cycleRepeatMode()
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
        surface.view.layoutSubtreeIfNeeded()
        /// Bitmap sized for caching the full native content surface.
        guard let bitmap = surface.view.bitmapImageRepForCachingDisplay(in: surface.view.bounds) else {
            throw ThemeError.invalid("Could not create a preview bitmap.")
        }
        surface.view.cacheDisplay(in: surface.view.bounds, to: bitmap)
        /// Encoded PNG payload to write to the requested destination.
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ThemeError.invalid("Could not encode the preview.")
        }
        try png.write(to: url)
    }
}
