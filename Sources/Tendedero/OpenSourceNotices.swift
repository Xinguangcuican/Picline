import AppKit

@MainActor
enum OpenSourceNotices {
    private static let upstreamURL = URL(string: "https://github.com/alejandrobujan/tendedero")!

    static func show() {
        let alert = NSAlert()
        alert.messageText = L("Open Source Notices")
        alert.informativeText = L("Picline is based on Tendedero by Alejandro Buján. The upstream source code is licensed under the MIT License. Picline uses its own name and icon and is an independent modified version.")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 580, height: 300))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        text.string = bundledText() ?? L("The license file is unavailable in this build.")
        text.setAccessibilityLabel(L("Open Source Notices"))
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Upstream Project"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(upstreamURL) }
    }

    private static func bundledText() -> String? {
        var sections: [String] = []
        for name in ["NOTICE", "LICENSE"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
            sections.append(text)
        }
        return sections.joined(separator: "\n\n")
    }
}
