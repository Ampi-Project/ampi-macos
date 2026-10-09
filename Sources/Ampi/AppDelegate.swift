// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Creates the native player and connects application lifecycle and menu commands.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Retained player controller, created after the default layout loads successfully.
    private var controller: PlayerWindowController?
    /// Native audio output retained for the lifetime of the application delegate.
    private let backend = NativeAudioBackend()
    /// Startup/termination persistence coordinator retained alongside the native player.
    private var persistence: PlayerPersistence?
    /// File-open events arriving during asynchronous restore are appended after startup completes.
    private var pendingOpenRequests: [[URL]] = []
    /// Keeps externally opened files from being overwritten by an in-flight startup restore.
    private var isRestoring = true
    /// Guards repeated native Quit/close requests while the final save awaits the storage actor.
    private var isTerminating = false

    /// Starts the default player and menus, or displays a fatal startup error and exits.
    /// - Parameter notification: AppKit launch event; no payload is needed here.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await launchPlayer() }
    }

    /// Builds the default player, restores saved state stopped, and then accepts queued file-open events.
    private func launchPlayer() async {
        do {
            /// Session shared by the window and native completion handler.
            let session = PlaybackSession(backend: backend)
            /// Success is the native completion result; the weak session receives auto-advance/errors.
            backend.onFinish = { [weak session] success in session?.finished(successfully: success) }
            /// Default remains available if saved geometry or Classic assets no longer validate.
            let player = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            controller = player
            /// Actor owns serial bounded JSON reads and atomic replacements in native application support.
            let store = SessionStateStore(url: try SessionStateStore.defaultURL())
            /// Recovery happens before attaching observation so it cannot save a partially restored session.
            let recovery = PlayerPersistence(controller: player, store: store)
            persistence = recovery
            /// Combined nonfatal diagnostics leave valid queue/settings usable, without triggering audio.
            let notices = await recovery.restore()
            if !notices.isEmpty { session.report(ThemeError.invalid(notices.joined(separator: " "))) }
            recovery.startSaving()
            /// Native primary-window close uses the same final save/error handling as the Quit command.
            player.onRequestClose = { [weak self] in
                guard self?.isTerminating == false else { return }
                NSApp.terminate(nil)
            }
            installMenus()
            player.showWindow(nil)
            isRestoring = false
            /// OS-delivered files represent an explicit open request, so normal importer playback rules apply.
            let queuedRequests = pendingOpenRequests
            pendingOpenRequests.removeAll()
            /// Preserve independent OS-open requests rather than merging an audio request with a separate skin import.
            for urls in queuedRequests { player.open(urls) }
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            /// Blocking startup alert used before a player window is available.
            let alert = NSAlert()
            alert.messageText = "Ampi could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Requests application termination when its last player window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Forwards files opened through macOS to the current player's import/queue handler.
    func application(_ application: NSApplication, open urls: [URL]) {
        if isRestoring { pendingOpenRequests.append(urls) }
        else { controller?.open(urls) }
    }

    /// Awaits a final durable snapshot on Quit/primary close; save errors let the owner cancel or quit without saving.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        /// Before startup completes there is no restored session to overwrite, so termination is immediate.
        guard !isRestoring, let persistence else { backend.stop(); return .terminateNow }
        isTerminating = true
        /// Pause retains the in-memory offset in case the owner cancels a failed save.
        let wasPlaying = controller?.session.state == .playing
        controller?.session.pause()
        Task {
            do {
                try await persistence.flush()
                controller?.session.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                /// Meaningful quit choice leaves the previous valid disk state intact if final replacement fails.
                let alert = NSAlert()
                alert.messageText = "Ampi could not save this session"
                alert.informativeText = "The previous saved session is unchanged. Cancel to keep the app open, or quit without saving these changes."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Quit Without Saving")
                if alert.runModal() == .alertSecondButtonReturn {
                    controller?.session.stop(); sender.reply(toApplicationShouldTerminate: true)
                } else {
                    isTerminating = false; persistence.resumeSaving()
                    if wasPlaying {
                        do { try controller?.session.resume() } catch { controller?.session.report(error) }
                    }
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
        }
        return .terminateLater
    }

    /// Installs native app, file, transport, theme, and window menus with shortcuts.
    private func installMenus() {
        /// Root menu bar assigned to the running native application.
        let main = NSMenu()
        NSApp.mainMenu = main
        /// Standard About, Hide, and Quit actions under the application name.
        let appMenu = NSMenu(title: "Ampi")
        /// Menu-bar item that hosts the application submenu.
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        appMenu.addItem(withTitle: "About Ampi", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ampi", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Ampi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        /// Audio and JSON-layout file selection commands.
        let file = submenu("File", in: main)
        add("Open Audio…", to: file, action: #selector(openAudio), key: "o")
        add("Open Skin / Layout…", to: file, action: #selector(openLayout), key: "o", modifiers: [.command, .shift])

        /// Transport actions available regardless of the active layout.
        let playback = submenu("Playback", in: main)
        add("Play / Pause", to: playback, action: #selector(togglePlayback), key: " ", modifiers: [])
        add("Stop", to: playback, action: #selector(stop), key: ".")
        add("Previous Track", to: playback, action: #selector(previous), key: "\u{F702}")
        add("Next Track", to: playback, action: #selector(next), key: "\u{F703}")
        playback.addItem(.separator())
        add("Shuffle", to: playback, action: #selector(toggleShuffle), key: "s", modifiers: [.command, .shift])
        /// Repeat choices share one validated policy instead of independent toggle states.
        let repeatMenu = submenu("Repeat", in: playback)
        /// Fixed policies carry raw values; validation reflects changes from any player surface.
        for mode in PlaybackSession.RepeatMode.allCases {
            /// Native checkmark item selects Off, All, or One without starting playback.
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(selectRepeat(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue
            repeatMenu.addItem(item)
        }

        /// Queue commands act on the highlighted row of the current native or Classic presentation.
        let queue = submenu("Queue", in: main)
        /// Each native item uses the same typed action as table keyboard/context input.
        for action in QueueEditAction.allCases {
            /// Dynamic validation prevents edits at missing rows or movement past either queue end.
            let item = NSMenuItem(title: action.title, action: #selector(editQueue(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = action.rawValue
            queue.addItem(item)
        }

        /// Built-in layout choices, including the default-layout recovery command.
        let themes = submenu("Themes", in: main)
        add("Restore Default / Retro Stereo", to: themes, action: #selector(retro), key: "0", modifiers: [.command, .shift])
        add("Quiet Space", to: themes, action: #selector(minimal), key: "1", modifiers: [.command, .shift])

        /// Native window commands also registered as AppKit's windows menu.
        let windowMenu = submenu("Window", in: main)
        add("Show / Hide Classic Playlist", to: windowMenu, action: #selector(togglePlaylist), key: "l")
        add("Show / Hide Equalizer", to: windowMenu, action: #selector(toggleEqualizer), key: "e")
        add("Show / Hide Track Info", to: windowMenu, action: #selector(toggleTrackInfo), key: "i")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu
    }

    /// Attaches a submenu with the supplied title to a parent and returns it.
    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        /// New submenu that will contain commands.
        let menu = NSMenu(title: title)
        /// Parent item whose submenu points to the newly created menu.
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    /// Adds a command targeting this delegate, with an explicit keyboard shortcut.
    /// - Parameters:
    ///   - title: Visible command name.
    ///   - menu: Menu receiving the command.
    ///   - action: Objective-C selector invoked when activated.
    ///   - key: AppKit key equivalent; an empty string means no shortcut.
    ///   - modifiers: Shortcut modifiers, defaulting to Command.
    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String,
                     modifiers: NSEvent.ModifierFlags = [.command]) {
        /// Command configured to dispatch to this delegate with the requested shortcut.
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    /// Opens the player's native audio-file picker from the File menu.
    @objc private func openAudio() { controller?.openFiles() }
    /// Opens the JSON-layout and Classic-package picker from the File menu.
    @objc private func openLayout() { controller?.openTheme() }
    /// Toggles transport through the same dispatch path used by skin buttons.
    @objc private func togglePlayback() { controller?.perform("playPause") }
    /// Stops and rewinds playback from the native menu.
    @objc private func stop() { controller?.perform("stop") }
    /// Restarts or selects the previous track from the native menu.
    @objc private func previous() { controller?.perform("previous") }
    /// Advances to the next track or stops at the queue end from the native menu.
    @objc private func next() { controller?.perform("next") }
    /// Toggles shuffle without changing the queue's visible order or loaded stream.
    @objc private func toggleShuffle() { controller?.perform("shuffle") }
    /// Sets a recognized repeat policy from a native menu payload.
    @objc private func selectRepeat(_ sender: NSMenuItem) {
        /// Native menu values are accepted only when they represent an explicit supported policy.
        guard let value = sender.representedObject as? String,
              let mode = PlaybackSession.RepeatMode(rawValue: value) else { return }
        controller?.session.setRepeatMode(mode)
    }
    /// Toggles the detachable Classic playlist using a shortcut available while either player panel is focused.
    @objc private func togglePlaylist() { controller?.togglePlaylist() }
    /// Opens or hides the shared EQ panel from either native or Classic layouts.
    @objc private func toggleEqualizer() { controller?.toggleEqualizer() }
    /// Shows or hides the read-only current-track metadata/artwork panel in every skin.
    @objc private func toggleTrackInfo() { controller?.toggleTrackInfo() }

    /// Disables the Classic-only panel command while native layouts show their embedded queue.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleShuffle) {
            menuItem.state = controller?.session.isShuffleEnabled == true ? .on : .off
        }
        /// A repeat item is checked exactly when its fixed policy matches the live shared session.
        if menuItem.action == #selector(selectRepeat(_:)), let value = menuItem.representedObject as? String {
            menuItem.state = controller?.session.repeatMode.rawValue == value ? .on : .off
        }
        /// Queue payloads are fixed strings created above; availability follows the displayed browse selection.
        if menuItem.action == #selector(editQueue(_:)), let value = menuItem.representedObject as? String,
           let action = QueueEditAction(rawValue: value) { return controller?.canEditQueue(action) == true }
        return menuItem.action == #selector(togglePlaylist) ? controller?.classicPlaylist != nil : true
    }
    /// Dispatches a recognized native Queue menu command to the active presentation's table.
    @objc private func editQueue(_ sender: NSMenuItem) {
        /// Fixed action payload maps to an edit with dynamic bounds checking.
        guard let value = sender.representedObject as? String, let action = QueueEditAction(rawValue: value) else { return }
        controller?.editQueue(action)
    }
    /// Restores the original Retro Stereo layout.
    @objc private func retro() { changeTheme("retro") }
    /// Selects the original Quiet Space layout.
    @objc private func minimal() { changeTheme("minimal") }

    /// Applies a bundled layout by resource name and presents loading/validation failures.
    private func changeTheme(_ name: String) {
        do { try controller?.apply(ThemeCatalog.builtin(name)) }
        catch { controller?.showError(error.localizedDescription) }
    }
}
