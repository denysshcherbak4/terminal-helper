import Foundation
import Darwin

let fm = FileManager.default
let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("TH-updater-tests-" + UUID().uuidString)
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
print("PASS \(checks) installer assertions: signed bundles, atomic exchange, rollback boundaries, Off, exact integration, locks, concurrent edits, quarantine, no execution, unsafe paths/signatures/versions.")
