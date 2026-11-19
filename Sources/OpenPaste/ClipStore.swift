import AppKit
import CryptoKit
import ImageIO
import Observation

struct Clip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, link, image, file }

    var id = UUID()
    var kind: Kind
    var text: String?  // text or URL string
    var imageFile: String?  // file name inside the images folder
    var imageHash: String?  // SHA-256 of the copied bytes, to drop duplicate screenshots
    var textFile: String?  // big texts live in texts/<file>; `text` then holds only a preview
    var textLength: Int?  // full character count of an externalized text
    var appBundleID: String?
    var date = Date()
    var pinboardID: UUID?  // nil = clipboard history
    var title: String?  // user-given name; nil shows the default ("Текст", "Ссылка", …)
}

extension Clip {
    /// Copied Finder files; their paths are stored newline-separated in `text` so search finds them.
    var files: [URL] {
        kind == .file
            ? (text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) } : []
    }
}

struct Pinboard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: Int  // index into PanelView.boardColors
}

@Observable
final class ClipStore {
    private(set) var clips: [Clip] = []
    private(set) var pinboards: [Pinboard] = []
    let dir: URL
    let limit: Int
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var ticks = 0
    @ObservationIgnored private let thumbCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100  // visible cards plus scroll headroom
        return cache
    }()
    @ObservationIgnored private var saveScheduled = false
    /// Disk writes and image encoding, off the main thread. Serial, so saves land in order.
    private static let io = DispatchQueue(label: "openpaste.io", qos: .utility)
    static let thumbnailPixels = 480  // card is 232 pt wide, 2x on Retina
    static let bigTextBytes = 50_000
    static let previewChars = 10_000

    var imagesDir: URL { dir.appendingPathComponent("images") }
    var textsDir: URL { dir.appendingPathComponent("texts") }
    private var historyFile: URL { dir.appendingPathComponent("history.json") }
    private var pinboardsFile: URL { dir.appendingPathComponent("pinboards.json") }

    init(
        dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0
        ]
        .appendingPathComponent("OpenPaste"),
        limit: Int = 500
    ) {
        self.dir = dir
        self.limit = limit
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: textsDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: historyFile),
            let saved = try? JSONDecoder().decode([Clip].self, from: data)
        {
            clips = saved
        }
        if let data = try? Data(contentsOf: pinboardsFile),
            let saved = try? JSONDecoder().decode([Pinboard].self, from: data)
        {
            pinboards = saved
        }
    }

    // macOS has no "pasteboard changed" notification, so polling changeCount is the standard way.
    func start() {
        pruneExpired()
        resume()
        // Nothing gets copied while the screen sleeps or is locked: stop waking the CPU.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main)
        { [weak self] _ in self?.pause() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.resume()
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in self?.pause()
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in self?.resume()
        }
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2  // lets macOS coalesce our wakeups with other timers
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    /// Every 0.4 s while the user is active, every 1.2 s after 30 s without input.
    private func tick() {
        ticks += 1
        let anyInput = CGEventType(rawValue: ~0)!
        if ticks % 3 != 0,
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > 30
        {
            return
        }
        poll()
    }

    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount

        let types = pb.types ?? []
        // Password managers mark secrets with these types; never store them.
        if types.contains(.init("org.nspasteboard.ConcealedType"))
            || types.contains(.init("org.nspasteboard.TransientType"))
        {
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Finder also puts the file name as a string, so file URLs must be checked first.
        if let urls = pb.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            add(Clip(kind: .file, text: urls.map(\.path).joined(separator: "\n"), appBundleID: app))
        } else if let s = pb.string(forType: .string),
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            add(Clip(kind: Self.isLink(s) ? .link : .text, text: s, appBundleID: app))
        } else if let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            // Encoding a Retina screenshot takes tens of ms: do it off the main thread.
            let isPNG = pb.data(forType: .png) != nil
            var clip = Clip(kind: .image, appBundleID: app)
            clip.imageFile = "\(clip.id).png"
            let dst = imagesDir.appendingPathComponent(clip.imageFile!)
            Self.io.async { [weak self] in
                guard
                    let png = isPNG
                        ? raw
                        : NSBitmapImageRep(data: raw)?.representation(using: .png, properties: [:]),
                    (try? png.write(to: dst)) != nil
                else { return }
                clip.imageHash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
                DispatchQueue.main.async { self?.add(clip) }
            }
        }
    }

    func add(_ clip: Clip) {
        var clip = clip
        if clip.textFile == nil, let text = clip.text, text.utf8.count > Self.bigTextBytes {
            // Keep multi-MB logs out of memory and history.json; search and cards only need the start.
            clip.textFile = "\(clip.id).txt"
            try? text.write(
                to: textsDir.appendingPathComponent(clip.textFile!), atomically: true,
                encoding: .utf8)
            clip.textLength = text.count
            clip.text = String(text.prefix(Self.previewChars))
        }
        // Duplicates move to the front of their board. Big texts compare only previews, so they never dedupe.
        if clip.textFile == nil, let text = clip.text,
            let i = clips.firstIndex(where: {
                $0.textFile == nil && $0.text == text && $0.pinboardID == clip.pinboardID
            })
        {
            clip.title = clip.title ?? clips[i].title  // a re-copied clip keeps the name the user gave it
            clips.remove(at: i)
        }
        if let hash = clip.imageHash,
            let i = clips.firstIndex(where: {
                $0.imageHash == hash && $0.pinboardID == clip.pinboardID
            })
        {
            clip.title = clip.title ?? clips[i].title
            removeFile(of: clips.remove(at: i))
        }
        clips.insert(clip, at: 0)
        // Limit applies to history only; pinned clips are kept forever.
        while clips.filter({ $0.pinboardID == nil }).count > limit,
            let last = clips.lastIndex(where: { $0.pinboardID == nil })
        {
            removeFile(of: clips.remove(at: last))
        }
        save()
    }

    /// Last deleted clip, kept with its image file so ⌘Z can bring it back.
    // shortcut: one level of undo, lost on quit (its image file stays until the next delete); add a real stack if users ask.
    private var trash: (clip: Clip, index: Int)?

    func delete(_ clip: Clip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        if let old = trash { removeFile(of: old.clip) }
        trash = (clips.remove(at: i), i)
        save()
    }

    /// Restores the last deleted clip at its old position; returns it, or nil if there is nothing to undo.
    @discardableResult
    func undoDelete() -> Clip? {
        guard let (deleted, index) = trash else { return nil }
        var clip = deleted
        trash = nil
        if let b = clip.pinboardID, !pinboards.contains(where: { $0.id == b }) {
            clip.pinboardID = nil  // its pinboard was deleted meanwhile: restore into history
        }
        clips.insert(clip, at: min(index, clips.count))
        save()
        return clip
    }

    /// Steps of the "keep history" slider in Settings; nil days = forever.
    static let retentionOptions: [(title: String, days: Int?)] = [
        ("День", 1), ("Неделя", 7), ("Месяц", 30), ("Год", 365), ("Бесконечно", nil),
    ]
    static let retentionKey = "historyRetention"  // UserDefaults: index into retentionOptions
    static let defaultRetention = 2  // month

    static var retentionDays: Int? {
        let i = UserDefaults.standard.object(forKey: retentionKey) as? Int ?? defaultRetention
        return retentionOptions[min(max(i, 0), retentionOptions.count - 1)].days
    }

    /// Applies the user's retention setting (on launch, before the panel shows, when the setting changes).
    func pruneExpired() { prune(olderThanDays: Self.retentionDays) }

    /// Drops history clips older than `days`; pinned clips are never expired.
    func prune(olderThanDays days: Int?, now: Date = Date()) {
        guard let days else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let expired = clips.filter { $0.pinboardID == nil && $0.date < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach(removeFile)
        clips.removeAll { $0.pinboardID == nil && $0.date < cutoff }
        save()
    }

    /// Clears history; pinboards stay.
    func clear() {
        clips.filter { $0.pinboardID == nil }.forEach(removeFile)
        clips.removeAll { $0.pinboardID == nil }
        if let old = trash { removeFile(of: old.clip) }
        trash = nil
        save()
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].name = name
        save()
    }

    func setPinboardColor(_ id: UUID, to color: Int) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].color = color
        save()
    }

    /// Moves a pinboard relative to its current position, preserving the order of the other tabs.
    func movePinboard(_ id: UUID, by delta: Int) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }),
            delta != 0, pinboards.indices.contains(i + delta)
        else { return }
        let board = pinboards.remove(at: i)
        pinboards.insert(board, at: i + delta)
        save()
    }

    @discardableResult
    func addPinboard(name: String) -> Pinboard {
        let board = Pinboard(name: name, color: pinboards.count)
        pinboards.append(board)
        save()
        return board
    }

    func deletePinboard(_ board: Pinboard) {
        clips.filter { $0.pinboardID == board.id }.forEach(removeFile)
        clips.removeAll { $0.pinboardID == board.id }
        pinboards.removeAll { $0.id == board.id }
        save()
    }

    func pin(_ clip: Clip, to board: Pinboard) {
        add(duplicate(clip, into: board.id))
    }

    /// Copy with its own id and image file, so deleting one never breaks the other.
    private func duplicate(_ clip: Clip, into board: UUID?) -> Clip {
        var copy = clip
        copy.id = UUID()
        copy.date = Date()
        copy.pinboardID = board
        if let src = imageURL(clip) {
            copy.imageFile = "\(copy.id).png"
            try? FileManager.default.copyItem(
                at: src, to: imagesDir.appendingPathComponent(copy.imageFile!))
        }
        if let file = clip.textFile {
            copy.textFile = "\(copy.id).txt"
            try? FileManager.default.copyItem(
                at: textsDir.appendingPathComponent(file),
                to: textsDir.appendingPathComponent(copy.textFile!))
        }
        return copy
    }

    /// Puts the clip back on the system pasteboard and moves it to the front.
    func copy(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if clip.kind == .file {
            pb.writeObjects(clip.files as [NSURL])
        } else if let text = fullText(clip) {
            pb.setString(text, forType: .string)
        } else if let url = imageURL(clip), let image = NSImage(contentsOf: url) {
            pb.writeObjects([image])
        }
        lastChange = pb.changeCount
        guard clip.pinboardID == nil else {
            add(duplicate(clip, into: nil))  // pasting a pin also records it in history; the pin stays put
            return
        }
        var moved = clip
        moved.date = Date()
        clips.removeAll { $0.id == clip.id }
        add(moved)
    }

    /// Whole text for pasting and dragging; `clip.text` may be just a preview.
    func fullText(_ clip: Clip) -> String? {
        clip.textFile.flatMap {
            try? String(contentsOf: textsDir.appendingPathComponent($0), encoding: .utf8)
        }
            ?? clip.text
    }

    /// Sets a custom card title; empty or whitespace resets it to the default.
    func rename(_ clip: Clip, to title: String) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        clips[i].title = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func filtered(_ query: String, board: UUID? = nil) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return clips.filter {
            $0.pinboardID == board
                && (q.isEmpty || $0.text?.localizedCaseInsensitiveContains(q) == true
                    || $0.title?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    func imageURL(_ clip: Clip) -> URL? {
        clip.imageFile.map { imagesDir.appendingPathComponent($0) }
    }

    static func isLink(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), let url = URL(string: t) else { return false }
        return (url.scheme == "http" || url.scheme == "https") && url.host != nil
    }

    /// Small preview for cards; full images stay on disk for pasting. Generated once, then served from disk/memory.
    func thumbnail(_ clip: Clip) -> NSImage? {
        if let file = clip.files.first {
            // Not cached on disk: the file can change; image files get a preview, others their Finder icon.
            let key = file.path as NSString
            if let cached = thumbCache.object(forKey: key) { return cached }
            let image =
                Self.makeThumbnail(file).map { NSImage(cgImage: $0, size: .zero) }
                ?? NSWorkspace.shared.icon(forFile: file.path)
            thumbCache.setObject(image, forKey: key)
            return image
        }
        guard let src = imageURL(clip) else { return nil }
        let key = src.lastPathComponent as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }

        let dst = Self.thumbnailURL(for: src)
        if !FileManager.default.fileExists(atPath: dst.path) {
            guard let cg = Self.makeThumbnail(src),
                let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            else { return nil }
            try? png.write(to: dst)
        }
        guard let image = NSImage(contentsOf: dst) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    static func makeThumbnail(_ url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func thumbnailURL(for image: URL) -> URL {
        image.deletingPathExtension().appendingPathExtension("thumb.png")
    }

    private func removeFile(of clip: Clip) {
        if let file = clip.textFile {
            try? FileManager.default.removeItem(at: textsDir.appendingPathComponent(file))
        }
        guard let url = imageURL(clip) else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: Self.thumbnailURL(for: url))
        thumbCache.removeObject(forKey: url.lastPathComponent as NSString)
    }

    // shortcut: whole history rewritten as JSON on every change, fine for ~500 items; move to SQLite/GRDB if the limit grows.
    /// Coalesces bursts of changes into one background write ~0.5 s later.
    private func save() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    /// Writes pending changes now; `wait` blocks until they are on disk (app quit, tests).
    func flush(wait: Bool = false) {
        if saveScheduled {
            saveScheduled = false
            let (clips, pinboards, history, boards) = (clips, pinboards, historyFile, pinboardsFile)
            Self.io.async {
                try? JSONEncoder().encode(clips).write(to: history, options: .atomic)
                try? JSONEncoder().encode(pinboards).write(to: boards, options: .atomic)
            }
        }
        if wait { Self.io.sync {} }
    }
}
