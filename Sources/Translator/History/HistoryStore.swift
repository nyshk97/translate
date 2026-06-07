import Foundation
import SQLite3

struct HistoryEntry: Identifiable, Sendable {
    let id: Int64
    let source: String
    let output: String
    let direction: String
    let model: String
    let createdAt: Double

    var directionValue: TranslationDirection { TranslationDirection.from(key: direction) }
}

/// OS 同梱 libsqlite3 を使うローカル履歴ストア。actor で DB アクセスを直列化する。
actor HistoryStore {
    static let shared = HistoryStore()

    private var db: OpaquePointer?

    // SQLite に文字列をコピーさせる destructor（Swift String の寿命に依存しない）
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    init() {
        let url = Self.databaseURL()
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.write("HistoryStore: open failed at \(url.path)")
            return
        }
        let createSQL = """
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            output TEXT NOT NULL,
            direction TEXT NOT NULL,
            model TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        sqlite3_exec(db, createSQL, nil, nil, nil)
    }

    private static func databaseURL() -> URL {
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser)
            .appendingPathComponent("com.d0ne1s.translate", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.sqlite")
    }

    func insert(source: String, output: String, direction: String, model: String, createdAt: Double) {
        // 直前と同一（source, output）なら重複登録しない
        if let latest = recent(limit: 1).first, latest.source == source, latest.output == output {
            return
        }
        let sql = "INSERT INTO history (source, output, direction, model, created_at) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, output, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, direction, -1, Self.transient)
        sqlite3_bind_text(stmt, 4, model, -1, Self.transient)
        sqlite3_bind_double(stmt, 5, createdAt)
        sqlite3_step(stmt)
    }

    func recent(limit: Int) -> [HistoryEntry] {
        query("SELECT id, source, output, direction, model, created_at FROM history ORDER BY id DESC LIMIT ?;") { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
    }

    func search(_ text: String, limit: Int) -> [HistoryEntry] {
        let like = "%\(text)%"
        return query("SELECT id, source, output, direction, model, created_at FROM history WHERE source LIKE ? OR output LIKE ? ORDER BY id DESC LIMIT ?;") { stmt in
            sqlite3_bind_text(stmt, 1, like, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, like, -1, Self.transient)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        }
    }

    // MARK: - private

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void) -> [HistoryEntry] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var results: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(HistoryEntry(
                id: sqlite3_column_int64(stmt, 0),
                source: column(stmt, 1),
                output: column(stmt, 2),
                direction: column(stmt, 3),
                model: column(stmt, 4),
                createdAt: sqlite3_column_double(stmt, 5)
            ))
        }
        return results
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }
}
