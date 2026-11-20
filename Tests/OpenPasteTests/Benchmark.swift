import AppKit
import XCTest

@testable import OpenPaste

/// OPENPASTE_BENCH=1 swift test -c release --filter Benchmark
final class Benchmark: XCTestCase {
    func testHistoryStorage() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENPASTE_BENCH"] != nil)
        for count in [500, 5_000] {
            try measureHistory(count: count)
        }
    }

    private func measureHistory(count: Int) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = String(repeating: "worker: Request failed\n", count: 220_000)
        let formatting = Data(("{\\rtf1 " + String(repeating: "x", count: 2_000) + "}").utf8)
        do {
            let store = ClipStore(dir: dir, limit: count)
            for i in 0..<(count - 5) {
                store.add(
                    Clip(
                        kind: .text, text: "item \(i) " + String(repeating: "x", count: 200),
                        richText: i.isMultiple(of: 10) ? formatting : nil))
            }
            for i in 0..<5 {
                store.add(Clip(kind: .text, text: "log \(i)\n" + log))
            }
            store.flush(wait: true)
            XCTAssertNil(store.persistenceError)

            report(
                count, "rename+flush",
                ms: median(31) { i in
                    store.rename(store.clips[0], to: "title \(i)")
                    store.flush(wait: true)
                })
            report(
                count, "insert+flush",
                ms: median(31) { i in
                    store.add(Clip(kind: .text, text: "copy \(i)"))
                    store.flush(wait: true)
                })
            XCTAssertNil(store.persistenceError)
        }

        report(
            count, "load",
            ms: median(11) { _ in
                let store = ClipStore(dir: dir, limit: count)
                XCTAssertEqual(store.clips.count, count)
            })
        let loaded = ClipStore(dir: dir, limit: count)
        XCTAssertEqual(loaded.clips.first?.text, "copy 30")
        report(
            count, "search miss",
            ms: median(31) { _ in
                XCTAssertTrue(loaded.filtered("no-such-thing").isEmpty)
            })

        let bytes = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ).reduce(0) { total, file in
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return total + (values.isRegularFile == true ? values.fileSize ?? 0 : 0)
        }
        print("BENCH \(count) storage: \(bytes) bytes")
    }

    private func median(_ count: Int, _ body: (Int) -> Void) -> Double {
        let samples = (0..<count).map { i in
            let start = DispatchTime.now().uptimeNanoseconds
            body(i)
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        }.sorted()
        return samples[count / 2]
    }

    private func report(_ count: Int, _ name: String, ms: Double) {
        print("BENCH \(count) \(name): \(String(format: "%.3f", ms)) ms")
    }
}
