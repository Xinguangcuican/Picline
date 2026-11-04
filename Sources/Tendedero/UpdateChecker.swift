import Foundation
import UserNotifications

/// Asks GitHub, once a day and once at launch, whether a newer Picline exists.
///
/// The app used to have no way of knowing: its only "check for updates" opened
/// a web page and hoped the page would answer. That is a check only for people
/// who already suspect there is something to check for. A new release nobody
/// hears about is a release that did not happen.
///
/// Everything here is quiet by design: one request, no polling, and a single
/// notification per version — never one per launch.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// The release feed. Unauthenticated, so GitHub allows sixty requests an
    /// hour; one a day is nowhere near it.
    nonisolated static let feed = URL(string: "https://api.github.com/repos/Xinguangcuican/Picline/releases/latest")!
    /// The same answer without the API: this URL redirects to
    /// `/releases/tag/vX.Y.Z`, so the tag can be read off the address it lands
    /// on. The API allows sixty requests an hour per address, which a shared
    /// connection can use up without trying; a redirect has no such ceiling.
    nonisolated static let latest = URL(string: "https://github.com/Xinguangcuican/Picline/releases/latest")!
    nonisolated static let page = URL(string: "https://github.com/Xinguangcuican/Picline/releases/latest")!

    /// The newest version that is newer than this build, once one is known.
    /// The menu reads this to offer the download without asking again.
    private(set) var newer: String?

    /// Called after a check that found something, so the menu bar can redraw.
    var onChange: (() -> Void)?

    private var task: URLSessionDataTask?
    private var daily: Timer?

    private static let checkedAtKey = "updateCheckedAt"
    private static let toldAboutKey = "updateToldAbout"

    /// Once a day, and once shortly after launch. The first check waits a
    /// little: starting up is not the moment to be doing network calls.
    func start() {
        log.notice("update check: started, current \(Self.currentVersion, privacy: .public)")
        let last = UserDefaults.standard.object(forKey: Self.checkedAtKey) as? Date ?? .distantPast
        let waited = Date().timeIntervalSince(last)
        if waited > 6 * 3600 {
            let delay: TimeInterval = waited > 24 * 3600 ? 20 : 20
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.check(announcing: true)
            }
        }
        daily?.invalidate()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let last = UserDefaults.standard.object(forKey: Self.checkedAtKey) as? Date ?? .distantPast
                if Date().timeIntervalSince(last) > 24 * 3600 {
                    self.check(announcing: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        daily = timer
    }

    /// One request. `announcing` says whether a new version should be shown to
    /// someone; the menu's own check passes false and reports the result
    /// itself, so it never gets both an alert and a notification.
    func check(announcing: Bool, then report: ((Result<String?, Error>) -> Void)? = nil) {
        task?.cancel()
        // The cheap way first: follow the redirect, read the tag off the end.
        var head = URLRequest(url: Self.latest)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 15
        head.setValue("Picline/1", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: head) { [weak self] _, response, error in
            let landed = (response as? HTTPURLResponse)?.url?.lastPathComponent
            if let landed, let tag = Self.tag(inPath: landed) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finish(tag: tag, announcing: announcing, report: report) }
                }
                return
            }
            // No redirect, or something that is not a tag: ask the API, which
            // answers with the whole release but is rate limited.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = error
                    self?.askAPI(announcing: announcing, report: report)
                }
            }
        }
        task?.resume()
    }

    /// `v0.3.0` out of `/releases/tag/v0.3.0`, or nothing.
    nonisolated static func tag(inPath path: String) -> String? {
        guard path.hasPrefix("v"), path.count > 1,
              path.dropFirst().allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return path
    }

    /// Everything that happens once a tag is known, whichever way it arrived.
    private func finish(tag: String, announcing: Bool,
                        report: ((Result<String?, Error>) -> Void)?) {
        UserDefaults.standard.set(Date(), forKey: Self.checkedAtKey)
        UserDefaults.standard.removeObject(forKey: "updateLastError")
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let current = Self.currentVersion
        log.notice("update check: latest \(latest, privacy: .public), this build \(current, privacy: .public)")
        let found = isNewer(latest, than: current) ? latest : nil
        newer = found
        onChange?()
        if announcing, let found { announce(found) }
        report?(.success(found))
    }

    /// The API request, used when the redirect says nothing.
    private func askAPI(announcing: Bool, report: ((Result<String?, Error>) -> Void)?) {
        task?.cancel()
        var request = URLRequest(url: Self.feed)
        request.timeoutInterval = 15
        // GitHub answers 403 without one.
        request.setValue("Picline", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        task = URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error {
                        // Kept where it can be looked at later: a check that
                        // fails silently is indistinguishable from one that
                        // never ran.
                        UserDefaults.standard.set(error.localizedDescription,
                                                  forKey: "updateLastError")
                        log.error("update check: \(error.localizedDescription, privacy: .public)")
                        report?(.failure(error))
                        return
                    }
                    guard let data,
                          let tag = Self.tag(in: data) else {
                        UserDefaults.standard.set("the answer had no tag", forKey: "updateLastError")
                        log.error("update check: the answer had no tag_name")
                        report?(.failure(URLError(.cannotParseResponse)))
                        return
                    }
                    self.finish(tag: tag, announcing: announcing, report: report)
                }
            }
        }
        task?.resume()
    }

    /// This build's version, as the bundle records it.
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `"tag_name":"v0.2.9"` out of the release JSON. Cheaper and steadier than
    /// a JSON parser for the one field this needs.
    nonisolated static func tag(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let range = text.range(of: "\"tag_name\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let colon = rest.firstIndex(of: ":"),
              let open = rest[colon...].firstIndex(of: "\""),
              let close = rest[rest.index(after: open)...].firstIndex(of: "\"") else { return nil }
        let value = rest[rest.index(after: open)..<close]
        return value.isEmpty ? nil : String(value)
    }

    /// A notification, unless this version was announced before. Someone who
    /// ignores it once should not be told again every six hours.
    private func announce(_ version: String) {
        guard UserDefaults.standard.string(forKey: Self.toldAboutKey) != version else { return }
        UserDefaults.standard.set(version, forKey: Self.toldAboutKey)

        // `current()` is asked for inside the closure: a notification centre is
        // not Sendable, and capturing one in a completion handler is what the
        // compiler rightly complains about.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(format: L("Picline %@ is available"), version)
            content.body = L("Click to see what is new")
            content.sound = .default
            content.userInfo = ["url": Self.page.absoluteString]
            let request = UNNotificationRequest(identifier: "picline-update-\(version)",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

/// Whether `candidate` is a later version than `current`, comparing the parts
/// as numbers so 0.3.0 follows 0.2.9 and 0.2.10 would follow 0.2.9 too.
func isNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ text: String) -> [Int] {
        text.split(separator: ".")
            .map { part in Int(part.prefix { $0.isNumber }) ?? 0 }
    }
    var a = parts(candidate)
    var b = parts(current)
    let count = max(a.count, b.count)
    a.append(contentsOf: repeatElement(0, count: count - a.count))
    b.append(contentsOf: repeatElement(0, count: count - b.count))
    for (x, y) in zip(a, b) where x != y {
        return x > y
    }
    return false
}
