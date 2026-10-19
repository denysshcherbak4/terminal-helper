import AppKit
import CryptoKit
import CoreServices
import Darwin

enum UpdateFailure: Error, LocalizedError {
    case http(Int)
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .http(429), .http(403): return "GitHub could not serve this request. Try again later."
        case .http: return "GitHub could not serve this download. Try again later."
        case .invalid(let text): return text
        }
    }
}

struct ReleaseVersion: Comparable {
    let parts: [Int]
    let text: String
    init?(_ text: String) {
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        var values: [Int] = []
        for field in fields {
            guard !field.isEmpty, field.count <= 6,
                  field.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  field.count == 1 || field.first != "0", let value = Int(field) else { return nil }
            values.append(value)
        }
        parts = values; self.text = text
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct UpdateOffer {
    let version: String
    let fileName: String
    let assetURL: URL
    let checksumURL: URL
    let assetSize: Int
    let checksumSize: Int
}
enum UpdateCheck {
    case noPublishedRelease, upToDate
    case available(UpdateOffer)
}

// Short-lived bounded requests serve enabled automatic metadata checks or explicit update actions.
final class BoundedRequest: NSObject, URLSessionDataDelegate {
    let url: URL
    let limit: Int
    private var data = Data()
    private var completion: ((Result<Data, Error>) -> Void)?
    private var session: URLSession?
    private let sessionLock = NSLock()
    init(url: URL, limit: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        self.url = url; self.limit = limit; self.completion = completion
    }
    static func permits(_ target: URL, from origin: URL) -> Bool {
        guard let bits = URLComponents(url: target, resolvingAgainstBaseURL: false),
              bits.scheme == "https", bits.user == nil, bits.password == nil,
              bits.port == nil, bits.fragment == nil else { return false }
        if origin.host == "api.github.com" { return bits.host == "api.github.com" }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(bits.host ?? "")
    }
    static func fetch(_ url: URL, _ limit: Int, _ completion: @escaping (Result<Data, Error>) -> Void) {
        BoundedRequest(url: url, limit: limit, completion: completion).start()
    }
    func start(configuration: URLSessionConfiguration = .ephemeral) {
        guard limit > 0, Self.permits(url, from: url) else {
            finish(.failure(UpdateFailure.invalid("The update download address is not allowed."))); return
        }
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        sessionLock.lock(); self.session = session; sessionLock.unlock()
        var request = URLRequest(url: url)
        request.setValue("Terminal-Helper", forHTTPHeaderField: "User-Agent")
        request.setValue(url.host == "api.github.com" ? "application/vnd.github+json" : "application/octet-stream", forHTTPHeaderField: "Accept")
        session.dataTask(with: request).resume()
    }
    func cancel() {
        sessionLock.lock(); let active = session; sessionLock.unlock()
        active?.invalidateAndCancel()
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let callback = completion else { return }
        completion = nil
        sessionLock.lock(); let active = session; session = nil; sessionLock.unlock()
        active?.invalidateAndCancel()
        callback(result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, Self.permits(next, from: url) else {
            completionHandler(nil)
            finish(.failure(UpdateFailure.invalid("The update server redirected outside GitHub."))); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let final = response.url,
              Self.permits(final, from: url) else {
            completionHandler(.cancel); finish(.failure(UpdateFailure.invalid("The update response is not valid."))); return
        }
        guard http.statusCode == 200 else {
            completionHandler(.cancel); finish(.failure(UpdateFailure.http(http.statusCode))); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(UpdateFailure.invalid("The update response exceeds the download limit."))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard completion != nil else { return }
        guard chunk.count <= limit - data.count else {
            finish(.failure(UpdateFailure.invalid("The update response exceeds the download limit."))); return
        }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { finish(.failure(UpdateFailure.invalid("Could not reach GitHub. Check your connection and try again."))) }
        else { finish(.success(data)) }
    }
}

enum TerminalUpdates {
    typealias Fetch = (URL, Int, @escaping (Result<Data, Error>) -> Void) -> Void
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.3"
    static let releasesURL = URL(string: "https://github.com/denysshcherbak4/terminal-helper/releases")!
    static let catalogURL = URL(string: "https://api.github.com/repos/denysshcherbak4/terminal-helper/releases/latest")!
    static let maximumDownload = 64 * 1024 * 1024

    private struct Catalog: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int
            let state: String
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    static func safeName(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 180 && !text.contains("..") &&
        text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 46 }
    }
    static func assetURL(_ text: String, tag: String, name: String) throws -> URL {
        guard safeName(name), let bits = URLComponents(string: text),
              bits.scheme == "https", bits.host == "github.com", bits.user == nil,
              bits.password == nil, bits.port == nil, bits.query == nil, bits.fragment == nil,
              bits.percentEncodedPath == "/denysshcherbak4/terminal-helper/releases/download/\(tag)/\(name)",
              let url = bits.url else {
            throw UpdateFailure.invalid("The release contains an unexpected download address.")
        }
        return url
    }
    static func parse(_ data: Data, current: String) throws -> UpdateCheck {
        guard data.count <= 512 * 1024, let installed = ReleaseVersion(current) else {
            throw UpdateFailure.invalid("The installed version or release response is not valid.")
        }
        let release: Catalog
        do { release = try JSONDecoder().decode(Catalog.self, from: data) }
        catch { throw UpdateFailure.invalid("GitHub returned an unreadable release response.") }
        guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v"),
              let version = ReleaseVersion(String(release.tag_name.dropFirst())),
              release.assets.count <= 32 else {
            throw UpdateFailure.invalid("The published release version is not supported.")
        }
        guard version > installed else { return .upToDate }
        let prefix = "Terminal-Helper-\(version.text)-"
        let disks = release.assets.filter { asset in
            if asset.name == "Terminal-Helper-\(version.text)-universal.dmg" { return true }
            guard asset.name.hasPrefix(prefix) else { return false }
            let suffix = String(asset.name.dropFirst(prefix.count))
            let ending = suffix.hasSuffix("-universal.dmg") ? "-universal.dmg" : "-universal-test.dmg"
            guard suffix.hasSuffix(ending) else { return false }
            let sha = suffix.dropLast(ending.count)
            return sha.count == 12 && sha.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
        }
        let sums = release.assets.filter { $0.name == "SHA256SUMS.txt" }
        guard disks.count == 1, sums.count == 1 else {
            throw UpdateFailure.invalid("This release does not contain one universal Mac download and checksum file.")
        }
        let disk = disks[0], sum = sums[0]
        guard disk.state == "uploaded", sum.state == "uploaded",
              disk.size > 0, disk.size <= maximumDownload, sum.size > 0, sum.size <= 16 * 1024 else {
            throw UpdateFailure.invalid("The release download size or upload state is not valid.")
        }
        return .available(UpdateOffer(version: version.text, fileName: disk.name,
            assetURL: try assetURL(disk.browser_download_url, tag: release.tag_name, name: disk.name),
            checksumURL: try assetURL(sum.browser_download_url, tag: release.tag_name, name: sum.name),
            assetSize: disk.size, checksumSize: sum.size))
    }
    static func check(current: String = currentVersion, fetch: @escaping Fetch = BoundedRequest.fetch, completion: @escaping (Result<UpdateCheck, Error>) -> Void) {
        fetch(catalogURL, 512 * 1024) { result in
            switch result {
            case .success(let data):
                do { completion(.success(try parse(data, current: current))) }
                catch { completion(.failure(error)) }
            case .failure(let error):
                if let failure = error as? UpdateFailure, case .http(404) = failure { completion(.success(.noPublishedRelease)) }
                else { completion(.failure(error)) }
            }
        }
    }
    static func verify(_ data: Data, manifest: Data, offer: UpdateOffer) throws {
        guard data.count == offer.assetSize, manifest.count == offer.checksumSize,
              manifest.count <= 16 * 1024, let text = String(data: manifest, encoding: .utf8) else {
            throw UpdateFailure.invalid("The downloaded files do not match the release sizes.")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count <= 64 else { throw UpdateFailure.invalid("The checksum file is too large.") }
        var hashes: [String: String] = [:]
        for line in lines where !line.isEmpty {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2 else { throw UpdateFailure.invalid("The checksum file is not valid.") }
            let hash = String(fields[0]).lowercased()
            var name = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasPrefix("./") { name = String(name.dropFirst(2)) }
            guard hash.count == 64, hash.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }),
                  safeName(name), hashes[name] == nil else {
                throw UpdateFailure.invalid("The checksum file has invalid or duplicate entries.")
            }
            hashes[name] = hash
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hashes[offer.fileName] == actual else {
            throw UpdateFailure.invalid("The update checksum does not match. Nothing was opened or installed.")
        }
    }
    static func save(_ data: Data, offer: UpdateOffer, downloads: URL) throws -> URL {
        guard safeName(offer.fileName), ReleaseVersion(offer.version) != nil else {
            throw UpdateFailure.invalid("The update filename is not valid.")
        }
        let manager = FileManager.default
        let folder = downloads.appendingPathComponent("Terminal Helper \(offer.version) \(UUID().uuidString)", isDirectory: true)
        do { try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { throw UpdateFailure.invalid("Could not save the update. Check that your Downloads folder exists and is writable.") }
        do {
            let file = folder.appendingPathComponent(offer.fileName)
            try data.write(to: file, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            // Programmatic downloads must retain macOS first-open security assessment.
            let properties: [String: Any] = [
                kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
                kLSQuarantineAgentNameKey as String: "Terminal Helper",
                kLSQuarantineAgentBundleIdentifierKey as String: "io.github.denysshcherbak4.terminal-helper",
                kLSQuarantineDataURLKey as String: offer.assetURL,
                kLSQuarantineOriginURLKey as String: releasesURL
            ]
            try (file as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
            let recorded = try (file as NSURL).resourceValues(forKeys: [.quarantinePropertiesKey])
            let quarantine = recorded[.quarantinePropertiesKey] as? [String: Any]
            guard quarantine?[kLSQuarantineTypeKey as String] as? String == kLSQuarantineTypeWebDownload as String,
                  getxattr(file.path, "com.apple.quarantine", nil, 0, 0, 0) > 0 else {
                throw UpdateFailure.invalid("macOS could not preserve download security information.")
            }
            return file
        } catch {
            try? manager.removeItem(at: folder)
            throw UpdateFailure.invalid("Could not save the verified update. Nothing was installed.")
        }
    }
    static func download(_ offer: UpdateOffer, fetch: @escaping Fetch = BoundedRequest.fetch, completion: @escaping (Result<URL, Error>) -> Void) {
        fetch(offer.checksumURL, 16 * 1024) { manifest in
            switch manifest {
            case .failure(let error): completion(.failure(error))
            case .success(let sums):
                fetch(offer.assetURL, maximumDownload) { asset in
                    switch asset {
                    case .failure(let error): completion(.failure(error))
                    case .success(let bytes):
                        do {
                            try verify(bytes, manifest: sums, offer: offer)
                            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                                throw UpdateFailure.invalid("The Downloads folder is unavailable.")
                            }
                            completion(.success(try save(bytes, offer: offer, downloads: downloads)))
                        } catch { completion(.failure(error)) }
                    }
                }
            }
        }
    }
}

func updateCommandLine() -> Int32? {
    let arguments = CommandLine.arguments
    if arguments.count == 4, arguments[1] == "--apply-update" {
        do {
            _ = try UpdateInstaller.install(disk: URL(fileURLWithPath: arguments[2]), version: arguments[3])
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            if UpdateInstaller.cancelledByUser { return 130 }
            let alert = NSAlert(); alert.messageText = "Update could not be completed"
            alert.informativeText = error.localizedDescription + " See the update recovery guide if a backup was retained."
            alert.addButton(withTitle: "OK"); NSApplication.shared.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true); alert.runModal()
            return 1
        }
    }
    guard arguments.count == 2, ["--version", "--check-for-updates", "--update"].contains(arguments[1]) else { return nil }
    if arguments[1] == "--version" { print("Terminal Helper \(TerminalUpdates.currentVersion)"); return 0 }
    func wait<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        start { value in result = value; semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 150) == .success, let value = result else {
            return .failure(UpdateFailure.invalid("The update request timed out. Try again later."))
        }
        return value
    }
    print("Checking published Terminal Helper releases on GitHub…")
    let checked: Result<UpdateCheck, Error> = wait { TerminalUpdates.check(completion: $0) }
    switch checked {
    case .failure(let error): fputs("\(error.localizedDescription)\n", stderr); return 1
    case .success(.noPublishedRelease):
        print("No public release is available yet. \(TerminalUpdates.releasesURL.absoluteString)"); return 0
    case .success(.upToDate): print("Terminal Helper \(TerminalUpdates.currentVersion) is up to date."); return 0
    case .success(.available(let offer)):
        print("Version \(offer.version) is available (installed: \(TerminalUpdates.currentVersion)).")
        if arguments[1] == "--check-for-updates" { print("Run terminal-helper update to install it."); return 0 }
        print("Downloading and verifying the update. Installation will close Terminal Helper and leave suggestions Off.")
        let downloaded: Result<URL, Error> = wait { TerminalUpdates.download(offer, completion: $0) }
        switch downloaded {
        case .failure(let error): fputs("\(error.localizedDescription)\n", stderr); return 1
        case .success(let file):
            print("Verified SHA-256. Saved to \(file.path)")
            do {
                let installed = try UpdateInstaller.install(disk: file, version: offer.version)
                print("Installed Terminal Helper \(offer.version). Previous app: \(installed.backup.path)")
                print("Restart terminal windows, then enable suggestions. Shell configuration and settings were preserved.")
                if !installed.relaunched {
                    print("Open Terminal Helper from Applications. macOS may require Privacy & Security → Open Anyway if you trust this exact release. Never override a malware or damaged-app warning.")
                }
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 1 }
            return 0
        }
    }
}
