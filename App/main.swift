import AppKit

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state: SuggestionState
    private let lifecycleRoot: URL?
    private var quitting = false
    init(lifecycleRoot: URL? = nil) {
        self.lifecycleRoot = lifecycleRoot
        self.state = lifecycleRoot.map { SuggestionState(parent: $0) } ?? SuggestionState()
        super.init()
    }
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "Suggestions: Off", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Enable suggestions", action: #selector(changeEnabled), keyEquivalent: "")
    private let integration = NSMenuItem(title: "Shell integration: not installed", action: nil, keyEquivalent: "")
    private var window: NSWindow?
    private var settingsToggle: NSButton?
    private var settingsStatus: NSTextField?
    private var worker: IntegrationWorker?
    private var lifecycleChild: pid_t?
    private var configurationDirectory = FileManager.default.homeDirectoryForCurrentUser

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
        if lifecycleRoot != nil {
            DispatchQueue.main.async { self.lifecycleTest() }
        }
        if CommandLine.arguments.contains("--smoke-test") { showSettings() }
        if let position = CommandLine.arguments.firstIndex(where: { $0 == "--ui-smoke-test" || $0 == "--render-preview" }), position + 1 < CommandLine.arguments.count {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = self.window?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fputs("Native render failed: cannot capture Settings view.\n", stderr); exit(1)
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                    fputs("Native render failed: cannot allocate output bitmap.\n", stderr); exit(1)
                }
                guard let context = NSGraphicsContext(bitmapImageRep: opaque) else {
                    fputs("Native render failed: cannot create bitmap graphics context.\n", stderr); exit(1)
                }
                guard let captured = rep.cgImage else {
                    fputs("Native render failed: cannot resolve captured image.\n", stderr); exit(1)
                }
                let graphics = context.cgContext
                let bounds = CGRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
                view.effectiveAppearance.performAsCurrentDrawingAppearance {
                    let background = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .white
                    graphics.setFillColor(background.cgColor)
                    graphics.fill(bounds)
                }
                graphics.draw(captured, in: bounds)
                graphics.flush()
                guard let pixels = opaque.bitmapData, opaque.bitsPerPixel == 32 else {
                    fputs("Native render failed: output pixel storage is unavailable.\n", stderr); exit(1)
                }
                var varied = false
                for y in 0..<opaque.pixelsHigh {
                    for x in 0..<opaque.pixelsWide {
                        let offset = y * opaque.bytesPerRow + x * 4
                        guard pixels[offset + 3] == 255 else {
                            fputs("Native render failed: transparent output pixel.\n", stderr); exit(1)
                        }
                        if pixels[offset] != pixels[0] || pixels[offset + 1] != pixels[1] || pixels[offset + 2] != pixels[2] { varied = true }
                    }
                }
                guard varied else {
                    fputs("Native render failed: blank output image.\n", stderr); exit(1)
                }
                do {
                    guard let png = opaque.representation(using: .png, properties: [:]) else {
                        fputs("Native render failed: cannot encode PNG.\n", stderr); exit(1)
                    }
                    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[position + 1]))
                    print("PASS native Settings render"); NSApp.terminate(nil)
                } catch { fputs("Native render failed: cannot write PNG artifact.\n", stderr); exit(1) }
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
    private func lifecycleTest() {
        guard !state.enabled() else { exit(1) }
        changeEnabled()
        guard state.enabled(), toggle.state == .on else { exit(1) }
        changeEnabled()
        guard !state.enabled(), toggle.state == .off else { exit(1) }
        changeEnabled()
        guard state.enabled(), toggle.state == .on else { exit(1) }
        guard let root = lifecycleRoot else { exit(1) }
        let pidFile = root.appendingPathComponent("child-pid")
        // Fixed test-only program; no command buffer or discovered file is evaluated.
        let program = "trap 'wait \"$child\"; exit 0' TERM; /bin/sleep 30 & child=$!; print -r -- \"$child\" > \"$1\"; wait \"$child\""
        do {
            worker = try IntegrationWorker(arguments: ["-f", "-c", program, "lifecycle-test", pidFile.path], environment: ["PATH": "/usr/bin:/bin"]) { _ in
                self.worker = nil
                guard self.quitting else { fputs("Lifecycle failed: worker exited before Quit.\n", stderr); exit(1) }
                self.finishQuit()
            }
            waitForLifecycleChild(attempts: 100)
        } catch { fputs("Lifecycle failed: cannot start owned test worker.\n", stderr); exit(1) }
    }
    private func waitForLifecycleChild(attempts: Int) {
        if let root = lifecycleRoot,
           let text = try? String(contentsOf: root.appendingPathComponent("child-pid"), encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
            lifecycleChild = pid
            disableAndQuit()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForLifecycleChild(attempts: attempts - 1) }
        } else {
            worker?.terminate()
            fputs("Lifecycle failed: owned test child did not start.\n", stderr); exit(1)
        }
    }
    private func finishQuit() {
        if let root = lifecycleRoot {
            guard !state.enabled() else { fputs("Lifecycle failed: Quit left state On.\n", stderr); exit(1) }
            if let child = lifecycleChild {
                guard kill(child, 0) == -1, errno == ESRCH else {
                    fputs("Lifecycle failed: owned child survived Quit.\n", stderr); exit(1)
                }
            }
            do { try FileManager.default.removeItem(at: root) }
            catch { fputs("Lifecycle failed: temporary state cleanup failed.\n", stderr); exit(1) }
            print("PASS controller lifecycle: On, Off, re-enable, Disable and Quit writes Off and terminates owned worker group")
        }
        NSApp.terminate(nil)
    }
    @objc private func disableAndQuit() {
        guard !quitting else { return }
        do {
            try state.write(enabled: false)
            quitting = true
            if let worker = worker, worker.isRunning { worker.terminate() }
            else { finishQuit() }
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
            label.font = .systemFont(ofSize: 13); stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; settingsStatus = label
            let button = NSButton(checkboxWithTitle: "Enable suggestions", target: self, action: #selector(changeEnabled))
            button.setAccessibilityLabel("Enable suggestions"); stack.addArrangedSubview(button); settingsToggle = button
            let info = NSTextField(wrappingLabelWithString: "Use Tab in an integrated interactive zsh. Off takes effect at the next completion or acceptance. The menu-bar app stays resident while Off.")
            info.font = .systemFont(ofSize: 13); stack.addArrangedSubview(info)
            info.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
        report("Terminal Helper", detail: "1. Install shell integration in Settings. Choose the folder containing your .zshrc (your ZDOTDIR, or home folder), then open a new zsh session.\n2. Enable suggestions from the menu bar.\n3. Tab opens completion; arrows select, Enter accepts text, and Escape cancels. Execute separately with Enter after the menu closes.\n\nOff and Disable and Quit are checked at the next completion or acceptance. Existing shell completion definitions run with your user privileges.\n\nUninstall integration from Settings using the same configuration folder before deleting the app. Documentation is included in the app's Resources/Docs folder. No history, command buffers, or filenames are logged.")
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
        let chooser = NSOpenPanel()
        chooser.title = "Choose your shell configuration folder"
        chooser.message = "Select the folder containing your .zshrc: your ZDOTDIR if configured, otherwise your home folder. Hidden files do not need to be selected."
        chooser.prompt = operation == "install" ? "Install here" : "Uninstall here"
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false; chooser.allowsMultipleSelection = false
        chooser.directoryURL = configurationDirectory
        guard chooser.runModal() == .OK, let selected = chooser.url else { return }
        configurationDirectory = selected
        let environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "ZDOTDIR": configurationDirectory.path]
        do {
            worker = try IntegrationWorker(arguments: ["-f", script.path], environment: environment) { status in
                self.worker = nil
                if self.quitting { self.finishQuit(); return }
                self.refresh()
                self.report(status == 0 ? "Shell integration updated" : "Shell integration could not be updated", detail: status == 0 ? "Open a new terminal shell to use the updated configuration." : "Check that your shell configuration and Terminal Helper folder belong to you and are writable. See the troubleshooting guide; no configuration is overwritten.")
            }
        } catch { worker = nil; report("Could not run installer", detail: "The bundled installer could not start.") }
    }
}

if CommandLine.arguments.contains("--self-test") {
    do { try stateSelfTest(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
let application = NSApplication.shared
let lifecycleRoot = CommandLine.arguments.contains("--lifecycle-test") ? FileManager.default.temporaryDirectory.appendingPathComponent("TerminalHelper-lifecycle-" + UUID().uuidString) : nil
let controller = Controller(lifecycleRoot: lifecycleRoot)
application.delegate = controller
application.run()
