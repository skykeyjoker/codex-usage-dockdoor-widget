import Foundation
import SQLite3

struct ProviderWorkSnapshot: Sendable {
    let conversations: [ProviderConversation]
    let scannedCount: Int
    let unavailableSources: Int
    let fetchedAt: Date
    var projectPaths: [String] { Array(Set(conversations.compactMap(\.projectPath))).sorted() }
}

struct ProviderConversation: Identifiable, Sendable {
    let id: String
    let title: String
    let projectPath: String?
    let modifiedAt: Date
    let isArchived: Bool
    var contextPercent: Double? = nil
    var linesAdded: Int? = nil
    var linesRemoved: Int? = nil
    var projectName: String { projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? CodexLocalization.text("未关联项目", "No project") }
}

/// Reads bounded local metadata only. Does not query credentials, modify databases, or persist conversation content.
actor ProviderWorkScanner {
    private struct CachedClaude {
        let modifiedAt: Date
        let size: Int
        let conversation: ProviderConversation?
    }
    private var claudeCache: [String: CachedClaude] = [:]

    func scanClaude(roots: [URL] = ClaudeLocalUsageScanner.roots(), now: Date = Date()) -> ProviderWorkSnapshot {
        var files: [(URL, Date, Int)] = []
        var seen = Set<String>()
        var unavailable = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles], errorHandler: { _, _ in unavailable += 1; return true }) else { unavailable += 1; continue }
            for case let url as URL in entries {
                if url.lastPathComponent == "subagents" { entries.skipDescendants(); continue }
                guard url.pathExtension == "jsonl", UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                      seen.insert(url.resolvingSymlinksInPath().path).inserted,
                      let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                files.append((url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
            }
        }
        let candidates = files.sorted { $0.1 > $1.1 }.prefix(200)
        let retained = Set(candidates.map { $0.0.path })
        claudeCache = claudeCache.filter { retained.contains($0.key) }
        var conversations: [String: ProviderConversation] = [:]
        for (url, modifiedAt, size) in candidates {
            guard !Task.isCancelled else { break }
            let conversation: ProviderConversation?
            if let cached = claudeCache[url.path], cached.modifiedAt == modifiedAt, cached.size == size { conversation = cached.conversation }
            else {
                do {
                    conversation = try Self.readClaude(url, modifiedAt: modifiedAt)
                    claudeCache[url.path] = CachedClaude(modifiedAt: modifiedAt, size: size, conversation: conversation)
                } catch { unavailable += 1; continue }
            }
            if let conversation, conversations[conversation.id] == nil { conversations[conversation.id] = conversation }
        }
        return ProviderWorkSnapshot(conversations: conversations.values.sorted { $0.modifiedAt > $1.modifiedAt },
            scannedCount: candidates.count, unavailableSources: unavailable, fetchedAt: now)
    }

    static func readClaude(_ url: URL, modifiedAt: Date) throws -> ProviderConversation? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 1024 * 1024
        let prefix = try handle.read(upToCount: limit) ?? Data()
        let size = try handle.seekToEnd()
        var chunks = [prefix]
        if size > UInt64(limit) {
            try handle.seek(toOffset: max(UInt64(limit), size - UInt64(limit)))
            chunks.append(try handle.read(upToCount: limit) ?? Data())
        }
        return decodeClaude(chunks, id: url.deletingPathExtension().lastPathComponent, modifiedAt: modifiedAt)
    }

    static func decodeClaude(_ chunks: [Data], id: String, modifiedAt: Date) -> ProviderConversation? {
        var path: String?
        var title: String?
        var firstPrompt: String?
        var latest: Date?
        var hasMainSession = false
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        for chunk in chunks {
            for line in chunk.split(separator: 0x0A) {
                guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      row["isSidechain"] as? Bool != true,
                      row["sessionId"] as? String == id else { continue }
                hasMainSession = true
                if let cwd = row["cwd"] as? String, cwd.hasPrefix("/") { path = cwd }
                if row["type"] as? String == "custom-title", let custom = normalizedTitle(row["customTitle"] as? String) { title = custom }
                if row["type"] as? String == "user", row["isMeta"] as? Bool != true, firstPrompt == nil,
                   let message = row["message"] as? [String: Any] {
                    if let text = message["content"] as? String { firstPrompt = normalizedTitle(text) }
                    else if let blocks = message["content"] as? [[String: Any]] {
                        firstPrompt = normalizedTitle(blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String)
                    }
                }
                if let raw = row["timestamp"] as? String, let date = formatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                    latest = max(latest ?? date, date)
                }
            }
        }
        guard hasMainSession else { return nil }
        return ProviderConversation(id: id, title: title ?? firstPrompt ?? CodexLocalization.text("未命名对话", "Untitled conversation"),
            projectPath: path, modifiedAt: latest ?? modifiedAt, isArchived: false)
    }

    func scanCursor(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User"), now: Date = Date()) -> ProviderWorkSnapshot {
        var records: [String: ProviderConversation] = [:]
        var workspacePaths: [String: String] = [:]
        var unavailable = 0
        let workspaces = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("workspaceStorage"), includingPropertiesForKeys: nil)) ?? []
        for workspace in workspaces {
            if let data = try? Data(contentsOf: workspace.appendingPathComponent("workspace.json")),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                workspacePaths[workspace.lastPathComponent] = Self.localPath(object["folder"] ?? object["workspace"])
            }
        }
        let global = root.appendingPathComponent("globalStorage/state.vscdb")
        var headersAvailable = false
        if FileManager.default.fileExists(atPath: global.path) {
            do {
                let database = try WorkReadOnlyDatabase(global)
                if database.hasTable("composerHeaders") {
                    headersAvailable = true
                    for data in try database.values("SELECT value FROM composerHeaders WHERE COALESCE(isSubagent,0)=0 ORDER BY recency DESC LIMIT 500") {
                        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let record = Self.decodeCursor(object, workspacePaths: workspacePaths) { records[record.id] = record }
                    }
                }
            } catch { unavailable += 1 }
        }
        // Older Cursor versions retain their composer headers per workspace.
        if !headersAvailable {
            for workspace in workspaces {
                let url = workspace.appendingPathComponent("state.vscdb")
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    let database = try WorkReadOnlyDatabase(url)
                    for data in try database.values("SELECT value FROM ItemTable WHERE key='composer.composerData'") {
                        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let headers = object["allComposers"] as? [[String: Any]] else { continue }
                        for header in headers {
                            if let record = Self.decodeCursor(header, workspacePaths: workspacePaths, fallbackPath: workspacePaths[workspace.lastPathComponent]),
                               records[record.id] == nil || record.modifiedAt > records[record.id]!.modifiedAt { records[record.id] = record }
                        }
                    }
                } catch { unavailable += 1 }
            }
        }
        let conversations = records.values.sorted { $0.modifiedAt > $1.modifiedAt }
        return ProviderWorkSnapshot(conversations: conversations, scannedCount: conversations.count, unavailableSources: unavailable, fetchedAt: now)
    }

    static func decodeCursor(_ object: [String: Any], workspacePaths: [String: String] = [:], fallbackPath: String? = nil) -> ProviderConversation? {
        guard let id = object["composerId"] as? String, UUID(uuidString: id) != nil,
              object["isDraft"] as? Bool != true, object["isSubagent"] as? Bool != true,
              object["isBestOfNSubcomposer"] as? Bool != true else { return nil }
        guard let timestamp = (object["lastUpdatedAt"] as? NSNumber ?? object["createdAt"] as? NSNumber)?.doubleValue,
              timestamp.isFinite, timestamp > 0 else { return nil }
        let workspace = object["workspaceIdentifier"] as? [String: Any]
        let path = localPath(workspace?["uri"]) ?? (workspace?["id"] as? String).flatMap { workspacePaths[$0] } ?? fallbackPath
        let context = (object["contextUsagePercent"] as? NSNumber)?.doubleValue
        return ProviderConversation(id: id, title: normalizedTitle(object["name"] as? String) ?? CodexLocalization.text("未命名对话", "Untitled conversation"),
            projectPath: path, modifiedAt: Date(timeIntervalSince1970: timestamp / 1000), isArchived: object["isArchived"] as? Bool ?? false,
            contextPercent: context.flatMap { $0.isFinite && $0 >= 0 && $0 <= 100 ? $0 : nil },
            linesAdded: (object["totalLinesAdded"] as? NSNumber)?.intValue,
            linesRemoved: (object["totalLinesRemoved"] as? NSNumber)?.intValue)
    }

    static func localPath(_ value: Any?) -> String? {
        if let uri = value as? [String: Any] {
            guard uri["scheme"] as? String == "file" else { return nil }
            return localPath(uri["fsPath"] ?? uri["external"] ?? uri["path"])
        }
        guard let raw = value as? String else { return nil }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw).standardizedFileURL.path }
        guard let url = URL(string: raw), url.isFileURL else { return nil }
        return url.standardizedFileURL.path
    }

    static func normalizedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(160))
    }
}

private final class WorkReadOnlyDatabase {
    private var handle: OpaquePointer?
    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); handle = nil; throw URLError(.cannotOpenFile)
        }
        sqlite3_busy_timeout(handle, 250)
    }
    deinit { sqlite3_close(handle) }
    func hasTable(_ name: String) -> Bool {
        // Only constant table names supplied by the scanner.
        (try? values("SELECT name FROM sqlite_master WHERE type='table' AND name='\(name)'"))?.isEmpty == false
    }
    func values(_ query: String) throws -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { throw URLError(.cannotParseResponse) }
        defer { sqlite3_finalize(statement) }
        var values: [Data] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let size = Int(sqlite3_column_bytes(statement, 0))
            guard size <= 4 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            if size > 0, let bytes = sqlite3_column_blob(statement, 0) { values.append(Data(bytes: bytes, count: size)) }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw URLError(.cannotLoadFromNetwork) }
        return values
    }
}
