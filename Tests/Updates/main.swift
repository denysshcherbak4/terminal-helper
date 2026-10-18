import Foundation
import CryptoKit
import CoreServices
import Darwin

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fputs("FAIL update: \(message)\n", stderr); exit(1) }
}
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); expect(false, message) } catch { checks += 1 }
}
let name = "Terminal-Helper-0.3.0-universal.dmg"
let bytes = Data("verified fixture disk image".utf8)
let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
let manifest = Data("\(hash)  ./\(name)\n".utf8)
let prefix = "https://github.com/denysshcherbak4/terminal-helper/releases/download/v0.3.0/"
func catalog(tag: String = "v0.3.0", draft: Bool = false, preview: Bool = false, name diskName: String = name, diskURL: String? = nil, size: Int = bytes.count, extras: [[String: Any]] = []) -> Data {
    let disk: [String: Any] = ["name": diskName, "browser_download_url": diskURL ?? prefix + diskName, "size": size, "state": "uploaded"]
    let sum: [String: Any] = ["name": "SHA256SUMS.txt", "browser_download_url": prefix + "SHA256SUMS.txt", "size": manifest.count, "state": "uploaded"]
    return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": preview, "assets": [disk, sum] + extras])
}
func offer(_ data: Data = catalog()) throws -> UpdateOffer {
    guard case .available(let item) = try TerminalUpdates.parse(data, current: "0.2.0") else {
        throw UpdateFailure.invalid("Fixture did not provide an update.")
    }
    return item
}
func wait<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void) -> Result<T, Error> {
    var result: Result<T, Error>?
    let done = DispatchSemaphore(value: 0)
    start { result = $0; done.signal() }
    expect(done.wait(timeout: .now() + 5) == .success, "bounded completion")
    return result!
}

expect(ReleaseVersion("0.2.0")! < ReleaseVersion("0.10.0")!, "numeric version comparison")
expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.999.999")!, "major version comparison")
for version in ["", "v0.2.0", "1.2", "01.2.3", "1.2.3.4", "1.2.3-beta", "1.2.-3", "1.2.３", "1.2.9999999", "1.2.3\n"] {
    expect(ReleaseVersion(version) == nil, "invalid version rejected")
}
let available = try offer()
expect(available.version == "0.3.0" && available.fileName == name, "valid release selected")
_ = try offer(catalog(name: "Terminal-Helper-0.3.0-012345abcdef-universal.dmg"))
checks += 1
if case .upToDate = try TerminalUpdates.parse(catalog(), current: "0.3.0") { checks += 1 } else { expect(false, "same version") }
if case .upToDate = try TerminalUpdates.parse(catalog(), current: "0.4.0") { checks += 1 } else { expect(false, "no downgrade") }
for data in [Data("not json".utf8), Data(repeating: 32, count: 512 * 1024 + 1), catalog(tag: "v0.3.0-beta"), catalog(draft: true), catalog(preview: true), catalog(size: 0), catalog(size: TerminalUpdates.maximumDownload + 1), catalog(name: "Terminal-Helper-0.3.0-012345abcdef-arm64.dmg"), catalog(name: "../update.dmg")] {
    rejects("invalid release metadata") { _ = try offer(data) }
}
let duplicate: [String: Any] = ["name": name, "browser_download_url": prefix + name, "size": bytes.count, "state": "uploaded"]
rejects("ambiguous assets") { _ = try offer(catalog(extras: [duplicate])) }
for url in ["http://github.com/denysshcherbak4/terminal-helper/releases/download/v0.3.0/" + name,
            "https://github.com.attacker.test/denysshcherbak4/terminal-helper/releases/download/v0.3.0/" + name,
            prefix + name + "?unexpected=1", prefix + name + "#fragment",
            "https://user@github.com/denysshcherbak4/terminal-helper/releases/download/v0.3.0/" + name,
            "https://github.com/other/repo/releases/download/v0.3.0/" + name,
            prefix.replacingOccurrences(of: "v0.3.0", with: "v0.4.0") + name,
            prefix + "%2e%2e/" + name] {
    rejects("invalid asset origin/path") { _ = try offer(catalog(diskURL: url)) }
}
expect(BoundedRequest.permits(URL(string: "https://release-assets.githubusercontent.com/fixture")!, from: available.assetURL), "GitHub CDN redirect")
for text in ["http://release-assets.githubusercontent.com/fixture", "https://github.com.attacker.test/fixture", "https://127.0.0.1/fixture", "https://user:pass@github.com/fixture", "https://github.com:443/fixture"] {
    expect(!BoundedRequest.permits(URL(string: text)!, from: available.assetURL), "redirect rejects non-TLS, credentials and unexpected origins")
}
expect(!BoundedRequest.permits(available.assetURL, from: TerminalUpdates.catalogURL), "API cannot redirect into asset origin")
try TerminalUpdates.verify(bytes, manifest: manifest, offer: available)
checks += 1
let altered = Data("corrupted fixture disk img!".utf8)
rejects("corrupt download") { try TerminalUpdates.verify(altered, manifest: manifest, offer: available) }
for text in ["\(String(repeating: "0", count: 64))  ./\(name)\n", "\(hash)  ../\(name)\n", "\(hash)  ./\(name)\n\(hash)  ./\(name)\n", "invalid\n"] {
    let bad = Data(text.utf8)
    let item = UpdateOffer(version: available.version, fileName: available.fileName, assetURL: available.assetURL, checksumURL: available.checksumURL, assetSize: bytes.count, checksumSize: bad.count)
    rejects("invalid or duplicate checksum manifest") { try TerminalUpdates.verify(bytes, manifest: bad, offer: item) }
}
let noRelease: Result<UpdateCheck, Error> = wait { callback in
    TerminalUpdates.check(fetch: { _, _, done in done(.failure(UpdateFailure.http(404))) }, completion: callback)
}
if case .success(.noPublishedRelease) = noRelease { checks += 1 } else { expect(false, "no release message") }
let networkError: Result<UpdateCheck, Error> = wait { callback in
    TerminalUpdates.check(fetch: { _, _, done in done(.failure(UpdateFailure.http(429))) }, completion: callback)
}
if case .failure = networkError { checks += 1 } else { expect(false, "HTTP failure not up to date") }
let fetched: Result<UpdateCheck, Error> = wait { callback in
    TerminalUpdates.check(current: "0.2.0", fetch: { url, limit, done in
        expect(url == TerminalUpdates.catalogURL && limit == 512 * 1024, "only fixed release catalog")
        done(.success(catalog()))
    }, completion: callback)
}
if case .success(.available) = fetched { checks += 1 } else { expect(false, "check completion") }
var requested: [URL] = []
let failedDownload: Result<URL, Error> = wait { callback in
    TerminalUpdates.download(available, fetch: { url, _, done in
        requested.append(url)
        done(.success(url == available.checksumURL ? manifest : altered))
    }, completion: callback)
}
if case .failure = failedDownload { checks += 1 } else { expect(false, "bad bytes are never offered to Finder") }
expect(requested == [available.checksumURL, available.assetURL], "checksum then exact asset; no executable download")

final class FixtureProtocol: URLProtocol {
    static var payload = Data()
    static var declared: String? = nil
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let headers = Self.declared.map { ["Content-Length": $0] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func transport(_ body: Data, declared: String? = nil, limit: Int, status: Int = 200) -> Result<Data, Error> {
    FixtureProtocol.payload = body; FixtureProtocol.declared = declared; FixtureProtocol.status = status
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    return wait { callback in
        BoundedRequest(url: TerminalUpdates.catalogURL, limit: limit, completion: callback).start(configuration: configuration)
    }
}
if case .success(let data) = transport(bytes, limit: 128) { expect(data == bytes, "actual URLSession delegate receives payload") }
else { expect(false, "transport success") }
for result in [transport(bytes, declared: "9999", limit: 128),
               transport(Data(repeating: 1, count: 129), limit: 128),
               transport(bytes, limit: 128, status: 404)] {
    if case .failure = result { checks += 1 } else { expect(false, "bounded transport rejects size/status") }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalHelper-update-tests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let downloads = root.appendingPathComponent("Downloads дані with spaces", isDirectory: true)
try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
let sentinel = downloads.appendingPathComponent("unrelated.txt"); try Data("keep".utf8).write(to: sentinel)
let saved = try TerminalUpdates.save(bytes, offer: available, downloads: downloads)
let second = try TerminalUpdates.save(bytes, offer: available, downloads: downloads)
expect(saved != second && saved.lastPathComponent == name, "unique destination; no overwrite")
let savedBytes = try Data(contentsOf: saved)
expect(savedBytes == bytes, "verified bytes saved")
let untouched = try Data(contentsOf: sentinel)
expect(untouched == Data("keep".utf8), "unrelated files preserved")
let fileMode = try FileManager.default.attributesOfItem(atPath: saved.path)[.posixPermissions] as! NSNumber
let directoryMode = try FileManager.default.attributesOfItem(atPath: saved.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
expect(fileMode.intValue == 0o600 && directoryMode.intValue == 0o700, "private downloaded file and directory")
let properties = try (saved as NSURL).resourceValues(forKeys: [.quarantinePropertiesKey])[.quarantinePropertiesKey] as? [String: Any]
expect(properties != nil, "download retains macOS quarantine assessment")
// macOS returns a subset of properties; verify the actual download protection.
expect(properties?[kLSQuarantineTypeKey as String] as? String == kLSQuarantineTypeWebDownload as String, "web-download quarantine type")
expect(getxattr(saved.path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "actual quarantine attribute exists")
let malicious = UpdateOffer(version: "0.3.0", fileName: "../outside.dmg", assetURL: available.assetURL, checksumURL: available.checksumURL, assetSize: bytes.count, checksumSize: manifest.count)
rejects("path traversal cannot be saved") { _ = try TerminalUpdates.save(bytes, offer: malicious, downloads: downloads) }
rejects("missing destination") { _ = try TerminalUpdates.save(bytes, offer: available, downloads: root.appendingPathComponent("missing")) }
print("PASS update: \(checks) assertions; numeric versions, metadata/origin/redirect bounds, HTTP failures, checksums, private files, quarantine and no overwrite")
