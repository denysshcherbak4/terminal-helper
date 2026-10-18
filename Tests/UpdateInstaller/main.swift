import Foundation
import CryptoKit
import Darwin

let fm = FileManager.default
let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("TH updater дані tests " + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: root) }
var checks = 0
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    if try !value() { throw UpdateFailure.invalid("FAIL installer: " + message) }
}
func rejects(_ message: String, _ action: () throws -> Void) throws {
    do { try action() } catch { checks += 1; return }
    throw UpdateFailure.invalid("FAIL accepted: " + message)
}
func makeApp(_ url: URL, version: String, integration: String, identifier: String = UpdateInstaller.bundleID) throws {
    let contents = url.appendingPathComponent("Contents")
    try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: contents.appendingPathComponent("Resources/Integration"), withIntermediateDirectories: true)
    try fm.copyItem(atPath: "/usr/bin/true", toPath: contents.appendingPathComponent("MacOS/TerminalHelper").path)
    let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "TerminalHelper",
        "CFBundleName": "Terminal Helper", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try Data(integration.utf8).write(to: contents.appendingPathComponent("Resources/Integration/terminal-helper.zsh"))
    try UpdateInstaller.command("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
}
struct Fixture {
    let directory: URL
    let applications: URL
    let target: URL
    let stage: URL
    let support: URL
    var integration: URL { support.appendingPathComponent("integration.zsh") }
    init(newVersion: String = "0.4.0", installed: Bool = true) throws {
        directory = root.appendingPathComponent(UUID().uuidString)
        applications = directory.appendingPathComponent("Applications")
        target = applications.appendingPathComponent("Terminal Helper.app")
        stage = applications.appendingPathComponent(".stage/Terminal Helper.app")
        support = directory.appendingPathComponent("Support/Terminal Helper")
        for folder in [applications, stage.deletingLastPathComponent(), support] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try makeApp(target, version: "0.3.0", integration: "# old exact data\n")
        try makeApp(stage, version: newVersion, integration: "# new data; never sourced\ntouch SHOULD_NOT_EXIST\n")
        if installed {
            try Data("# old exact data\n".utf8).write(to: integration)
            try Data((target.path + "\n").utf8).write(to: support.appendingPathComponent("app-path"))
            chmod(integration.path, 0o600); chmod(support.appendingPathComponent("app-path").path, 0o600)
        }
        try SuggestionState(parent: support.deletingLastPathComponent()).write(enabled: true)
        try Data("unrelated settings\n".utf8).write(to: directory.appendingPathComponent(".zshrc"))
    }
    func replace(stop: () throws -> Void = {}, checkpoint: (String) throws -> Void = { _ in }) throws {
        try UpdateInstaller.replace(staged: stage, target: target, version: "0.4.0", support: support,
                                    applications: [applications], stop: stop, checkpoint: checkpoint)
    }
    func oldIntact() throws {
        try expect(UpdateInstaller.bundleVersion(target) == "0.3.0", "previous app retained/restored")
        try expect(Data(contentsOf: integration) == Data("# old exact data\n".utf8), "previous integration retained/restored")
    }
}
do {
    let f = try Fixture()
    var stopped = false
    try f.replace(stop: { stopped = true })
    try expect(stopped, "controller shutdown boundary reached")
    try expect(UpdateInstaller.bundleVersion(f.target) == "0.4.0", "new app installed")
    try expect(UpdateInstaller.bundleVersion(f.stage) == "0.3.0", "previous app retained in staging")
    try expect(Data(contentsOf: f.integration) == Data("# new data; never sourced\ntouch SHOULD_NOT_EXIST\n".utf8), "new integration data installed")
    try expect(!SuggestionState(parent: f.support.deletingLastPathComponent()).enabled(), "update leaves Off")
    try expect(Data(contentsOf: f.directory.appendingPathComponent(".zshrc")) == Data("unrelated settings\n".utf8), "shell configuration untouched")
    try expect(!fm.fileExists(atPath: "SHOULD_NOT_EXIST"), "downloaded shell data never executed")
    try expect(!fm.fileExists(atPath: f.support.appendingPathComponent(".integration-lock").path), "owned lock released")
}
for point in ["before-swap", "after-swap", "after-integration"] {
    let f = try Fixture()
    try rejects("injected failure " + point) {
        try f.replace(checkpoint: { if $0 == point { throw UpdateFailure.invalid("injected") } })
    }
    try f.oldIntact()
    try expect(!SuggestionState(parent: f.support.deletingLastPathComponent()).enabled(), "failure leaves Off after shutdown boundary")
}
do {
    let f = try Fixture()
    try rejects("concurrent integration edit") {
        try f.replace(stop: { try Data("# user change\n".utf8).write(to: f.integration) })
    }
    try expect(UpdateInstaller.bundleVersion(f.target) == "0.3.0", "concurrent change leaves app intact")
    try expect(Data(contentsOf: f.integration) == Data("# user change\n".utf8), "concurrent user change preserved")
}
do {
    let f = try Fixture()
    try fm.createDirectory(at: f.support.appendingPathComponent(".integration-lock"), withIntermediateDirectories: false)
    try rejects("busy installer lock") { try f.replace() }
    try f.oldIntact()
    try expect(SuggestionState(parent: f.support.deletingLastPathComponent()).enabled(), "busy lock refuses before disabling")
}
for mode in ["changed-integration", "wrong-app-path", "integration-symlink", "bundle-symlink", "bundle-hardlink", "bundle-writable", "tampered-signature", "wrong-identity", "noncanonical-target", "parent-symlink"] {
    let f = try Fixture()
    switch mode {
    case "changed-integration": try Data("# custom\n".utf8).write(to: f.integration)
    case "wrong-app-path": try Data("/another/app.app\n".utf8).write(to: f.support.appendingPathComponent("app-path"))
    case "integration-symlink":
        try fm.removeItem(at: f.integration)
        try fm.createSymbolicLink(at: f.integration, withDestinationURL: f.directory.appendingPathComponent(".zshrc"))
    case "bundle-symlink": try fm.createSymbolicLink(at: f.stage.appendingPathComponent("escape"), withDestinationURL: f.directory)
    case "bundle-hardlink":
        let source = f.stage.appendingPathComponent("Contents/Resources/Integration/terminal-helper.zsh")
        try fm.linkItem(at: source, to: f.stage.appendingPathComponent("linked-data"))
    case "bundle-writable": chmod(f.stage.appendingPathComponent("Contents/Info.plist").path, 0o666)
    case "tampered-signature": try Data("# tampered\n".utf8).write(to: f.stage.appendingPathComponent("Contents/Resources/Integration/terminal-helper.zsh"))
    case "wrong-identity":
        try fm.removeItem(at: f.stage); try makeApp(f.stage, version: "0.4.0", integration: "# new\n", identifier: "other.app")
    case "noncanonical-target":
        try rejects(mode) { try UpdateInstaller.targetAllowed(f.target, applications: [root]) }; continue
    case "parent-symlink":
        let alias = f.directory.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: f.applications)
        try rejects(mode) { try UpdateInstaller.targetAllowed(alias.appendingPathComponent("Terminal Helper.app"), applications: [alias]) }; continue
    default: break
    }
    try rejects(mode) { try f.replace() }
    try expect(UpdateInstaller.bundleVersion(f.target) == "0.3.0", "refused update leaves old app: " + mode)
}
for version in ["0.3.0", "0.2.0", "0.5.0"] {
    let f = try Fixture(newVersion: version)
    try rejects("same/downgrade/wrong offered version") { try f.replace() }
    try f.oldIntact()
}
do {
    let f = try Fixture(installed: false)
    try f.replace()
    try expect(!fm.fileExists(atPath: f.integration.path), "no implicit integration installation")
}
do {
    let f = try Fixture()
    try UpdateInstaller.quarantine(f.stage)
    try expect(getxattr(f.stage.path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "bundle quarantine")
    try expect(getxattr(f.stage.appendingPathComponent("Contents/MacOS/TerminalHelper").path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "executable quarantine")
    try f.replace()
    try expect(getxattr(f.target.path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "installed quarantine survives exchange")
}

// Full image mount/copy/verification path, restricted to a disposable runner's empty user folders.
do {
    let home = fm.homeDirectoryForCurrentUser
    let apps = home.appendingPathComponent("Applications")
    let target = apps.appendingPathComponent("Terminal Helper.app")
    let support = home.appendingPathComponent("Library/Application Support/Terminal Helper")
    guard !fm.fileExists(atPath: target.path), !fm.fileExists(atPath: support.path) else {
        throw UpdateFailure.invalid("Full installer fixture requires an empty disposable runner; refusing existing installation.")
    }
    try fm.createDirectory(at: apps, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try makeApp(target, version: "0.3.0", integration: "# original\n")
    defer { try? fm.removeItem(at: target); try? fm.removeItem(at: support) }
    let imageSource = root.appendingPathComponent("disk-source")
    try fm.createDirectory(at: imageSource, withIntermediateDirectories: false)
    try makeApp(imageSource.appendingPathComponent("Terminal Helper.app"), version: "0.4.0", integration: "# updated fixture; data only\n")
    let image = root.appendingPathComponent("fixture.dmg")
    try UpdateInstaller.command("/usr/bin/hdiutil", ["create", "-srcfolder", imageSource.path, "-format", "UDZO", image.path, "-quiet"])
    let diskBytes = try Data(contentsOf: image)
    let digest = SHA256.hash(data: diskBytes).map { String(format: "%02x", $0) }.joined()
    let name = "Terminal-Helper-0.4.0-universal.dmg"
    let sums = Data("\(digest)  ./\(name)\n".utf8)
    let prefix = "https://github.com/denysshcherbak4/terminal-helper/releases/download/v0.4.0/"
    let offer = UpdateOffer(version: "0.4.0", fileName: name, assetURL: URL(string: prefix + name)!,
        checksumURL: URL(string: prefix + "SHA256SUMS.txt")!, assetSize: diskBytes.count, checksumSize: sums.count)
    let catalog = try JSONSerialization.data(withJSONObject: [
        "tag_name": "v0.4.0", "draft": false, "prerelease": false,
        "assets": [
            ["name": name, "browser_download_url": offer.assetURL.absoluteString, "size": diskBytes.count, "state": "uploaded"],
            ["name": "SHA256SUMS.txt", "browser_download_url": offer.checksumURL.absoluteString, "size": sums.count, "state": "uploaded"]
        ]
    ])
    let saved = try TerminalUpdates.save(diskBytes, offer: offer, downloads: root)
    try SuggestionState().write(enabled: true)
    let integration = support.appendingPathComponent("integration.zsh")
    try Data("# original\n".utf8).write(to: integration); chmod(integration.path, 0o600)
    let marker = support.appendingPathComponent("app-path")
    try Data((target.path + "\n").utf8).write(to: marker); chmod(marker.path, 0o600)
    var requests: [URL] = []
    let fetch: TerminalUpdates.Fetch = { url, _, done in
        requests.append(url)
        if url == TerminalUpdates.catalogURL { done(.success(catalog)) }
        else if url == offer.checksumURL { done(.success(sums)) }
        else { done(.failure(UpdateFailure.invalid("Unexpected fixture network request"))) }
    }
    try rejects("cancel during release verification") {
        let delayed: TerminalUpdates.Fetch = { _, _, done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { kill(getpid(), SIGTERM) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done(.success(catalog)) }
        }
        _ = try UpdateInstaller.install(disk: saved, version: "0.4.0", target: target, fetch: delayed, launch: { _ in false })
    }
    try expect(UpdateInstaller.cancelledByUser, "SIGTERM cooperatively cancels preparation")
    try expect(UpdateInstaller.bundleVersion(target) == "0.3.0", "cancellation preserves installed app")
    try expect(!fm.fileExists(atPath: support.appendingPathComponent(".integration-lock").path), "cancellation leaves no integration lock")
    var opened: URL?
    let installed = try UpdateInstaller.install(disk: saved, version: "0.4.0", target: target,
        fetch: fetch, launch: { opened = $0; return false })
    defer { try? fm.removeItem(at: installed.backup.deletingLastPathComponent()) }
    try expect(requests == [TerminalUpdates.catalogURL, offer.checksumURL], "installer rechecks published metadata and checksum")
    try expect(UpdateInstaller.bundleVersion(target) == "0.4.0", "actual verified DMG mounted and installed")
    try expect(UpdateInstaller.bundleVersion(installed.backup) == "0.3.0", "full installer keeps original app")
    try expect(opened == target && !installed.relaunched, "launch request boundary; blocked launch accurately reported")
    var lateLaunch = false
    let cancelled = UpdateInstaller.finish(backup: installed.backup, target: target, cancelled: true, launch: { _ in lateLaunch = true; return true })
    try expect(!cancelled.relaunched && !lateLaunch, "late cancellation retains installed app and backup without relaunch")
    try expect(Data(contentsOf: integration) == Data("# updated fixture; data only\n".utf8), "full installer upgrades owned integration")
    try expect(!SuggestionState().enabled(), "full installer leaves suggestions Off")
    try expect(getxattr(target.path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "full installed bundle quarantined")
    try expect(getxattr(target.appendingPathComponent("Contents/MacOS/TerminalHelper").path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "full installed executable quarantined")
    try expect(!fm.fileExists(atPath: installed.backup.deletingLastPathComponent().appendingPathComponent("mount").path), "owned image mount detached and removed")
}
print("PASS \(checks) installer assertions: signed bundles, atomic exchange, rollback boundaries, Off, exact integration, locks, concurrent edits, quarantine, no execution, unsafe paths/signatures/versions.")
