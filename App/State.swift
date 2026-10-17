import Foundation
import Darwin

struct StateFailure: Error, CustomStringConvertible {
    let description: String
}

// No executable state, symlink following, or permissive owned files.
final class SuggestionState {
    let parent: URL
    init(parent: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")) {
        self.parent = parent
    }
    private func directory(create: Bool) throws -> Int32 {
        if create { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw StateFailure(description: "Cannot safely open Application Support.") }
        defer { close(parentFD) }
        if create, mkdirat(parentFD, "Terminal Helper", 0o700) != 0, errno != EEXIST {
            throw StateFailure(description: "Cannot create Terminal Helper's private folder.")
        }
        let fd = openat(parentFD, "Terminal Helper", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw StateFailure(description: "Private folder is missing or unsafe.") }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == getuid(), st.st_mode & 0o777 == 0o700 else {
            close(fd); throw StateFailure(description: "Private folder must belong to you and have permissions 700.")
        }
        return fd
    }
    private func safeFile(_ st: stat) -> Bool {
        st.st_mode & S_IFMT == S_IFREG && st.st_uid == getuid() && st.st_mode & 0o777 == 0o600 && st.st_nlink == 1
    }
    func enabled() -> Bool {
        guard let fd = try? directory(create: false) else { return false }
        defer { close(fd) }
        let file = openat(fd, "state", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return false }
        defer { close(file) }
        var st = stat()
        guard fstat(file, &st) == 0, safeFile(st), st.st_size == 21 else { return false }
        var bytes = [UInt8](repeating: 0, count: 23)
        let count = read(file, &bytes, bytes.count)
        return count == 21 && Data(bytes.prefix(count)) == Data("terminal-helper-v1:on\n".utf8)
    }
    func write(enabled: Bool) throws {
        let fd = try directory(create: true)
        defer { close(fd) }
        var existing = stat()
        if fstatat(fd, "state", &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            guard safeFile(existing) else { throw StateFailure(description: "State file has unsafe ownership, type, links, or permissions.") }
        } else if errno != ENOENT { throw StateFailure(description: "Cannot inspect state file.") }
        let name = ".state-" + UUID().uuidString
        let file = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw StateFailure(description: "Cannot create private state update.") }
        defer { close(file); unlinkat(fd, name, 0) }
        let data = Data("terminal-helper-v1:\(enabled ? "on" : "off")\n".utf8)
        let written = data.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) }
        guard written == data.count, fsync(file) == 0, renameat(fd, name, fd, "state") == 0 else {
            throw StateFailure(description: "Cannot save state; the previous state remains in effect.")
        }
    }
}

func stateSelfTest() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = SuggestionState(parent: root)
    func check(_ value: Bool, _ message: String) throws {
        if !value { throw StateFailure(description: "Self-test failed: " + message) }
    }
    try check(!state.enabled(), "missing is disabled")
    try state.write(enabled: false)
    try check(!state.enabled(), "off")
    try state.write(enabled: true)
    try check(state.enabled(), "on")
    try state.write(enabled: false)
    try state.write(enabled: true)
    try check(state.enabled(), "re-enable")
    let owned = root.appendingPathComponent("Terminal Helper")
    let file = owned.appendingPathComponent("state")
    try Data("terminal-helper-v1:on\nextra".utf8).write(to: file)
    try check(!state.enabled(), "malformed disabled")
    try state.write(enabled: false)
    chmod(file.path, 0o644)
    try check(!state.enabled(), "permissive file disabled")
    do { try state.write(enabled: true); throw StateFailure(description: "Self-test failed: unsafe write succeeded") }
    catch let error as StateFailure { if error.description.hasPrefix("Self-test") { throw error } }
    chmod(file.path, 0o600)
    try FileManager.default.removeItem(at: file)
    let target = root.appendingPathComponent("untouched")
    try Data("keep".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    try check(!state.enabled(), "symlink disabled")
    do { try state.write(enabled: true); throw StateFailure(description: "Self-test failed: symlink write succeeded") }
    catch let error as StateFailure { if error.description.hasPrefix("Self-test") { throw error } }
    try check(try Data(contentsOf: target) == Data("keep".utf8), "symlink target unchanged")
    try FileManager.default.removeItem(at: owned)
    try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: root)
    try check(!state.enabled(), "symlink directory disabled")
    print("PASS state: missing, off, on, re-enable, malformed, private permissions, file/directory symlinks")
}
