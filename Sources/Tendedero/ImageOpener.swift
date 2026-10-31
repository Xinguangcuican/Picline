import AppKit

struct ImageOpeningApplication: Equatable {
    let name: String
    let bundleIdentifier: String?
    let path: String?

    static let preview = Self(name: "Preview", bundleIdentifier: "com.apple.Preview", path: nil)
    static let shottr = Self(name: "Shottr", bundleIdentifier: "cc.ffitch.shottr", path: nil)
    static let snapzy = Self(name: "Snapzy", bundleIdentifier: "com.trongduong.snapzy", path: nil)
    static let suggested: [Self] = [.preview, .shottr, .snapzy]

    init(name: String, bundleIdentifier: String?, path: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }

    init?(saved: [String: String]) {
        guard let name = saved["name"], !name.isEmpty else { return nil }
        let identifier = saved["bundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 }
        let path = saved["path"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        guard identifier != nil || path != nil else { return nil }
        self.init(name: name, bundleIdentifier: identifier, path: path)
    }

    var saved: [String: String] {
        var value = ["name": name]
        value["bundleIdentifier"] = bundleIdentifier
        value["path"] = path
        return value
    }

    func matches(_ other: Self) -> Bool {
        if let bundleIdentifier, let identifier = other.bundleIdentifier { return bundleIdentifier == identifier }
        return path != nil && path == other.path
    }

    var displayName: String { bundleIdentifier == Self.preview.bundleIdentifier ? L("Preview") : name }
}

/// Opens document URLs through Launch Services so sandboxed editors receive
/// the file access that accompanies a normal macOS Open Document request.
@MainActor
final class ImageOpener {
    typealias OpenApplication = @MainActor (URL, URL, @escaping (Error?) -> Void) -> Void
    private let defaults: UserDefaults
    private let resolve: @MainActor (ImageOpeningApplication) -> URL?
    private let openDefault: @MainActor (URL) -> Bool
    private let openApplication: OpenApplication
    private let onFailure: @MainActor (URL, ImageOpeningApplication?) -> Void
    private static let preferenceKey = "imageOpeningApplication"

    var selected: ImageOpeningApplication? {
        get {
            guard let value = defaults.dictionary(forKey: Self.preferenceKey) as? [String: String] else { return nil }
            return ImageOpeningApplication(saved: value)
        }
        set {
            if let newValue { defaults.set(newValue.saved, forKey: Self.preferenceKey) }
            else { defaults.removeObject(forKey: Self.preferenceKey) }
        }
    }

    init(defaults: UserDefaults = .standard,
         resolve: (@MainActor (ImageOpeningApplication) -> URL?)? = nil,
         openDefault: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
         openApplication: @escaping OpenApplication = { file, app, completion in
             NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
                 _, error in completion(error)
             }
         },
         onFailure: (@MainActor (URL, ImageOpeningApplication?) -> Void)? = nil) {
        self.defaults = defaults
        self.resolve = resolve ?? Self.applicationURL
        self.openDefault = openDefault
        self.openApplication = openApplication
        self.onFailure = onFailure ?? Self.showFailure
    }

    func isAvailable(_ application: ImageOpeningApplication) -> Bool { resolve(application) != nil }

    func open(_ url: URL) {
        if isRecording(url) { _ = openDefault(url); return }
        guard let application = selected else {
            if !openDefault(url) { onFailure(url, nil) }
            return
        }
        guard let appURL = resolve(application) else { onFailure(url, application); return }
        openApplication(url, appURL) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.onFailure(url, application) }
        }
    }

    private static func applicationURL(_ application: ImageOpeningApplication) -> URL? {
        if let path = application.path {
            let url = URL(fileURLWithPath: path)
            if let bundle = Bundle(url: url), bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
               application.bundleIdentifier == nil || application.bundleIdentifier == bundle.bundleIdentifier { return url }
        }
        return application.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    private static func showFailure(_ file: URL, application: ImageOpeningApplication?) {
        let alert = NSAlert()
        alert.messageText = L("Could not open the image")
        if let application {
            alert.informativeText = String(format: L("%@ could not open this image. Check that it is installed, or choose another application in the menu."), application.displayName)
            alert.addButton(withTitle: L("Use System Default"))
            alert.addButton(withTitle: L("Cancel"))
        } else {
            alert.informativeText = L("Check that the file still exists and that an application is available to open it.")
            alert.addButton(withTitle: L("OK"))
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, application != nil {
            if !NSWorkspace.shared.open(file) { NSSound.beep() }
        }
    }
}
