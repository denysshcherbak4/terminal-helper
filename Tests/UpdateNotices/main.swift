import Foundation

let suite = "TerminalHelper.NoticeTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
defer { defaults.removePersistentDomain(forName: suite) }
let policy = UpdateNoticePolicy(defaults: defaults)
let now = Date(timeIntervalSince1970: 1_700_000_000)
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fputs("FAIL notice policy: \(message)\n", stderr); exit(1) }
}
expect(policy.isEnabled && policy.shouldCheck(now: now), "default first eligible check")
policy.recordAttempt(now: now)
expect(!policy.shouldCheck(now: now), "same launch does not repeat")
expect(!policy.shouldCheck(now: now.addingTimeInterval(86_399)), "less than 24h")
expect(policy.shouldCheck(now: now.addingTimeInterval(86_400)), "24h becomes eligible")
expect(UpdateNoticePolicy(defaults: UserDefaults(suiteName: suite)!).shouldCheck(now: now.addingTimeInterval(86_400)), "eligibility survives new policy instance")
expect(!UpdateNoticePolicy(defaults: UserDefaults(suiteName: suite)!).shouldCheck(now: now.addingTimeInterval(10)), "attempt survives relaunch")
policy.recordAttempt(now: now.addingTimeInterval(86_400))
expect(!policy.shouldCheck(now: now.addingTimeInterval(86_401)), "failed/offline attempt also throttles; no retry storm")
policy.isEnabled = false
expect(!policy.shouldCheck(now: now.addingTimeInterval(172_800)), "preference blocks due checks")
expect(!UpdateNoticePolicy(defaults: UserDefaults(suiteName: suite)!).isEnabled, "disabled preference persists")
policy.isEnabled = true
expect(policy.shouldCheck(now: now.addingTimeInterval(172_800)), "re-enable respects due time")
expect(policy.shouldCheck(now: now), "backward clock correction recovers")
defaults.set("malformed date", forKey: UpdateNoticePolicy.lastAttemptKey)
expect(policy.shouldCheck(now: now), "malformed last attempt does not block forever")
defaults.set("malformed boolean", forKey: UpdateNoticePolicy.enabledKey)
expect(!policy.isEnabled && !policy.shouldCheck(now: now), "malformed enabled preference fails closed")
defaults.removeObject(forKey: UpdateNoticePolicy.enabledKey)
expect(policy.isEnabled, "missing preference restores documented default")
expect(policy.shouldOffer(version: "0.3.2", current: "0.3.1"), "new version offered")
policy.skip(version: "0.3.2")
expect(!policy.shouldOffer(version: "0.3.2", current: "0.3.1"), "exact skipped version suppressed")
expect(UpdateNoticePolicy(defaults: UserDefaults(suiteName: suite)!).skippedVersion == "0.3.2", "skip survives relaunch")
expect(policy.shouldOffer(version: "0.3.3", current: "0.3.1"), "future patch version still offered")
expect(policy.shouldOffer(version: "0.4.0", current: "0.3.1"), "future minor version still offered")
expect(!policy.shouldOffer(version: "0.3.1", current: "0.3.1"), "same version not offered")
expect(!policy.shouldOffer(version: "0.3.0", current: "0.3.1"), "no downgrade")
for bad in ["", "v0.3.2", "0.3.2-beta", "0.3", "../0.3.2", "0.3.２"] {
    expect(!policy.shouldOffer(version: bad, current: "0.3.1"), "invalid version rejected")
    policy.skip(version: bad)
    expect(policy.skippedVersion == "0.3.2", "invalid skip cannot change valid preference")
}
defaults.set("invalid", forKey: UpdateNoticePolicy.skippedVersionKey)
expect(policy.skippedVersion == nil && policy.shouldOffer(version: "0.3.2", current: "0.3.1"), "malformed skip ignored safely")
print("PASS \(checks) automatic-update policy assertions: first launch, daily throttle, persisted preferences/skip, errors, clock correction, malformed state and future versions.")
