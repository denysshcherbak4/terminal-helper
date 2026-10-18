import AppKit
import CoreServices
import Darwin

struct UpdateInstallation {
    let backup: URL
    let relaunched: Bool
}

// Runs only for an explicit update. No downloaded executable or script is invoked directly.
enum UpdateInstaller {
    static let bundleID = "io.github.denysshcherbak4.terminal-helper"
    static let manager = FileManager.default

    static func fail(_ text: String) -> UpdateFailure { .invalid(text) }

    static func wait<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void) throws -> T {
        let done = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        start { result = $0; done.signal() }
        guard done.wait(timeout: .now() + 150) == .success, let result else {
            throw fail("The update request timed out. Nothing was installed.")
        }
        return try result.get()
    }

    static func info(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw fail("An update file is missing or inaccessible.") }
        return value
    }

    static func directory(_ url: URL, owned: Bool, privateOnly: Bool = false) throws {
        let value = try info(url)
        guard value.st_mode & S_IFMT == S_IFDIR,
              !owned || value.st_uid == getuid(),
              privateOnly ? value.st_mode & 0o777 == 0o700 : value.st_mode & 0o002 == 0,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else {
            throw fail("The update location has unsafe ownership, permissions, or symbolic links.")
        }
    }

    static func targetAllowed(_ target: URL, applications: [URL]) throws {
        let parent = target.deletingLastPathComponent()
        guard target.lastPathComponent == "Terminal Helper.app",
              applications.contains(where: { $0.standardizedFileURL.path == parent.standardizedFileURL.path }) else {
            throw fail("Move Terminal Helper to ~/Applications/Terminal Helper.app in Finder once, reopen it, and repair integration. Automatic updates support that location or a user-owned writable copy in /Applications.")
        }
        try directory(parent, owned: parent.path != "/Applications")
        try directory(target, owned: true)
        guard access(parent.path, W_OK) == 0, access(target.path, W_OK) == 0 else {
            throw fail("The app is not writable by your account. Move it to your home Applications folder; no administrator password is requested.")
        }
    }

    static func command(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": manager.homeDirectoryForCurrentUser.path]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        try task.run()
        if done.wait(timeout: .now() + timeout) != .success {
            task.terminate()
            if done.wait(timeout: .now() + 2) != .success { kill(task.processIdentifier, SIGKILL); task.waitUntilExit() }
            throw fail("A macOS update operation timed out. The recovery copy was retained.")
        }
        guard task.terminationStatus == 0 else {
            throw fail("macOS refused an update operation. Check app permissions and security approval; the recovery copy was retained if installation started.")
        }
    }

    static func bundleVersion(_ app: URL) throws -> String {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let size = try info(plistURL)
        guard size.st_mode & S_IFMT == S_IFREG, size.st_size > 0, size.st_size <= 64 * 1024 else { throw fail("The app metadata is unsafe or too large.") }
        let data = try Data(contentsOf: plistURL)
        guard data.count <= 64 * 1024,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == bundleID,
              plist["CFBundleExecutable"] as? String == "TerminalHelper",
              let version = plist["CFBundleShortVersionString"] as? String,
              ReleaseVersion(version) != nil else { throw fail("The app identity or version is not valid.") }
        return version
    }

    static func validateBundle(_ app: URL, version: String) throws {
        try directory(app, owned: false)
        guard try bundleVersion(app) == version else { throw fail("The app version does not match the published update.") }
        // Our small native bundle needs no symlinks, special files, hardlinks or writable shared code.
        guard let files = manager.enumerator(at: app, includingPropertiesForKeys: nil) else { throw fail("Could not inspect the app bundle.") }
        var count = 0, bytes: Int64 = 0
        for case let file as URL in files {
            count += 1
            let value = try info(file)
            let kind = value.st_mode & S_IFMT
            bytes += max(0, value.st_size)
            guard count <= 2048, bytes <= 128 * 1024 * 1024,
                  kind == S_IFDIR || (kind == S_IFREG && value.st_nlink == 1),
                  value.st_mode & 0o022 == 0 else { throw fail("The update bundle contains unsafe or excessive files.") }
        }
        let executable = try info(app.appendingPathComponent("Contents/MacOS/TerminalHelper"))
        guard executable.st_mode & S_IFMT == S_IFREG, executable.st_mode & 0o111 != 0 else {
            throw fail("The update executable is missing.")
        }
        try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    static func privateData(_ file: URL, limit: Int) throws -> Data {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw fail("An owned update file could not be opened safely.") }
        defer { close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              value.st_uid == getuid(), value.st_mode & 0o777 == 0o600,
              value.st_nlink == 1, value.st_size > 0, value.st_size <= limit else {
            throw fail("An update file has unsafe ownership, permissions, links, or size.")
        }
        var bytes = [UInt8](repeating: 0, count: Int(value.st_size))
        var offset = 0
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), remaining) }
            guard count > 0 else { throw fail("An update file changed while being read.") }
            offset += count
        }
        return Data(bytes)
    }

    static func quarantine(_ app: URL) throws {
        let properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: "Terminal Helper",
            kLSQuarantineOriginURLKey as String: TerminalUpdates.releasesURL
        ]
        // Apply to executable as well as bundle: the mounted DMG is not the final installed file.
        for file in [app, app.appendingPathComponent("Contents/MacOS/TerminalHelper")] {
            try (file as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
            guard getxattr(file.path, "com.apple.quarantine", nil, 0, 0, 0) > 0 else {
                throw fail("macOS download security information could not be preserved.")
            }
        }
    }

    static func stopControllers(target: URL) throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0.processIdentifier != getpid() }
        guard apps.allSatisfy({ $0.bundleURL?.standardizedFileURL == target.standardizedFileURL }) else {
            throw fail("Another copy of Terminal Helper is running. Quit it before updating this copy.")
        }
        for app in apps {
            guard app.terminate() else { throw fail("Could not ask Terminal Helper to quit. Disable and Quit, then retry.") }
        }
        let deadline = Date().addingTimeInterval(10)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard apps.allSatisfy({ $0.isTerminated }) else {
            throw fail("Terminal Helper is still running. Disable and Quit, then retry.")
        }
    }

    static func reopen(_ target: URL) -> Bool {
        let done = DispatchSemaphore(value: 0)
        var launched = false
        let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = ["--updated"]
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { app, error in
            launched = app != nil && error == nil; done.signal()
        }
        let deadline = Date().addingTimeInterval(15)
        while done.wait(timeout: .now()) != .success {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return launched
    }

    // Keep the tested transaction separate from network, mounted-image and GUI boundaries.
    static func replace(staged: URL, target: URL, version: String, support: URL,
                        applications: [URL], stop: () throws -> Void,
                        checkpoint: (String) throws -> Void = { _ in }) throws {
        try targetAllowed(target, applications: applications)
        try validateBundle(staged, version: version)
        let oldVersion = try bundleVersion(target)
        guard let old = ReleaseVersion(oldVersion), let new = ReleaseVersion(version), new > old else {
            throw fail("Only a newer published version can replace the installed app.")
        }
        try directory(support, owned: true, privateOnly: true)
        let lock = support.appendingPathComponent(".integration-lock")
        guard mkdir(lock.path, 0o700) == 0 else {
            throw fail("Another integration or update operation is in progress. Resolve its lock before retrying.")
        }
        defer { rmdir(lock.path) }
        let integration = support.appendingPathComponent("integration.zsh")
        let marker = support.appendingPathComponent("app-path")
        let oldIntegrationURL = target.appendingPathComponent("Contents/Resources/Integration/terminal-helper.zsh")
        let newIntegrationURL = staged.appendingPathComponent("Contents/Resources/Integration/terminal-helper.zsh")
        var original: Data?
        if manager.fileExists(atPath: integration.path) || (try? info(integration)) != nil {
            original = try privateData(integration, limit: 262144)
            guard original == (try Data(contentsOf: oldIntegrationURL)),
                  try privateData(marker, limit: 4097) == Data((target.path + "\n").utf8) else {
                throw fail("Installed shell integration was changed or belongs to another app copy. Repair it in Settings before updating.")
            }
        }
        let replacement = try Data(contentsOf: newIntegrationURL)
        guard !replacement.isEmpty, replacement.count <= 262144 else { throw fail("Bundled shell integration is missing or too large.") }
        let integrationStage = support.appendingPathComponent(".update-integration-" + UUID().uuidString)
        if original != nil {
            try replacement.write(to: integrationStage, options: .withoutOverwriting)
            guard chmod(integrationStage.path, 0o600) == 0 else { throw fail("Could not prepare private integration.") }
        }
        var preserveIntegrationStage = false
        defer { if !preserveIntegrationStage { try? manager.removeItem(at: integrationStage) } }
        try SuggestionState(parent: support.deletingLastPathComponent()).write(enabled: false)
        try stop()
        try targetAllowed(target, applications: applications)
        guard try bundleVersion(target) == oldVersion else { throw fail("The installed app changed during this update. Retry.") }
        if let original {
            guard try privateData(integration, limit: 262144) == original else { throw fail("Shell integration changed during the update. Nothing was replaced.") }
        }
        try checkpoint("before-swap")
        // Atomic exchange leaves the old app in the private staging folder, even on interruption.
        guard renamex_np(staged.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
            throw fail("macOS could not replace this app. Its existing copy was kept; check App Management or use a writable home Applications folder.")
        }
        var integrationChanged = false
        do {
            try checkpoint("after-swap")
            try validateBundle(target, version: version)
            if original != nil {
                guard renamex_np(integrationStage.path, integration.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw fail("Could not update shell integration.")
                }
                integrationChanged = true
            }
            try checkpoint("after-integration")
        } catch {
            var restored = true
            if integrationChanged {
                restored = renamex_np(integrationStage.path, integration.path, UInt32(RENAME_SWAP)) == 0
            }
            restored = (renamex_np(staged.path, target.path, UInt32(RENAME_SWAP)) == 0) && restored
            if !restored { preserveIntegrationStage = true; throw fail("Automatic recovery could not finish. Keep suggestions Off and restore the retained backup using the update recovery guide.") }
            throw fail("The update failed and the previous app and integration were restored. Suggestions remain Off.")
        }
    }

    static func install(disk: URL, version: String, target: URL = Bundle.main.bundleURL) throws -> UpdateInstallation {
        let home = manager.homeDirectoryForCurrentUser
        let applications = [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")]
        try targetAllowed(target, applications: applications)
        let installedVersion = try bundleVersion(target)
        let checked: UpdateCheck = try wait { TerminalUpdates.check(current: installedVersion, completion: $0) }
        guard case .available(let offer) = checked, offer.version == version else {
            throw fail("The requested update is no longer the latest published version. Check for updates again.")
        }
        try directory(disk.deletingLastPathComponent(), owned: true, privateOnly: true)
        let bytes = try privateData(disk, limit: TerminalUpdates.maximumDownload)
        let manifest: Data = try wait { BoundedRequest.fetch(offer.checksumURL, 16 * 1024, $0) }
        try TerminalUpdates.verify(bytes, manifest: manifest, offer: offer)
        guard getxattr(disk.path, "com.apple.quarantine", nil, 0, 0, 0) > 0 else {
            throw fail("The downloaded disk image is missing macOS security information.")
        }
        let workspace = target.deletingLastPathComponent().appendingPathComponent(".Terminal-Helper-update-" + UUID().uuidString)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var exchanged = false
        defer { if !exchanged { try? manager.removeItem(at: workspace) } }
        let mount = workspace.appendingPathComponent("mount")
        try manager.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        // Mount a private snapshot of the verified bytes; do not reopen a mutable download path.
        let snapshot = workspace.appendingPathComponent("verified.dmg")
        try bytes.write(to: snapshot, options: .withoutOverwriting)
        guard chmod(snapshot.path, 0o600) == 0 else { throw fail("Could not protect the verified disk image.") }
        try command("/usr/bin/hdiutil", ["attach", snapshot.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, "-quiet"])
        var mounted = true
        defer {
            if mounted { try? command("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
            try? manager.removeItem(at: snapshot)
        }
        let candidate = mount.appendingPathComponent("Terminal Helper.app")
        try validateBundle(candidate, version: version)
        let staged = workspace.appendingPathComponent("Terminal Helper.app")
        try manager.copyItem(at: candidate, to: staged)
        try validateBundle(staged, version: version)
        try quarantine(staged)
        try command("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
        mounted = false
        try manager.removeItem(at: mount)
        let support = home.appendingPathComponent("Library/Application Support/Terminal Helper")
        try SuggestionState().write(enabled: false)
        try Data("Previous Terminal Helper app retained here. Disable and Quit before restoring it to the same Applications folder. Repair shell integration in Settings and restart shells afterward. Do not remove quarantine or change macOS security settings. See Docs/UPDATES.md in the repository.\n".utf8).write(to: workspace.appendingPathComponent("RECOVERY.txt"), options: .withoutOverwriting)
        do {
            try replace(staged: staged, target: target, version: version, support: support,
                        applications: applications, stop: { try stopControllers(target: target) })
            exchanged = true
        } catch {
            // Retain both copies if a recovery error left the target uncertain.
            if (try? bundleVersion(target)) != installedVersion || error.localizedDescription.contains("Automatic recovery") { exchanged = true }
            _ = reopen(target)
            throw error
        }
        return UpdateInstallation(backup: staged, relaunched: reopen(target))
    }
}
