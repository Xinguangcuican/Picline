import AppKit

/// Mission Control, App Exposé and Launchpad all hand the screen over to the
/// Dock, which puts a window the size of each display on top of everything:
/// the overview behind, the spaces bar across the top, the thumbnails in front.
///
/// Dragging a window from one Space to another happens in there, with the left
/// button held and the pointer crossing the top edge of the screen — the exact
/// shape of carrying a picture up to the line. The line has to keep out of the
/// way for all of it, or it takes the drop that was meant for the next Space.
///
/// The state is read off the window list rather than off the frontmost app:
/// with Mission Control open the frontmost app stays whatever it was and so
/// does the owner of the menu bar (checked on macOS 26). What does change is
/// that the Dock owns a screen-sized window on every display; with the
/// overview closed it owns nothing at all, or only its strip along the bottom.
enum Overview {
    /// The window list costs more than the rest of a frame put together, and
    /// the answer cannot change inside this much time, so it is asked for at
    /// most this often. Callers only ask when the answer can change something:
    /// the pointer is at the top of a screen, or the line is already down.
    private static let probeInterval: TimeInterval = 0.2

    private static var lastProbe: (at: Date, up: Bool)?

    /// Whether an overview is on screen right now.
    static func isUp(now: Date = Date()) -> Bool {
        if let lastProbe, now.timeIntervalSince(lastProbe.at) < probeInterval {
            return lastProbe.up
        }
        let up = coversAScreen(owner: dockPid())
        lastProbe = (now, up)
        return up
    }

    /// The overview is drawn by the Dock, and its windows are named in the
    /// system language ("Dock", "程序坞"), so the process itself is matched.
    private static func dockPid() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
    }

    /// A window the Dock owns that covers (very nearly) a whole screen. Its own
    /// strip is a few dozen points tall and never qualifies; the overview, the
    /// spaces bar and its backdrop cover the display exactly.
    private static func coversAScreen(owner pid: pid_t?) -> Bool {
        guard let pid else { return false }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { continue }
            if screens.contains(where: { width >= $0.width * 0.9 && height >= $0.height * 0.9 }) {
                return true
            }
        }
        return false
    }
}
