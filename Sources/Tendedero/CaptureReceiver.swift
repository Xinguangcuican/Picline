import AppKit
import CryptoKit
import ImageIO

/// Every producer hands captures to this boundary. References keep the existing
/// folder-watching semantics; temporary-folder and clipboard files are copied
/// before their owner can clean them up. Neither policy changes the source.
struct CaptureInput {
    enum Source: Hashable { case folder, clipboard }
    enum Storage {
        case reference, copy

        /// OS temporary locations have a producer-controlled lifetime. Detect
        /// their structure, rather than naming individual screenshot apps or
        /// treating every directory called "tmp" as temporary.
        static func forFolder(_ folder: URL) -> Self {
            let original = folder.path
            let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
            let temporaryRoots = [FileManager.default.temporaryDirectory,
                                  URL(fileURLWithPath: "/tmp"),
                                  URL(fileURLWithPath: "/var/tmp"),
                                  URL(fileURLWithPath: "/private/tmp"),
                                  URL(fileURLWithPath: "/private/var/tmp")]
            if temporaryRoots.contains(where: {
                let lexicalRoot = $0.path
                let root = $0.standardizedFileURL.resolvingSymlinksInPath().path
                return original == lexicalRoot || original.hasPrefix(lexicalRoot + "/")
                    || folder.path == root || folder.path.hasPrefix(root + "/")
            }) { return .copy }
            let containers = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers").standardizedFileURL.resolvingSymlinksInPath()
            if folder.path.hasPrefix(containers.path + "/") {
                let components = folder.pathComponents.dropFirst(containers.pathComponents.count)
                let relative = Array(components)
                if relative.count >= 3, relative[1] == "Data", relative[2] == "tmp" { return .copy }
            }
            return .reference
        }
    }
    enum Payload {
        case file(URL, Storage)
        case image(Data)
    }
    let payload: Payload
    let source: Source
    /// An explicit image representation accompanying a clipboard image file.
    /// Kept separate so the original file takes priority over a Finder icon.
    var fallbackImage: Data? = nil
}

struct ReceivedCapture {
    let url: URL
    let originalURL: URL?
    let thumbnail: NSImage
    let isUpdate: Bool
    /// Rebind an existing card without treating recovery as a new capture.
    var replacingURL: URL? = nil
}

struct CaptureFileVersion: Equatable {
    let size: Int
    let modified: Date
    let created: Date

    init?(at url: URL) {
        // URL resource values are cached on the URL instance. Records reuse
        // their URLs, so invalidate that cache before checking for an edit or
        // deletion, including atomic replacements performed by an editor.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard url.isFileURL,
              let values = try? fresh.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                .contentModificationDateKey, .creationDateKey,
              ]), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        self.size = size
        self.modified = modified
        created = values.creationDate ?? .distantPast
    }
}

@MainActor
final class CaptureReceiver {
    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]
    nonisolated static let maxBytes = 64 * 1024 * 1024
    private let inbox: URL
    private let isPresent: (URL) -> Bool
    private let currentURLs: () -> [URL]
    private let onCapture: (ReceivedCapture) -> Void
    private let onRemove: (URL) -> Void
    private let worker = DispatchQueue(label: "picline.receiver", qos: .userInitiated)
    private enum Work {
        case capture(CaptureInput), refresh
    }
    private var pending: [Work] = []
    private(set) var isProcessing = false

    private struct Record {
        var origins: Set<URL>
        var primaryOrigin: URL?
        var destination: URL
        var fingerprint: String?
        var version: CaptureFileVersion?
    }
    private var records: [Record] = []

    init(inbox: URL = Inbox.folder, isPresent: @escaping (URL) -> Bool,
         currentURLs: @escaping () -> [URL] = { [] },
         onRemove: @escaping (URL) -> Void = { _ in },
         onCapture: @escaping (ReceivedCapture) -> Void) {
        self.inbox = inbox
        self.isPresent = isPresent
        self.currentURLs = currentURLs
        self.onRemove = onRemove
        self.onCapture = onCapture
    }

    func receive(_ input: CaptureInput) {
        // Coalesce queued notifications, but keep one after an in-flight read:
        // the file may have changed while that read was finishing.
        if case let .file(url, _) = input.payload,
           pending.contains(where: {
               if case let .capture(otherInput) = $0, case let .file(other, _) = otherInput.payload {
                   return other.standardizedFileURL == url.standardizedFileURL
               }
               return false
           }) { return }
        pending.append(.capture(input))
        startProcessing()
    }

    /// Rebuild the index from live cards at launch, and reconcile edits or
    /// deletions reported by a watcher. No historical directories are scanned.
    func refresh() {
        if !pending.contains(where: { if case .refresh = $0 { return true }; return false }) {
            pending.append(.refresh)
        }
        startProcessing()
    }

    private func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            while !pending.isEmpty {
                switch pending.removeFirst() {
                case let .capture(input): await process(input)
                case .refresh: await reconcile()
                }
            }
            isProcessing = false
        }
    }

    private struct Prepared {
        let original: URL?
        let thumbnail: NSImage
        let fingerprint: String?
        let data: Data?
        let ext: String
        let version: CaptureFileVersion?
    }

    private func process(_ input: CaptureInput) async {
        var previous: CaptureFileVersion?
        var prepared: Prepared?
        // References wait for matching versions. Temporary inputs take a
        // complete byte snapshot immediately, before the producer removes it.
        for attempt in 0..<12 {
            let prior = previous
            let result = await onWorker { Self.prepare(input, previous: prior) }
            previous = result.1
            if let ready = result.0 { prepared = ready; break }
            if input.fallbackImage != nil, previous == nil { break }
            if case .image = input.payload { break }
            if attempt < 11 { try? await Task.sleep(for: .milliseconds(200)) }
        }
        if prepared == nil, let bytes = input.fallbackImage {
            prepared = await onWorker {
                Self.prepare(CaptureInput(payload: .image(bytes), source: input.source), previous: nil).0
            }
        }
        guard let prepared else { return }
        // Snapshot short-lived inputs before indexing the existing cards.
        await reconcile()
        let original = prepared.original
        if case .file(_, .reference) = input.payload, let original,
           await onWorker({ CaptureFileVersion(at: original) }) != prepared.version {
            // Indexing existing cards can take time. A reference that changed
            // meanwhile needs another stable read rather than the old pixels.
            receive(input)
            return
        }
        var existing = records.lastIndex { record in
            original.map { record.origins.contains($0) || record.destination == $0 } ?? false
        }

        // An alias is another independent file. Editing it must not overwrite
        // the file backing the shared card (or its managed snapshot).
        if let index = existing, original != records[index].destination,
           original != records[index].primaryOrigin,
           prepared.fingerprint != records[index].fingerprint {
            if let original { records[index].origins.remove(original) }
            existing = nil
        }
        // Exact pixel equality across every channel and path, for as long as
        // the matching card remains live. Sources are never deleted by merging.
        if let fingerprint = prepared.fingerprint,
           let duplicate = records.firstIndex(where: { $0.fingerprint == fingerprint }) {
            if let original { records[duplicate].origins.insert(original) }
            if let existing, existing != duplicate {
                onRemove(records[existing].destination)
                records.remove(at: existing)
            }
            return
        }

        let destination: URL
        let needsCopy: Bool
        switch input.payload {
        case .image: needsCopy = true
        case let .file(_, storage): needsCopy = storage == .copy
        }
        if let existing { destination = records[existing].destination }
        else if !needsCopy, let original { destination = original }
        else { destination = inbox.appendingPathComponent("Capture \(UUID().uuidString).\(prepared.ext)") }

        if destination != original {
            guard let data = prepared.data else { return }
            guard await save(data, to: destination) else { return }
        }
        let version = await onWorker { CaptureFileVersion(at: destination) }
        // Explicitly taking a card down while its update is saving wins over
        // that update; a background edit must not resurrect it.
        if let existing, !isPresent(destination) { records.remove(at: existing); return }
        let update = isPresent(destination)
        var record = Record(origins: [], primaryOrigin: original, destination: destination,
                            fingerprint: prepared.fingerprint, version: version)
        if let original { record.origins.insert(original) }
        if let existing { records[existing] = record } else { records.append(record) }
        onCapture(ReceivedCapture(url: destination, originalURL: original,
                                  thumbnail: prepared.thumbnail, isUpdate: update))
    }

    private func save(_ data: Data, to destination: URL) async -> Bool {
        await onWorker {
            do {
                try FileManager.default.createDirectory(at: self.inbox, withIntermediateDirectories: true)
                let staging = self.inbox.appendingPathComponent(".\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: staging) }
                guard FileManager.default.createFile(atPath: staging.path, contents: data,
                                                    attributes: [.posixPermissions: 0o600]) else { return false }
                return rename(staging.path, destination.path) == 0
            } catch { return false }
        }
    }

    private func reconcile() async {
        records.removeAll { !isPresent($0.destination) }
        // Existing preferences contain card URLs only. Recompute identities
        // instead of persisting hashes which could be stale after an edit.
        for url in currentURLs() where !records.contains(where: { $0.destination == url }) {
            guard let prepared = await readCurrent(url), isPresent(url) else {
                if !FileManager.default.fileExists(atPath: url.path) { onRemove(url) }
                continue
            }
            records.append(Record(origins: [], primaryOrigin: nil, destination: url,
                                  fingerprint: prepared.fingerprint, version: prepared.version))
        }
        for index in records.indices {
            let url = records[index].destination
            guard isPresent(url) else { continue }
            let version = await onWorker { CaptureFileVersion(at: url) }
            if version == nil {
                // Keep a surviving alias only if its content still matches.
                // Recover to a private copy so another temporary file cannot
                // immediately invalidate the replacement card.
                var recovered = false
                for alias in records[index].origins.sorted(by: { $0.path < $1.path }) where alias != url {
                    guard let fingerprint = records[index].fingerprint,
                          let prepared = await readCurrent(alias), prepared.fingerprint == fingerprint,
                          let data = prepared.data, isPresent(url) else { continue }
                    let destination = inbox.appendingPathComponent("Capture \(UUID().uuidString).\(prepared.ext)")
                    guard await save(data, to: destination) else { continue }
                    guard isPresent(url) else { try? FileManager.default.removeItem(at: destination); break }
                    records[index].destination = destination
                    records[index].version = await onWorker { CaptureFileVersion(at: destination) }
                    records[index].primaryOrigin = nil
                    onCapture(ReceivedCapture(url: destination, originalURL: nil, thumbnail: prepared.thumbnail,
                                              isUpdate: true, replacingURL: url))
                    recovered = true
                    break
                }
                if !recovered { onRemove(url) }
            } else if version != records[index].version {
                guard let prepared = await readCurrent(url), isPresent(url) else {
                    // A writer may be midway through an edit. Do not compare
                    // incoming images with the card's old fingerprint.
                    records[index].fingerprint = nil
                    continue
                }
                if records[index].fingerprint != prepared.fingerprint {
                    records[index].origins = []
                    records[index].primaryOrigin = nil
                }
                records[index].fingerprint = prepared.fingerprint
                records[index].version = prepared.version
                onCapture(ReceivedCapture(url: url, originalURL: nil, thumbnail: prepared.thumbnail, isUpdate: true))
            }
        }
        records.removeAll { !isPresent($0.destination) }
        // This also folds duplicates left by an older version or by an edit
        // which changes an existing card to match another one.
        var unique: [Record] = []
        for record in records {
            if let fingerprint = record.fingerprint,
               let index = unique.firstIndex(where: { $0.fingerprint == fingerprint }) {
                unique[index].origins.formUnion(record.origins)
                unique[index].origins.insert(record.destination)
                onRemove(record.destination)
            } else { unique.append(record) }
        }
        records = unique
    }

    /// A reference read with a known version checks again after decoding, so
    /// an interrupted edit cannot become an entry in the live content index.
    private func readCurrent(_ url: URL) async -> Prepared? {
        await onWorker {
            guard let version = CaptureFileVersion(at: url) else { return nil }
            return Self.prepare(CaptureInput(payload: .file(url, .reference), source: .folder), previous: version).0
        }
    }

    private func onWorker<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            worker.async { continuation.resume(returning: work()) }
        }
    }

    nonisolated private static func prepare(_ input: CaptureInput, previous: CaptureFileVersion?) -> (Prepared?, CaptureFileVersion?) {
        let data: Data
        let original: URL?
        let version: CaptureFileVersion?
        let ext: String
        switch input.payload {
        case let .file(url, storage):
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard let current = CaptureFileVersion(at: canonical), current.size > 0 else { return (nil, nil) }
            guard storage == .copy || current == previous else { return (nil, current) }
            if isRecording(canonical) {
                guard let thumbnail = makeThumbnail(canonical), CaptureFileVersion(at: canonical) == current else { return (nil, current) }
                return (Prepared(original: canonical, thumbnail: thumbnail,
                                 fingerprint: nil, data: nil, ext: canonical.pathExtension, version: current), current)
            }
            guard imageExtensions.contains(canonical.pathExtension.lowercased()), current.size <= maxBytes,
                  let bytes = try? Data(contentsOf: canonical), bytes.count <= maxBytes else { return (nil, current) }
            let afterRead = CaptureFileVersion(at: canonical)
            guard afterRead == current || (storage == .copy && afterRead == nil) else { return (nil, current) }
            data = bytes
            original = canonical
            version = current
            ext = canonical.pathExtension.lowercased()
        case let .image(bytes):
            guard bytes.count <= maxBytes else { return (nil, nil) }
            data = bytes
            original = nil
            version = nil
            ext = "png"
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 80_000_000 / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data else { return (nil, version) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let digest = SHA256.hash(data: Data(bytesNoCopy: pixels, count: width * height * 4, deallocator: .none))
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let fingerprint = "\(width)x\(height)/\(orientation):\(digest.map { String(format: "%02x", $0) }.joined())"
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 640]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return (nil, version) }
        var savedData = data
        if original == nil {
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else { return (nil, nil) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return (nil, nil) }
            savedData = encoded as Data
        }
        if case .file(_, .reference) = input.payload, let original,
           CaptureFileVersion(at: original) != version { return (nil, nil) }
        return (Prepared(original: original,
                         thumbnail: NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height)),
                         fingerprint: fingerprint, data: savedData, ext: ext, version: version), version)
    }
}
