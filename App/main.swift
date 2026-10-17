import AppKit

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = SuggestionState()
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "Suggestions: Off", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Enable suggestions", action: #selector(changeEnabled), keyEquivalent: "")
    private let integration = NSMenuItem(title: "Shell integration: not installed", action: nil, keyEquivalent: "")
    private var window: NSWindow?
    private var settingsToggle: NSButton?
    private var settingsStatus: NSTextField?
    private var worker: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.denysshcherbak4.terminal-helper").count > 1 {
            NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = terminalGlyph(size: 22)
        item.button?.setAccessibilityLabel("Terminal Helper")
        item.button?.toolTip = "Terminal Helper — suggestions On or Off"
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Terminal Helper", action: nil, keyEquivalent: ""))
        menu.addItem(status)
        toggle.target = self; menu.addItem(toggle)
        menu.addItem(integration)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",")
        add("Help", action: #selector(showHelp))
        menu.addItem(.separator())
        add("Disable and Quit", action: #selector(disableAndQuit), key: "q")
        item.menu = menu
        refresh()
        if CommandLine.arguments.contains("--smoke-test") { showSettings() }
        if let position = CommandLine.arguments.firstIndex(where: { $0 == "--ui-smoke-test" || $0 == "--render-preview" }), position + 1 < CommandLine.arguments.count {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = self.window?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: rep)
                do {
                    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[position + 1]))
                    print("PASS native Settings render"); NSApp.terminate(nil)
                } catch { exit(1) }
            }
        }
    }
    private func add(_ title: String, action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self; menu.addItem(entry)
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    private var integrationInstalled: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Terminal Helper/integration.zsh").path
        var st = stat()
        return lstat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFREG && st.st_uid == getuid() && st.st_mode & 0o022 == 0
    }
    private func refresh() {
        let enabled = state.enabled()
        status.title = "Suggestions: \(enabled ? "On" : "Off")"
        toggle.state = enabled ? .on : .off
        integration.title = integrationInstalled ? "Integration file present; restart shells" : "Shell integration: not installed"
        item.button?.setAccessibilityValue(enabled ? "On" : "Off")
        settingsToggle?.state = toggle.state
        settingsStatus?.stringValue = status.title + "\n" + integration.title
    }
    @objc private func changeEnabled() {
        do { try state.write(enabled: !state.enabled()); refresh() }
        catch { report("Could not change suggestions", detail: String(describing: error)) }
    }
    @objc private func disableAndQuit() {
        do {
            try state.write(enabled: false)
            worker?.terminate()
            NSApp.terminate(nil)
        } catch { report("Could not disable safely", detail: "Terminal Helper will stay open. " + String(describing: error)) }
    }
    @objc private func showSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Terminal Helper Settings"; w.isReleasedWhenClosed = false
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 24)])
            let title = NSTextField(labelWithString: "Helpful terminal suggestions")
            title.font = .systemFont(ofSize: 17, weight: .semibold); stack.addArrangedSubview(title)
            let label = NSTextField(wrappingLabelWithString: "Suggestions: Off\nShell integration: not installed")
            label.font = .systemFont(ofSize: 13); stack.addArrangedSubview(label); settingsStatus = label
            let button = NSButton(checkboxWithTitle: "Enable suggestions", target: self, action: #selector(changeEnabled))
            button.setAccessibilityLabel("Enable suggestions"); stack.addArrangedSubview(button); settingsToggle = button
            let info = NSTextField(wrappingLabelWithString: "Use Tab in an integrated interactive zsh. Off takes effect at the next completion or acceptance. The menu-bar app stays resident while Off.")
            info.font = .systemFont(ofSize: 13); stack.addArrangedSubview(info)
            let install = NSButton(title: "Install or repair shell integration…", target: self, action: #selector(installIntegration))
            stack.addArrangedSubview(install)
            let uninstall = NSButton(title: "Uninstall shell integration…", target: self, action: #selector(uninstallIntegration))
            stack.addArrangedSubview(uninstall)
            let help = NSButton(title: "Help", target: self, action: #selector(showHelp)); stack.addArrangedSubview(help)
            window = w; w.center()
        }
        refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func report(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func showHelp() {
        report("Terminal Helper", detail: "1. Install shell integration in Settings, then open a new zsh session.\n2. Enable suggestions from the menu bar.\n3. Tab opens completion; arrows select, Enter accepts text, and Escape cancels. Execute separately with Enter after the menu closes.\n\nOff and Disable and Quit are checked at the next completion or acceptance. Existing shell completion definitions run with your user privileges.\n\nUninstall integration from Settings before deleting the app. Documentation is included in the app's Resources/Docs folder. No history, command buffers, or filenames are logged.")
    }
    @objc private func installIntegration() { runIntegration("install") }
    @objc private func uninstallIntegration() {
        let alert = NSAlert(); alert.messageText = "Uninstall shell integration?"
        alert.informativeText = "Suggestions will be disabled and the owned shell configuration block and integration files removed. Open shells must be restarted."
        alert.addButton(withTitle: "Uninstall"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try state.write(enabled: false) } catch { report("Could not disable safely", detail: String(describing: error)); return }
        runIntegration("uninstall")
    }
    private func runIntegration(_ operation: String) {
        guard worker == nil else { return }
        guard let script = Bundle.main.url(forResource: operation, withExtension: "zsh", subdirectory: "Integration") else {
            report("Integration unavailable", detail: "Reinstall this app from a complete build."); return
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = [script.path]
        // Installer output may include private paths; never forward it into app logs.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "ZDOTDIR": ProcessInfo.processInfo.environment["ZDOTDIR"] ?? FileManager.default.homeDirectoryForCurrentUser.path]
        worker = process
        process.terminationHandler = { completed in
            DispatchQueue.main.async {
                self.worker = nil; self.refresh()
                self.report(completed.terminationStatus == 0 ? "Shell integration updated" : "Shell integration could not be updated", detail: completed.terminationStatus == 0 ? "Open a new terminal shell to use the updated configuration." : "Check that your shell configuration and Terminal Helper folder belong to you and are writable. See the troubleshooting guide; no configuration is overwritten.")
            }
        }
        do { try process.run() } catch { worker = nil; report("Could not run installer", detail: "The bundled installer could not start.") }
    }
}

if CommandLine.arguments.contains("--self-test") {
    do { try stateSelfTest(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
let application = NSApplication.shared
let controller = Controller()
application.delegate = controller
application.run()
