import AppKit
import Darwin

let fm = FileManager.default
guard CommandLine.arguments.count == 2 else { fatalError("Pass the CI-built app path.") }
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Terminal Helper")
guard !fm.fileExists(atPath: support.path) else { fatalError("Refusing an existing installation; use a disposable runner.") }
let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("TH-launch-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
let target = root.appendingPathComponent("Terminal Helper.app")
defer {
    try? fm.removeItem(at: root)
    try? fm.removeItem(at: support)
}
try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: target)
try SuggestionState().write(enabled: true)
guard UpdateInstaller.reopen(target, updated: true) else { fatalError("Launch Services could not open the CI-built unquarantined fixture.") }
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: UpdateInstaller.bundleID)
guard apps.contains(where: { $0.bundleURL?.standardizedFileURL == target.standardizedFileURL }) else {
    fatalError("Fixture controller did not register with Launch Services.")
}
try UpdateInstaller.stopControllers(target: target)
guard !SuggestionState().enabled() else { fatalError("External updater quit left suggestions On.") }
guard !NSRunningApplication.runningApplications(withBundleIdentifier: UpdateInstaller.bundleID).contains(where: { !$0.isTerminated }) else {
    fatalError("Controller survived updater termination handshake.")
}
print("PASS actual Launch Services controller start, updater-requested quit, process exit and Off; fixture was CI-built, not a downloaded Gatekeeper approval test.")
