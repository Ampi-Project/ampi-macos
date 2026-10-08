// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Creates the native player and connects application lifecycle and menu commands.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained player controller, created after the default layout loads successfully.
    private var controller: PlayerWindowController?
    /// Native audio output retained for the lifetime of the application delegate.
    private let backend = NativeAudioBackend()

    /// Starts the default player and menus, or displays a fatal startup error and exits.
    /// - Parameter notification: AppKit launch event; no payload is needed here.
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            /// Session shared by the window and native completion handler.
            let session = PlaybackSession(backend: backend)
            /// Success is the native completion result; the weak session receives auto-advance/errors.
            backend.onFinish = { [weak session] success in session?.finished(successfully: success) }
            controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            installMenus()
            controller?.showWindow(nil)
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
    func application(_ application: NSApplication, open urls: [URL]) { controller?.open(urls) }

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

        /// Built-in layout choices, including the default-layout recovery command.
        let themes = submenu("Themes", in: main)
        add("Restore Default / Retro Stereo", to: themes, action: #selector(retro), key: "0", modifiers: [.command, .shift])
        add("Quiet Space", to: themes, action: #selector(minimal), key: "1", modifiers: [.command, .shift])

        /// Native window commands also registered as AppKit's windows menu.
        let windowMenu = submenu("Window", in: main)
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
