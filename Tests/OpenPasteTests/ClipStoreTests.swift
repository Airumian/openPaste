import SQLite3
import XCTest

@testable import OpenPaste

final class ClipStoreTests: XCTestCase {
    private func reload(_ s: ClipStore) -> ClipStore {
        s.flush(wait: true)
        return ClipStore(dir: s.dir)
    }

    func testBigTextIsExternalized() {
        let s = makeStore()
        let big = String(repeating: "log line\n", count: 10_000)  // 90 KB
        s.add(Clip(kind: .text, text: big))
        let clip = s.clips[0]
        XCTAssertEqual(clip.text?.count, ClipStore.previewChars)
        XCTAssertEqual(clip.textLength, big.count)
        XCTAssertEqual(s.fullText(clip), big)
        XCTAssertEqual(reload(s).fullText(clip), big)
        s.delete(clip)
        s.clear()
        s.flush(wait: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.textsDir.path), [])
    }

    func testFailedExternalWritePreservesFullText() throws {
        let store = makeStore()
        try FileManager.default.removeItem(at: store.textsDir)
        try Data().write(to: store.textsDir)
        let text = String(repeating: "full text\n", count: 6_000)
        store.add(Clip(kind: .text, text: text))
        let reopened = reload(store)
        let saved = try XCTUnwrap(reopened.clips.first)
        XCTAssertNil(saved.textFile)
        XCTAssertEqual(reopened.fullText(saved), text)
    }

    func testFailedSaveCanBeRetriedWithoutAnotherChange() throws {
        let store = makeStore()
        let path = store.dir.appendingPathComponent("history.sqlite3")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        store.add(Clip(kind: .text, text: "keep this"))
        store.flush(wait: true)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(store.clips.first?.text, "keep this")

        try FileManager.default.removeItem(at: path)
        store.flush(wait: true)
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(reload(store).clips.first?.text, "keep this")
    }

    func testImportsJSONHistoryAndPinboardsOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let texts = dir.appendingPathComponent("texts")
        try FileManager.default.createDirectory(at: texts, withIntermediateDirectories: true)
        let boards = [Pinboard(name: "Работа", color: 4), Pinboard(name: "Дом", color: 1)]
        var pinned = Clip(kind: .text, text: "preview", pinboardID: boards[0].id, title: "Title")
        pinned.textFile = "saved.txt"
        pinned.textLength = 12
        let clips = [Clip(kind: .text, text: "a\0б", richText: Data()), pinned]
        let sidecar = texts.appendingPathComponent("saved.txt")
        try Data("full content".utf8).write(to: sidecar)
        let legacy = dir.appendingPathComponent("history.json")
        try JSONEncoder().encode(clips).write(to: legacy)
        try JSONEncoder().encode(boards).write(to: dir.appendingPathComponent("pinboards.json"))

        let store = ClipStore(dir: dir)
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(store.clips, clips)
        XCTAssertEqual(store.pinboards, boards)
        XCTAssertEqual(store.fullText(pinned), "full content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("pinboards.json").path))
        XCTAssertEqual(ClipStore(dir: dir).clips, clips)

        store.delete(clips[0])
        store.flush(wait: true)
        try JSONEncoder().encode(clips).write(to: legacy)
        let reopened = ClipStore(dir: dir)
        XCTAssertEqual(reopened.clips, [pinned])
        XCTAssertEqual(reopened.pinboards, boards)
        XCTAssertEqual(reopened.fullText(pinned), "full content")
    }

    func testInvalidLegacyJSONIsKeptWhenImportFails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let history = dir.appendingPathComponent("history.json")
        let boards = dir.appendingPathComponent("pinboards.json")
        let originalHistory = try JSONEncoder().encode([Clip(kind: .text, text: "keep me")])
        let invalidBoards = Data("{".utf8)
        try originalHistory.write(to: history)
        try invalidBoards.write(to: boards)

        let store = ClipStore(dir: dir)
        store.add(Clip(kind: .text, text: "new item"))
        store.flush(wait: true)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(try Data(contentsOf: history), originalHistory)
        XCTAssertEqual(try Data(contentsOf: boards), invalidBoards)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("history.sqlite3").path))
    }

    func testFailedSaveKeepsPreviouslyPersistedExternalText() throws {
        let store = makeStore()
        let oldText = String(repeating: "old\n", count: 15_000)
        let newText = String(repeating: "new\n", count: 15_000)
        store.add(Clip(kind: .text, text: oldText))
        let old = try XCTUnwrap(reload(store).clips.first)
        let oldFile = store.textsDir.appendingPathComponent(try XCTUnwrap(old.textFile))

        var connection: OpaquePointer?
        let path = store.dir.appendingPathComponent("history.sqlite3").path
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        try store.editContents(of: old.id, text: newText, richText: nil)
        store.flush(wait: true)
        XCTAssertNotNil(store.persistenceError)
        let reopened = ClipStore(dir: store.dir)
        XCTAssertEqual(reopened.clips, [old])
        XCTAssertEqual(reopened.fullText(old), oldText)

        XCTAssertEqual(sqlite3_exec(connection, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        let saved = reload(store)
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(saved.clips.first.flatMap(saved.fullText), newText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    }

    func testEditingKeepsCardIdentityAndPersistsFullText() throws {
        let store = makeStore()
        let board = store.addPinboard(name: "Pinned")
        var card = Clip(kind: .link, text: "https://example.org")
        card.pinboardID = board.id
        card.title = "Custom name"
        store.add(card)

        let text = String(repeating: "edited content\n", count: 5_000)
        let formatting = Data("{\\rtf1 \\b edited}".utf8)
        try store.editContents(of: card.id, text: text, richText: formatting)
        let reopened = reload(store)
        let edited = try XCTUnwrap(reopened.clips.first)
        XCTAssertEqual(edited.id, card.id)
        XCTAssertEqual(edited.pinboardID, board.id)
        XCTAssertEqual(edited.title, card.title)
        XCTAssertEqual(edited.kind, .text)
        XCTAssertEqual(edited.richText, formatting)
        XCTAssertEqual(try reopened.textForEditing(edited), text)

        try reopened.editContents(of: edited.id, text: "https://example.com", richText: nil)
        let saved = try XCTUnwrap(reload(reopened).clips.first)
        XCTAssertEqual(saved.kind, .link)
        XCTAssertNil(saved.richText)
        XCTAssertEqual(try reopened.textForEditing(saved), "https://example.com")
    }

    func testDuplicateImagesByHash() throws {
        let s = makeStore()
        var first = Clip(kind: .image)
        first.imageFile = "a.png"
        first.imageHash = "same"
        try Data([1]).write(to: s.imageURL(first)!)
        s.add(first)
        var second = Clip(kind: .image)
        second.imageFile = "b.png"
        second.imageHash = "same"
        s.add(second)
        s.flush(wait: true)
        XCTAssertEqual(s.clips.map(\.imageFile), ["b.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.imageURL(first)!.path))
    }

    func testDeleteSelectionRestoresAllCardsInOrder() throws {
        let store = makeStore()
        let board = store.addPinboard(name: "Pinned")
        var pinned = Clip(kind: .text, text: "pinned")
        pinned.pinboardID = board.id
        store.add(Clip(kind: .text, text: "old"))
        store.add(pinned)
        let largeText = String(repeating: "clipboard line\n", count: 5_000)
        store.add(Clip(kind: .text, text: largeText))
        store.add(Clip(kind: .text, text: "new"))
        let original = store.clips

        store.delete(store.filtered(""))
        XCTAssertEqual(reload(store).clips, [pinned])

        XCTAssertEqual(store.undoDelete()?.id, original.first?.id)
        XCTAssertEqual(reload(store).clips, original)
        let restored = try XCTUnwrap(store.clips.first { $0.textFile != nil })
        XCTAssertEqual(try store.textForEditing(restored), largeText)
        XCTAssertNil(store.undoDelete())
    }

    private func makeStore(limit: Int = 500) -> ClipStore {
        ClipStore(
            dir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            limit: limit)
    }

    func testDuplicateMovesToFront() {
        let s = makeStore()
        s.add(Clip(kind: .text, text: "a"))
        s.add(Clip(kind: .text, text: "b"))
        s.add(Clip(kind: .text, text: "a"))
        XCTAssertEqual(s.clips.map(\.text), ["a", "b"])
    }

    /// A private pasteboard, so tests never clobber the user's clipboard.
    private func makePasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: .init("openpaste-test-\(UUID())"))
        addTeardownBlock { pb.releaseGlobally() }
        return pb
    }

    func testCopySelectedTextClipsTogetherInPanelOrder() throws {
        let store = makeStore()
        let pb = makePasteboard()
        let text = "formatted"
        let rtf = try XCTUnwrap(
            NSAttributedString(string: text).rtf(
                from: NSRange(location: 0, length: text.count), documentAttributes: [:]))
        let longText = String(repeating: "line of text\n", count: 5_000)
        store.add(Clip(kind: .text, text: "outside the selection"))
        store.add(Clip(kind: .text, text: longText))
        store.add(Clip(kind: .text, text: text, richText: rtf))
        let clips = store.filtered("")
        let state = PanelState()
        state.select(clips[1].id)
        state.extendSelection(to: 0, in: clips)
        let selected = state.selectedIDs(in: clips)

        store.copy(clips.filter { selected.contains($0.id) }, to: pb)

        let expected = text + "\n" + longText
        XCTAssertEqual(pb.pasteboardItems?.count, 1)
        XCTAssertEqual(pb.string(forType: .string), expected)
        let combinedRTF = try XCTUnwrap(pb.data(forType: .rtf))
        XCTAssertEqual(
            NSAttributedString(rtf: combinedRTF, documentAttributes: nil)?.string, expected)
        XCTAssertEqual(store.filtered("").map(\.id), clips.map(\.id))
    }

    func testCopySelectedClipsWithFilesPreservesSeparateItems() {
        let store = makeStore()
        let pb = makePasteboard()
        let file = store.dir.appendingPathComponent("file.txt")
        let clips = [
            Clip(kind: .text, text: "text"),
            Clip(kind: .file, text: file.path),
        ]

        store.copy(clips, to: pb)

        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.pasteboardItems?.first?.string(forType: .string), "text")
        XCTAssertEqual(
            pb.readObjects(
                forClasses: [NSURL.self],
                options: [
                    .urlReadingFileURLsOnly: true
                ]) as? [URL], [file])
    }

    func testRichTextIsCapturedAndRestored() throws {
        let s = makeStore()
        let pb = makePasteboard()
        let rtf = try XCTUnwrap(
            NSAttributedString(string: "bold").rtf(
                from: NSRange(location: 0, length: 4), documentAttributes: [:]))
        pb.clearContents()
        pb.setString("bold", forType: .string)
        pb.setData(rtf, forType: .rtf)
        s.poll(pb)
        XCTAssertEqual(s.clips.map(\.richText), [rtf])

        // The same text copied again without formatting replaces the card instead of duplicating it.
        pb.clearContents()
        pb.setString("bold", forType: .string)
        s.poll(pb)
        XCTAssertEqual(s.clips.count, 1)
        XCTAssertNil(s.clips[0].richText)

        s.add(Clip(kind: .text, text: "bold", richText: rtf))
        s.copy(s.clips[0], to: pb)
        XCTAssertEqual(pb.data(forType: .rtf), rtf)
    }

    func testImageIsCopiedBackAsOriginalPNG() throws {
        let s = makeStore()
        let pb = makePasteboard()
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        var clip = Clip(kind: .image)
        clip.imageFile = "a.png"
        try png.write(to: s.imageURL(clip)!)
        s.add(clip)
        s.copy(s.clips[0], to: pb)
        XCTAssertEqual(pb.data(forType: .png), png)
    }

    func testLimitAndPersistence() {
        let s = makeStore(limit: 2)
        ["1", "2", "3"].forEach { s.add(Clip(kind: .text, text: $0)) }
        XCTAssertEqual(s.clips.map(\.text), ["3", "2"])
        XCTAssertEqual(reload(s).clips.map(\.text), ["3", "2"])
    }

    func testFilter() {
        let s = makeStore()
        s.add(Clip(kind: .text, text: "docker image prune"))
        s.add(Clip(kind: .text, text: "192.0.2.10"))
        XCTAssertEqual(s.filtered("DOCKER").map(\.text), ["docker image prune"])
        XCTAssertEqual(s.filtered("  ").count, 2)
    }

    func testPinboards() {
        let s = makeStore(limit: 1)
        s.add(Clip(kind: .text, text: "keep"))
        let board = s.addPinboard(name: "Работа")
        s.pin(s.clips[0], to: board)
        s.add(Clip(kind: .text, text: "newer"))  // pushes "keep" out of history (limit 1), pin survives

        XCTAssertEqual(s.filtered("").map(\.text), ["newer"])
        XCTAssertEqual(s.filtered("", board: board.id).map(\.text), ["keep"])

        s.clear()
        XCTAssertEqual(s.filtered("", board: board.id).count, 1, "clearing history keeps pins")
        XCTAssertEqual(reload(s).pinboards.map(\.name), ["Работа"])

        s.deletePinboard(board)
        XCTAssertTrue(s.clips.isEmpty)
    }

    func testMovePinboardAcrossMultipleTabs() {
        let store = makeStore()
        let first = store.addPinboard(name: "A")
        _ = store.addPinboard(name: "B")
        _ = store.addPinboard(name: "C")

        store.movePinboard(first.id, by: 2)

        XCTAssertEqual(reload(store).pinboards.map(\.name), ["B", "C", "A"])
    }

    func testRenameAndMovePinboards() {
        let s = makeStore()
        let a = s.addPinboard(name: "A")
        let b = s.addPinboard(name: "B")
        s.renamePinboard(a.id, to: "Alpha")
        s.setPinboardColor(a.id, to: 5)
        XCTAssertEqual(reload(s).pinboards.first?.color, 5)
        s.movePinboard(a.id, by: +1)
        s.movePinboard(a.id, by: +1)  // already last: no-op
        XCTAssertEqual(s.pinboards.map(\.name), ["B", "Alpha"])
        s.movePinboard(b.id, by: -1)  // already first: no-op
        XCTAssertEqual(reload(s).pinboards.map(\.name), ["B", "Alpha"])
    }

    func testThumbnailIsSmallAndDeletedWithClip() throws {
        let s = makeStore()
        var clip = Clip(kind: .image)
        clip.imageFile = "\(clip.id).png"
        let big = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 2000, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        try big.representation(using: .png, properties: [:])!.write(to: s.imageURL(clip)!)
        s.add(clip)

        let thumb = try XCTUnwrap(s.thumbnail(clip))
        let px = thumb.representations.map { max($0.pixelsWide, $0.pixelsHigh) }.max() ?? 0
        XCTAssertLessThanOrEqual(px, ClipStore.thumbnailPixels)
        XCTAssertEqual(s.imageSize(clip), CGSize(width: 3000, height: 2000))
        XCTAssertEqual(reload(s).imageSize(clip), CGSize(width: 3000, height: 2000))

        let thumbFile = ClipStore.thumbnailURL(for: s.imageURL(clip)!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbFile.path))
        s.delete(clip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbFile.path), "kept for ⌘Z")
        s.clear()
        s.flush(wait: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbFile.path))
    }

    func testUndoDeleteRestoresPosition() {
        let s = makeStore()
        ["c", "b", "a"].forEach { s.add(Clip(kind: .text, text: $0)) }  // a, b, c
        s.delete(s.clips[1])
        XCTAssertEqual(s.clips.map(\.text), ["a", "c"])
        XCTAssertEqual(s.undoDelete()?.text, "b")
        XCTAssertEqual(s.clips.map(\.text), ["a", "b", "c"])
        XCTAssertNil(s.undoDelete(), "only one level of undo")
    }

    func testFileClips() throws {
        let s = makeStore()
        let png = s.dir.appendingPathComponent("shot.png")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1000, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)

        let clip = Clip(kind: .file, text: png.path + "\n/tmp/nope.txt")
        XCTAssertEqual(clip.files.map(\.lastPathComponent), ["shot.png", "nope.txt"])

        let preview = try XCTUnwrap(s.thumbnail(clip))
        XCTAssertLessThanOrEqual(
            max(preview.size.width, preview.size.height), CGFloat(ClipStore.thumbnailPixels))
        XCTAssertNotNil(
            s.thumbnail(Clip(kind: .file, text: "/tmp/missing.txt")),
            "non-images fall back to the Finder icon")
        XCTAssertEqual(Clip(kind: .text, text: "/a/b").files, [], "only file clips expose files")
    }

    func testPruneKeepsPinsAndRecentClips() {
        let s = makeStore()
        let now = Date()
        s.add(Clip(kind: .text, text: "old", date: now.addingTimeInterval(-40 * 86_400)))
        s.add(Clip(kind: .text, text: "recent", date: now.addingTimeInterval(-2 * 86_400)))
        let board = s.addPinboard(name: "B")
        s.add(
            Clip(
                kind: .text, text: "old pin", date: now.addingTimeInterval(-400 * 86_400),
                pinboardID: board.id))

        s.prune(olderThanDays: nil, now: now)
        XCTAssertEqual(s.clips.count, 3, "forever keeps everything")
        s.prune(olderThanDays: 30, now: now)
        XCTAssertEqual(s.clips.map(\.text), ["old pin", "recent"])
        s.prune(olderThanDays: 1, now: now)
        XCTAssertEqual(s.clips.map(\.text), ["old pin"])
    }

    func testRenameKeepsTitleAndIsSearchable() {
        let s = makeStore()
        s.add(Clip(kind: .text, text: "ssh deploy@192.0.2.10"))
        s.rename(s.clips[0], to: "  Прод-сервер ")
        XCTAssertEqual(s.clips[0].title, "Прод-сервер")
        XCTAssertEqual(s.filtered("прод").count, 1, "search matches the custom title")

        s.add(Clip(kind: .text, text: "ssh deploy@192.0.2.10"))  // copied again
        XCTAssertEqual(s.clips.count, 1)
        XCTAssertEqual(s.clips[0].title, "Прод-сервер", "re-copy keeps the name")

        s.rename(s.clips[0], to: "   ")
        XCTAssertNil(s.clips[0].title, "blank resets to the default title")
    }

    func testIsLink() {
        XCTAssertTrue(ClipStore.isLink("https://github.com/x/y"))
        XCTAssertTrue(ClipStore.isLink("  http://a.b  \n"))
        XCTAssertFalse(ClipStore.isLink("github.com"))
        XCTAssertFalse(ClipStore.isLink("see https://a.b now"))
        XCTAssertFalse(ClipStore.isLink("mailto:a@b.c"))
    }
}

final class FormatTests: XCTestCase {
    func testCharactersPlural() {
        XCTAssertEqual(Format.characters(1), "1 символ")
        XCTAssertEqual(Format.characters(3), "3 символа")
        XCTAssertEqual(Format.characters(12), "12 символов")
        XCTAssertEqual(Format.characters(21), "21 символ")
        XCTAssertEqual(Format.characters(113), "113 символов")
    }

    func testLinkLabel() {
        XCTAssertEqual(
            Format.linkLabel("https://www.github.com/Airumian/openPaste/"),
            "github.com/Airumian/openPaste")
        XCTAssertEqual(Format.linkLabel("https://pasteapp.io"), "pasteapp.io")
    }

    func testDominantColor() {
        let blueOnWhite = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in
            NSColor.white.setFill()
            r.fill()
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 32, height: 16).fill()
            return true
        }
        let c = AppStyle.dominantColor(of: blueOnWhite)?.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(c)
        XCTAssertGreaterThan(c!.blueComponent, c!.redComponent)

        let gray = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in
            NSColor.darkGray.setFill()
            r.fill()
            return true
        }
        XCTAssertNil(AppStyle.dominantColor(of: gray), "monochrome icons fall back to gray")
    }

    func testBrightAppColorsRetainBrightnessWithoutClippingSaturation() throws {
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: 5.0 / 255, green: 161.0 / 255, blue: 221.0 / 255, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let color = try XCTUnwrap(AppStyle.dominantColor(of: icon)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.brightnessComponent, 0.85)
        XCTAssertLessThan(color.saturationComponent, 1)
        XCTAssertEqual(color.redComponent, 5.0 / 255, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 161.0 / 255, accuracy: 0.02)
        XCTAssertEqual(color.blueComponent, 221.0 / 255, accuracy: 0.02)
    }
}
