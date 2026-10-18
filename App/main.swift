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
    private var settingsIntegration: NSTextField?
    private var settingsOperation: NSTextField?
    private var installButton: NSButton?
    private var uninstallButton: NSButton?
    private var setupMenuItem: NSMenuItem?
    private var helpWindow: NSWindow?
    private var operationStatus = ""
    private var worker: IntegrationWorker?
    private var lifecycleChild: pid_t?
    private var configurationDirectory = UserDefaults.standard.string(forKey: "ShellConfigurationDirectory").map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--appearance"), index + 1 < CommandLine.arguments.count {
            let value = CommandLine.arguments[index + 1]
            guard value == "light" || value == "dark" else { fputs("Appearance must be light or dark.\n", stderr); exit(1) }
            NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.denysshcherbak4.terminal-helper").count > 1 {
            NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = terminalGlyph(size: 22)
        item.button?.setAccessibilityLabel("Terminal Helper")
        item.button?.toolTip = "Terminal Helper — suggestions On or Off"
        menu.delegate = self; menu.autoenablesItems = false
        let heading = NSMenuItem(title: "Terminal Helper", action: nil, keyEquivalent: "")
        heading.isEnabled = false; status.isEnabled = false; integration.isEnabled = false
        menu.addItem(heading)
        menu.addItem(status)
        toggle.target = self; menu.addItem(toggle)
        menu.addItem(integration)
        let setup = NSMenuItem(title: "Install shell integration…", action: #selector(installIntegration), keyEquivalent: "")
        setup.target = self; setupMenuItem = setup; menu.addItem(setup)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",")
        add("Help", action: #selector(showHelp))
        menu.addItem(.separator())
        add("Disable and Quit", action: #selector(disableAndQuit), key: "q")
        item.menu = menu
        let mainMenu = NSMenu()
        let appEntry = NSMenuItem(); mainMenu.addItem(appEntry)
        let applicationMenu = NSMenu(title: "Terminal Helper"); appEntry.submenu = applicationMenu
        for (title, action, key) in [("Settings…", #selector(showSettings), ","), ("Help", #selector(showHelp), ""), ("Disable and Quit", #selector(disableAndQuit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self; applicationMenu.addItem(entry)
        }
        NSApp.mainMenu = mainMenu
        refresh()
        if !integrationInstalled && CommandLine.arguments.count == 1 { showSettings() }
        if lifecycleRoot != nil {
            DispatchQueue.main.async {
                if CommandLine.arguments.contains("--settings-self-test") { self.settingsSelfTest() }
                else { self.lifecycleTest() }
            }
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
        let path = (lifecycleRoot?.appendingPathComponent("Terminal Helper/integration.zsh") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Terminal Helper/integration.zsh")).path
        var st = stat()
        return lstat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFREG && st.st_uid == getuid() && st.st_mode & 0o022 == 0
    }
    private func refresh() {
        let enabled = state.enabled()
        status.title = "Suggestions: \(enabled ? "On" : "Off")"
        toggle.state = enabled ? .on : .off
        toggle.isEnabled = enabled || (worker == nil && (integrationInstalled || CommandLine.arguments.contains("--lifecycle-test")))
        setupMenuItem?.isEnabled = worker == nil
        setupMenuItem?.title = integrationInstalled ? "Repair shell integration…" : "Install shell integration…"
        integration.title = integrationInstalled ? "Integration file present; restart shells" : "Shell integration: not installed"
        item.button?.setAccessibilityValue(enabled ? "On" : "Off")
        settingsToggle?.state = toggle.state
        settingsToggle?.isEnabled = toggle.isEnabled
        settingsStatus?.stringValue = status.title
        settingsIntegration?.stringValue = integration.title
        settingsOperation?.stringValue = operationStatus
        settingsOperation?.isHidden = operationStatus.isEmpty
        installButton?.title = integrationInstalled ? "Repair shell integration…" : "Install shell integration…"
        installButton?.isEnabled = worker == nil
        uninstallButton?.isEnabled = integrationInstalled && worker == nil
    }
    @objc private func changeEnabled() {
        if !state.enabled(), !CommandLine.arguments.contains("--lifecycle-test"), !integrationInstalled || worker != nil {
            operationStatus = worker == nil ? "Install shell integration before enabling suggestions." : "Wait for shell integration to finish."
            showSettings(); return
        }
        do { try state.write(enabled: !state.enabled()); operationStatus = ""; refresh() }
        catch { report("Could not change suggestions", detail: String(describing: error)) }
    }
    private func settingsSelfTest() {
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("Settings test failed: \(message)\n", stderr); exit(1) }
        }
        showSettings()
        check(!state.enabled() && !toggle.isEnabled && settingsToggle?.isEnabled == false, "Enable must require integration")
        check(installButton?.isEnabled == true && uninstallButton?.isEnabled == false, "setup actions")
        changeEnabled()
        check(!state.enabled() && !operationStatus.isEmpty, "missing integration leaves Off and explains setup")
        guard let root = lifecycleRoot else { exit(1) }
        do {
            try state.write(enabled: false)
            let fixture = root.appendingPathComponent("Terminal Helper/integration.zsh")
            try Data("# test fixture only\n".utf8).write(to: fixture)
            chmod(fixture.path, 0o600)
            refresh()
            check(toggle.isEnabled && settingsToggle?.isEnabled == true && uninstallButton?.isEnabled == true, "installed controls")
            changeEnabled()
            check(state.enabled() && settingsToggle?.state == .on && settingsStatus?.stringValue == "Suggestions: On", "On state and label")
            changeEnabled()
            check(!state.enabled() && settingsToggle?.state == .off && settingsStatus?.stringValue == "Suggestions: Off", "Off state and label")
            try FileManager.default.removeItem(at: root)
        } catch { fputs("Settings test failed: isolated fixture could not be updated.\n", stderr); exit(1) }
        print("PASS native Settings: setup required, action availability, On/Off controls and status labels")
        NSApp.terminate(nil)
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 470), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Terminal Helper Settings"; w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 460, height: 450)
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: w.contentView!.bottomAnchor, constant: -24)])
            let title = NSTextField(labelWithString: "Helpful terminal suggestions")
            title.font = .systemFont(ofSize: 17, weight: .semibold); stack.addArrangedSubview(title)
            let statusLabel = NSTextField(labelWithString: "Suggestions: Off")
            stack.addArrangedSubview(statusLabel); settingsStatus = statusLabel
            func paragraph(_ text: String) -> NSTextField {
                let label = NSTextField(wrappingLabelWithString: text)
                label.font = .systemFont(ofSize: NSFont.systemFontSize)
                stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                return label
            }
            settingsIntegration = paragraph("Shell integration: not installed")
            _ = paragraph("1. Install shell integration.\n2. Open a new terminal window.\n3. Enable suggestions, then press Tab in zsh.")
            let install = NSButton(title: "Install shell integration…", target: self, action: #selector(installIntegration))
            install.setAccessibilityLabel("Install or repair shell integration")
            stack.addArrangedSubview(install); installButton = install
            let button = NSButton(checkboxWithTitle: "Enable suggestions", target: self, action: #selector(changeEnabled))
            button.setAccessibilityLabel("Enable suggestions")
            button.setAccessibilityHelp("Install shell integration first. Off is checked at the next completion or acceptance.")
            stack.addArrangedSubview(button); settingsToggle = button
            _ = paragraph("Off takes effect at the next completion or acceptance. The menu-bar app stays open while suggestions are disabled.")
            settingsOperation = paragraph("")
            settingsOperation?.setAccessibilityLabel("Integration result")
            let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 12
            let help = NSButton(title: "Help", target: self, action: #selector(showHelp)); actions.addArrangedSubview(help)
            let uninstall = NSButton(title: "Uninstall shell integration…", target: self, action: #selector(uninstallIntegration))
            actions.addArrangedSubview(uninstall); uninstallButton = uninstall
            stack.addArrangedSubview(actions)
            window = w; w.center()
        }
        refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func report(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func showHelp() {
        if helpWindow == nil {
            guard let url = Bundle.main.url(forResource: "Help", withExtension: "txt", subdirectory: "Docs"),
                  let help = try? String(contentsOf: url, encoding: .utf8) else {
                report("Help unavailable", detail: "Reinstall a complete app build to restore offline documentation."); return
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Terminal Helper Help"; w.isReleasedWhenClosed = false; w.contentMinSize = NSSize(width: 420, height: 320)
            let scroll = NSScrollView(frame: w.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.contentView.bounds)
            text.isEditable = false; text.isRichText = false; text.isSelectable = true
            text.font = .systemFont(ofSize: NSFont.systemFontSize)
            text.textColor = .textColor; text.backgroundColor = .textBackgroundColor
            text.textContainerInset = NSSize(width: 20, height: 20)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            text.string = help; text.setAccessibilityLabel("Terminal Helper offline help")
            scroll.documentView = text; w.contentView!.addSubview(scroll)
            helpWindow = w; w.center()
        }
        helpWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
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
        let choice = NSAlert()
        choice.messageText = "Choose your shell configuration"
        choice.informativeText = "Use your home folder for a standard zsh setup. If you configured ZDOTDIR, choose that folder instead. Current folder: " + configurationDirectory.path
        choice.addButton(withTitle: configurationDirectory == FileManager.default.homeDirectoryForCurrentUser ? "Use Home folder" : "Use selected folder")
        choice.addButton(withTitle: "Choose another folder…"); choice.addButton(withTitle: "Cancel")
        switch choice.runModal() {
        case .alertFirstButtonReturn: break
        case .alertSecondButtonReturn:
            let chooser = NSOpenPanel()
            chooser.title = "Choose your ZDOTDIR folder"
            chooser.message = "Select the folder containing your .zshrc. You do not need to select the hidden file."
            chooser.prompt = "Use this folder"
            chooser.canChooseDirectories = true; chooser.canChooseFiles = false; chooser.allowsMultipleSelection = false
            chooser.directoryURL = configurationDirectory
            guard chooser.runModal() == .OK, let selected = chooser.url else { return }
            configurationDirectory = selected
        default: return
        }
        let environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "ZDOTDIR": configurationDirectory.path]
        do {
            operationStatus = operation == "install" ? "Installing shell integration…" : "Uninstalling shell integration…"
            worker = try IntegrationWorker(arguments: ["-f", script.path], environment: environment) { status in
                self.worker = nil
                if self.quitting { self.finishQuit(); return }
                self.operationStatus = status == 0 ? (operation == "install" ? "Installed. Open a new terminal window, then enable suggestions." : "Uninstalled. Restart open terminal shells.") : "Integration update failed. Check ownership and permissions; see Help."
                if status == 0 { UserDefaults.standard.set(self.configurationDirectory.path, forKey: "ShellConfigurationDirectory") }
                self.refresh()
                self.report(status == 0 ? "Shell integration updated" : "Shell integration could not be updated", detail: status == 0 ? "Open a new terminal shell to use the updated configuration." : "Check that your shell configuration and Terminal Helper folder belong to you and are writable. See the troubleshooting guide; no configuration is overwritten.")
            }
            refresh()
        } catch {
            worker = nil; operationStatus = "The bundled installer could not start. Reinstall a complete app build."
            refresh(); report("Could not run installer", detail: operationStatus)
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    do { try stateSelfTest(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
let application = NSApplication.shared
let lifecycleRoot = (CommandLine.arguments.contains("--lifecycle-test") || CommandLine.arguments.contains("--settings-self-test")) ? FileManager.default.temporaryDirectory.appendingPathComponent("TerminalHelper-lifecycle-" + UUID().uuidString) : nil
let controller = Controller(lifecycleRoot: lifecycleRoot)
application.delegate = controller
application.run()
