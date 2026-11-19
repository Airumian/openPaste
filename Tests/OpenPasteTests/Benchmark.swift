import AppKit
import XCTest

@testable import OpenPaste

/// Stress numbers for a big history. Run: OPENPASTE_BENCH=1 swift test -c release --filter Benchmark
final class Benchmark: XCTestCase {
    func testBigHistory() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENPASTE_BENCH"] != nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID())")
        let line =
            "2026-11-19 10:13:23.298 | ERROR | app.worker:process_job:42 - Request failed\n"
        let log = String(repeating: line, count: 52_000)  // ~5 MB

        do {
            let s = ClipStore(dir: dir)
            for i in 0..<495 {
                s.add(Clip(kind: .text, text: "item \(i) " + String(repeating: "x", count: 200)))
            }
            for i in 0..<5 { s.add(Clip(kind: .text, text: "log \(i)\n" + log)) }
            let t = time(20) { s.add(Clip(kind: .text, text: "copy \(UUID())")) }
            s.flush(wait: true)
            report("copy (main thread)", ms: t)
        }

        let before = footprintMB()
        var loaded: ClipStore!
        report("load history", ms: time(1) { loaded = ClipStore(dir: dir) })
        report("memory of loaded history", mb: footprintMB() - before)
        report("search miss (500 clips)", ms: time(20) { _ = loaded.filtered("no-such-thing") })
        let json = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent("history.json").path)
        report("history.json", mb: Double(json[.size] as! Int) / 1_048_576)

        let shot = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3024, pixelsHigh: 1964, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let tiff = shot.tiffRepresentation!
        report(
            "screenshot TIFF→PNG",
            ms: time(3) {
                _ = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            })
        _ = loaded
    }

    private func time(_ n: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(n)
    }

    private func report(_ name: String, ms: Double) {
        print("BENCH \(name): \(String(format: "%.1f", ms)) ms")
    }
    private func report(_ name: String, mb: Double) {
        print("BENCH \(name): \(String(format: "%.1f", mb)) MB")
    }

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return Double(info.phys_footprint) / 1_048_576
    }
}
