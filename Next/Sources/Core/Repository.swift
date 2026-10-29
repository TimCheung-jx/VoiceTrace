import Foundation
import SQLite3

// 单一存储入口：事务写入文档与历史版本，旧版资料不会被就地改写。
final class VTRepository {
  private var db: OpaquePointer?
  let root: URL
  init(root: URL) throws {
    self.root = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    guard sqlite3_open(root.appendingPathComponent("workspace.sqlite").path, &db) == SQLITE_OK
    else { throw VTError.message("无法打开本地资料库") }
    let version = try statement("PRAGMA user_version")
    let step = sqlite3_step(version)
    let schema = step == SQLITE_ROW ? sqlite3_column_int(version, 0) : 0
    sqlite3_finalize(version)
    guard schema <= 1 else { throw VTError.message("资料库来自更新版本，请使用对应新版应用，未改写数据") }
    try exec(
      "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY,payload BLOB NOT NULL,modified REAL NOT NULL); CREATE TABLE IF NOT EXISTS revisions(id TEXT PRIMARY KEY,document_id TEXT NOT NULL,payload BLOB NOT NULL,reason TEXT NOT NULL,created REAL NOT NULL); PRAGMA user_version=1;"
    )
  }
  deinit { sqlite3_close(db) }
  private func exec(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw VTError.message("本地资料库操作失败；请检查磁盘空间")
    }
  }
  private func statement(_ sql: String) throws -> OpaquePointer {
    var s: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s = s else {
      throw VTError.message("本地资料库语句失败")
    }
    return s
  }
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private func text(_ value: String, _ index: Int32, _ s: OpaquePointer) {
    sqlite3_bind_text(s, index, value, -1, transient)
  }
  private func blob(_ value: Data, _ index: Int32, _ s: OpaquePointer) {
    _ = value.withUnsafeBytes {
      sqlite3_bind_blob(s, index, $0.baseAddress, Int32(value.count), transient)
    }
  }
  func save(_ doc: VTDocument, reason: String? = nil) throws {
    let payload = try JSONEncoder().encode(doc)
    try exec("BEGIN IMMEDIATE")
    do {
      if let reason = reason, var old = try load(doc.id) {
        old.cache = [:]
        let s = try statement("INSERT INTO revisions VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(s) }
        text(UUID().uuidString, 1, s)
        text(doc.id, 2, s)
        blob(try JSONEncoder().encode(old), 3, s)
        text(reason, 4, s)
        sqlite3_bind_double(s, 5, Date().timeIntervalSince1970)
        guard sqlite3_step(s) == SQLITE_DONE else { throw VTError.message("无法保存修订历史") }
      }
      let s = try statement(
        "INSERT INTO documents VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,modified=excluded.modified"
      )
      defer { sqlite3_finalize(s) }
      text(doc.id, 1, s)
      blob(payload, 2, s)
      sqlite3_bind_double(s, 3, Date().timeIntervalSince1970)
      guard sqlite3_step(s) == SQLITE_DONE else { throw VTError.message("本地保存失败") }
      try exec("COMMIT")
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }
  func load(_ id: String) throws -> VTDocument? {
    let s = try statement("SELECT payload FROM documents WHERE id=?")
    defer { sqlite3_finalize(s) }
    text(id, 1, s)
    if sqlite3_step(s) == SQLITE_ROW { return try read(s, 0) }
    return nil
  }
  private func read(_ s: OpaquePointer, _ col: Int32) throws -> VTDocument {
    guard let bytes = sqlite3_column_blob(s, col) else { throw VTError.message("文档数据为空") }
    return try JSONDecoder().decode(
      VTDocument.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, col))))
  }
  func list() throws -> [VTDocument] {
    let s = try statement("SELECT payload FROM documents ORDER BY modified DESC")
    defer { sqlite3_finalize(s) }
    var docs: [VTDocument] = []
    while sqlite3_step(s) == SQLITE_ROW { docs.append(try read(s, 0)) }
    return docs
  }
  func history(_ id: String) throws -> [(String, String, VTDocument)] {
    let s = try statement(
      "SELECT id,reason,payload FROM revisions WHERE document_id=? ORDER BY created DESC LIMIT 100")
    defer { sqlite3_finalize(s) }
    text(id, 1, s)
    var rows: [(String, String, VTDocument)] = []
    while sqlite3_step(s) == SQLITE_ROW {
      rows.append(
        (
          String(cString: sqlite3_column_text(s, 0)), String(cString: sqlite3_column_text(s, 1)),
          try read(s, 2)
        ))
    }
    return rows
  }
  func audioFolder(_ id: String) throws -> URL {
    let url = root.appendingPathComponent("audio").appendingPathComponent(id)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
