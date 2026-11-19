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
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.textsDir.path), [])
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
        XCTAssertEqual(s.clips.map(\.imageFile), ["b.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.imageURL(first)!.path))
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

        let thumbFile = ClipStore.thumbnailURL(for: s.imageURL(clip)!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbFile.path))
        s.delete(clip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbFile.path), "kept for ⌘Z")
        s.clear()
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
}
