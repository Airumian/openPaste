import Foundation
import SQLite3

final class ClipDatabase {
    private let dir: URL
    private var connection: OpaquePointer?
    private var revision: Int64?
    private var clipOrder: [UUID] = []
    private var legacyFiles: [URL] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(dir: URL) { self.dir = dir }

    deinit { sqlite3_close(connection) }

    private var url: URL { dir.appendingPathComponent("history.sqlite3") }

    func load() throws -> (clips: [Clip], pinboards: [Pinboard], needsImport: Bool) {
        if FileManager.default.fileExists(atPath: url.path) {
            let db = try connect()
            let loaded: ([Clip], [Pinboard])? = try db.transaction("BEGIN") {
                switch try db.version() {
                case 0: return nil
                case 1:
                    let snapshot = try db.statement(
                        "SELECT revision, clip_order, pinboards FROM snapshot")
                    guard try snapshot.next() else { throw StorageError.invalidSnapshot }
                    revision = snapshot.integer(0)

                    var byID: [UUID: Clip] = [:]
                    let rows = try db.statement(
                        """
                        SELECT id, kind, text, rich_text, image_file, image_hash, text_file,
                               text_length, app_bundle_id, date, pinboard_id, title FROM clips
                        """)
                    while try rows.next() {
                        let clip = try rows.clip()
                        byID[clip.id] = clip
                    }
                    clipOrder = try decoder.decode([UUID].self, from: snapshot.blob(1) ?? Data())
                    let clips = try clipOrder.map {
                        guard let clip = byID.removeValue(forKey: $0) else {
                            throw StorageError.invalidSnapshot
                        }
                        return clip
                    }
                    guard byID.isEmpty else { throw StorageError.invalidSnapshot }
                    let pinboards = try decoder.decode(
                        [Pinboard].self, from: snapshot.blob(2) ?? Data())
                    return (clips, pinboards)
                default: throw StorageError.unsupportedVersion
                }
            }
            if let loaded { return (loaded.0, loaded.1, false) }
        }
        let clips: [Clip] = try readLegacy("history.json")
        let pinboards: [Pinboard] = try readLegacy("pinboards.json")
        return (clips, pinboards, !legacyFiles.isEmpty)
    }

    // Called on ClipStore's serial I/O queue after the initial load.
    func save(clips: [Clip], pinboards: [Pinboard], changed: Set<UUID>) throws {
        let db = try connect()
        let newOrder = clips.map(\.id)
        let newIDs = Set(newOrder)
        guard newIDs.count == newOrder.count else { throw StorageError.invalidSnapshot }
        let nextRevision = (revision ?? 0) + 1
        try db.transaction("BEGIN IMMEDIATE") {
            switch try db.version() {
            case 0:
                guard revision == nil else { throw StorageError.changedOnDisk }
                try db.exec(
                    """
                    CREATE TABLE clips (
                        id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, text TEXT,
                        rich_text BLOB, image_file TEXT, image_hash TEXT, text_file TEXT,
                        text_length INTEGER, app_bundle_id TEXT, date REAL NOT NULL,
                        pinboard_id TEXT, title TEXT
                    );
                    CREATE TABLE snapshot (
                        id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL,
                        clip_order BLOB NOT NULL, pinboards BLOB NOT NULL
                    );
                    PRAGMA user_version = 1;
                    """)
            case 1:
                let current = try db.statement("SELECT revision FROM snapshot")
                guard let revision, try current.next(), current.integer(0) == revision else {
                    throw StorageError.changedOnDisk
                }
            default: throw StorageError.unsupportedVersion
            }

            let delete = try db.statement("DELETE FROM clips WHERE id = ?")
            for id in clipOrder where !newIDs.contains(id) {
                try delete.bind(id.uuidString, at: 1)
                try delete.run()
            }
            let put = try db.statement(
                """
                REPLACE INTO clips (
                    id, kind, text, rich_text, image_file, image_hash, text_file,
                    text_length, app_bundle_id, date, pinboard_id, title
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for clip in clips where revision == nil || changed.contains(clip.id) {
                try put.bind(clip)
                try put.run()
            }

            let snapshot = try db.statement(
                """
                INSERT INTO snapshot (id, revision, clip_order, pinboards) VALUES (1, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET revision = excluded.revision,
                    clip_order = IFNULL(?, clip_order), pinboards = excluded.pinboards
                """)
            let order =
                revision == nil || clipOrder != newOrder ? try encoder.encode(newOrder) : nil
            try snapshot.check(sqlite3_bind_int64(snapshot.handle, 1, nextRevision))
            try snapshot.bind(order ?? Data(), at: 2)
            try snapshot.bind(try encoder.encode(pinboards), at: 3)
            try snapshot.bind(order, at: 4)
            try snapshot.run()
        }
        revision = nextRevision
        clipOrder = newOrder
        legacyFiles.removeAll { file in
            do {
                try FileManager.default.removeItem(at: file)
                return true
            } catch CocoaError.fileNoSuchFile {
                return true
            } catch {
                return false
            }
        }
    }

    private func readLegacy<Value: Decodable>(_ name: String) throws -> [Value] {
        let file = dir.appendingPathComponent(name)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let values = try decoder.decode([Value].self, from: data)
        legacyFiles.append(file)
        return values
    }

    private func connect() throws -> OpaquePointer {
        if let connection { return connection }
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        do {
            guard result == SQLITE_OK, let handle else { throw StorageError.sqlite(handle, result) }
            try handle.exec("PRAGMA secure_delete = ON")
            connection = handle
            return handle
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    fileprivate enum StorageError: LocalizedError {
        case message(String)
        case invalidSnapshot, unsupportedVersion, changedOnDisk

        static func sqlite(_ db: OpaquePointer?, _ code: Int32) -> Self {
            let message = db.flatMap(sqlite3_errmsg) ?? sqlite3_errstr(code)
            return .message(message.map { String(cString: $0) } ?? "SQLite error \(code)")
        }

        var errorDescription: String? {
            switch self {
            case .message(let message): return message
            case .invalidSnapshot: return "Нарушена целостность истории OpenPaste."
            case .unsupportedVersion: return "Эта история создана несовместимой версией OpenPaste."
            case .changedOnDisk: return "История изменилась на диске. Перезапустите OpenPaste."
            }
        }
    }

    fileprivate final class Statement {
        let handle: OpaquePointer
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        init(_ db: OpaquePointer, _ sql: String) throws {
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            guard result == SQLITE_OK, let statement else { throw StorageError.sqlite(db, result) }
            handle = statement
        }

        deinit { sqlite3_finalize(handle) }

        func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
            guard result == expected else {
                throw StorageError.sqlite(sqlite3_db_handle(handle), result)
            }
        }

        func next() throws -> Bool {
            let result = sqlite3_step(handle)
            if result == SQLITE_ROW { return true }
            try check(result, expected: SQLITE_DONE)
            return false
        }

        func run() throws {
            try check(sqlite3_step(handle), expected: SQLITE_DONE)
            try check(sqlite3_reset(handle))
        }

        func bind(_ value: String?, at index: Int32) throws {
            guard let value else { return try check(sqlite3_bind_null(handle, index)) }
            try value.withCString {
                try check(
                    sqlite3_bind_text64(
                        handle, index, $0, UInt64(value.utf8.count), Self.transient,
                        UInt8(SQLITE_UTF8)))
            }
        }

        func bind(_ value: Data?, at index: Int32) throws {
            guard let value else { return try check(sqlite3_bind_null(handle, index)) }
            if value.isEmpty {
                try check(sqlite3_bind_zeroblob(handle, index, 0))
            } else {
                try value.withUnsafeBytes {
                    try check(
                        sqlite3_bind_blob64(
                            handle, index, $0.baseAddress, UInt64($0.count), Self.transient))
                }
            }
        }

        func bind(_ clip: Clip) throws {
            try bind(clip.id.uuidString, at: 1)
            try bind(clip.kind.rawValue, at: 2)
            try bind(clip.text, at: 3)
            try bind(clip.richText, at: 4)
            try bind(clip.imageFile, at: 5)
            try bind(clip.imageHash, at: 6)
            try bind(clip.textFile, at: 7)
            if let length = clip.textLength {
                try check(sqlite3_bind_int64(handle, 8, Int64(length)))
            } else {
                try check(sqlite3_bind_null(handle, 8))
            }
            try bind(clip.appBundleID, at: 9)
            try check(sqlite3_bind_double(handle, 10, clip.date.timeIntervalSinceReferenceDate))
            try bind(clip.pinboardID?.uuidString, at: 11)
            try bind(clip.title, at: 12)
        }

        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }

        func blob(_ column: Int32) -> Data? {
            guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
            guard let bytes = sqlite3_column_blob(handle, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
        }

        private func text(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(handle, column) else { return nil }
            return String(
                decoding: UnsafeBufferPointer(
                    start: bytes, count: Int(sqlite3_column_bytes(handle, column))),
                as: UTF8.self)
        }

        func clip() throws -> Clip {
            guard let id = text(0).flatMap(UUID.init(uuidString:)),
                let kind = text(1).flatMap(Clip.Kind.init(rawValue:))
            else { throw StorageError.invalidSnapshot }
            let board = text(10)
            let boardID = board.flatMap(UUID.init(uuidString:))
            guard board == nil || boardID != nil else { throw StorageError.invalidSnapshot }
            return Clip(
                id: id, kind: kind, text: text(2), richText: blob(3), imageFile: text(4),
                imageHash: text(5), textFile: text(6),
                textLength: sqlite3_column_type(handle, 7) == SQLITE_NULL ? nil : Int(integer(7)),
                appBundleID: text(8),
                date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(handle, 9)),
                pinboardID: boardID, title: text(11))
        }
    }
}

extension OpaquePointer {
    fileprivate func statement(_ sql: String) throws -> ClipDatabase.Statement {
        try ClipDatabase.Statement(self, sql)
    }

    fileprivate func exec(_ sql: String) throws {
        let result = sqlite3_exec(self, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw ClipDatabase.StorageError.sqlite(self, result) }
    }

    fileprivate func version() throws -> Int64 {
        let query = try statement("PRAGMA user_version")
        guard try query.next() else { throw ClipDatabase.StorageError.invalidSnapshot }
        return query.integer(0)
    }

    fileprivate func transaction<Value>(_ begin: String, _ body: () throws -> Value) throws -> Value
    {
        try exec(begin)
        do {
            let value = try body()
            try exec("COMMIT")
            return value
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}
