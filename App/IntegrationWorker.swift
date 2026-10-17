import Foundation
import Darwin

// Only bundled installer code runs in this group; no persistent helper is installed.
final class IntegrationWorker {
    private let pid: pid_t
    private var source: DispatchSourceProcess?
    private(set) var isRunning = true

    init(arguments: [String], environment: [String: String], completion: @escaping (Int32) -> Void) throws {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var result = posix_spawn_file_actions_init(&actions)
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        result = posix_spawnattr_init(&attributes)
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
        defer { posix_spawnattr_destroy(&attributes) }
        // SETPGROUP is applied by spawn before exec, so descendants cannot escape an exec race.
        let setup = [
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)),
            posix_spawnattr_setpgroup(&attributes, 0),
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        ]
        guard let failure = setup.first(where: { $0 != 0 }) else {
            var argv = (["/bin/zsh"] + arguments).map { strdup($0) } + [nil]
            var env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { argv.forEach { free($0) }; env.forEach { free($0) } }
            var child: pid_t = 0
            result = argv.withUnsafeMutableBufferPointer { args in
                env.withUnsafeMutableBufferPointer { vars in
                    posix_spawn(&child, "/bin/zsh", &actions, &attributes, args.baseAddress!, vars.baseAddress!)
                }
            }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
            pid = child
            let processSource = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .main)
            source = processSource
            processSource.setEventHandler { [weak self] in
                guard let self else { return }
                // Keep the exited leader unreaped until remaining group members are killed;
                // its reserved PID prevents accidentally signalling a reused process group.
                kill(-self.pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(self.pid, &status, 0) < 0 && errno == EINTR {}
                self.isRunning = false
                self.source?.cancel(); self.source = nil
                completion(status)
            }
            processSource.resume()
            return
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
    }

    func terminate() {
        guard isRunning else { return }
        kill(-pid, SIGTERM)
        // Only explicit Quit schedules a deadline; idle Off has no timers or polling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if let self, self.isRunning { kill(-self.pid, SIGKILL) }
        }
    }
}
