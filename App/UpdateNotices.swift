import Foundation

// Only non-sensitive preferences are persisted; no timer or network request lives here.
final class UpdateNoticePolicy {
    static let enabledKey = "AutomaticUpdateChecksEnabled"
    static let lastAttemptKey = "AutomaticUpdateLastAttempt"
    static let skippedVersionKey = "AutomaticUpdateSkippedVersion"
    static let interval: TimeInterval = 24 * 60 * 60
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get {
            guard let value = defaults.object(forKey: Self.enabledKey) else { return true }
            return value as? Bool ?? false
        }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var skippedVersion: String? {
        guard let value = defaults.string(forKey: Self.skippedVersionKey),
              ReleaseVersion(value) != nil else { return nil }
        return value
    }

    func shouldCheck(now: Date = Date()) -> Bool {
        guard isEnabled, now.timeIntervalSince1970.isFinite else { return false }
        guard let previous = defaults.object(forKey: Self.lastAttemptKey) as? Date,
              previous.timeIntervalSince1970.isFinite else { return true }
        let elapsed = now.timeIntervalSince(previous)
        // A clock correction must not suppress checks indefinitely.
        return elapsed < 0 || elapsed >= Self.interval
    }

    func recordAttempt(now: Date = Date()) {
        guard now.timeIntervalSince1970.isFinite else { return }
        defaults.set(now, forKey: Self.lastAttemptKey)
    }

    func skip(version: String) {
        guard ReleaseVersion(version) != nil else { return }
        defaults.set(version, forKey: Self.skippedVersionKey)
    }

    func shouldOffer(version: String, current: String = TerminalUpdates.currentVersion) -> Bool {
        guard let offered = ReleaseVersion(version), let installed = ReleaseVersion(current),
              offered > installed else { return false }
        return skippedVersion != version
    }
}
