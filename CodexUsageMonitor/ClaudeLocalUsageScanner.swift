import Foundation
import CoreFoundation

struct ClaudeLocalUsageSnapshot {
    let daily: [ClaudeUsageDay]
    let models: [ClaudeModelUsage]
    let fileCount: Int
    let unreadableFiles: Int
    let skippedRecords: Int
    let fetchedAt: Date
    var dailyModels: [String: [ClaudeModelUsage]] = [:]
    var hourly: [ClaudeUsageHour] = []
    var requestCount: Int { daily.reduce(0) { $0 + $1.requests } }
    var tokens: Int { daily.reduce(0) { $0 + $1.tokens } }
    var inputTokens: Int { daily.reduce(0) { $0 + $1.input } }
    var outputTokens: Int { daily.reduce(0) { $0 + $1.output } }
    var cacheReadTokens: Int { daily.reduce(0) { $0 + $1.cacheRead } }
    var cacheWriteTokens: Int { daily.reduce(0) { $0 + $1.cacheWrite } }
    var cost: Double? { let values = daily.compactMap(\.cost); return values.isEmpty ? nil : values.reduce(0, +) }
    var coverage: CodexCostCoverage { CodexCostCoverage.combining(daily.map(\.coverage)) }
    var hasData: Bool { requestCount > 0 }
    var today: ClaudeUsageDay? { daily.last }
}

struct ClaudeUsageHour {
    let day: String
    let weekday: Int
    let hour: Int
    var tokens = 0
}

extension ClaudeLocalUsageSnapshot {
    func period(_ dayCount: Int) -> ClaudeLocalUsageSnapshot {
        let days = Array(daily.suffix(max(1, min(30, dayCount))))
        let keys = Set(days.map(\.id))
        var periodModels: [String: ClaudeModelUsage] = [:]
        for key in keys {
            for model in dailyModels[key] ?? [] {
                var combined = periodModels[model.id] ?? ClaudeModelUsage(id: model.id)
                combined.tokens += model.tokens; combined.requests += model.requests; combined.pricedTokens += model.pricedTokens
                if let cost = model.cost { combined.cost = (combined.cost ?? 0) + cost }
                periodModels[model.id] = combined
            }
        }
        return ClaudeLocalUsageSnapshot(daily: days,
            models: periodModels.values.sorted { $0.tokens == $1.tokens ? $0.id < $1.id : $0.tokens > $1.tokens },
            fileCount: fileCount, unreadableFiles: unreadableFiles, skippedRecords: skippedRecords, fetchedAt: fetchedAt,
            dailyModels: dailyModels.filter { keys.contains($0.key) }, hourly: hourly.filter { keys.contains($0.day) })
    }
}

struct ClaudeUsageDay: Identifiable {
    let id: String
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var requests = 0
    var cost: Double? = nil
    var pricedTokens = 0
    var pricedRequests = 0
    var tokens: Int { input + output + cacheRead + cacheWrite }
    var coverage: CodexCostCoverage {
        CodexCostCoverage(pricedTokens: pricedTokens, totalTokens: tokens, pricedRequests: pricedRequests, totalRequests: requests)
    }
}

struct ClaudeModelUsage: Identifiable {
    let id: String
    var tokens = 0
    var requests = 0
    var cost: Double? = nil
    var pricedTokens = 0
}

/// Native Claude CLI/Desktop metadata only. Parsed records are cached in memory by file stamp;
/// prompt/tool content is discarded and no transcript or credential is uploaded or persisted.
actor ClaudeLocalUsageScanner {
    struct Record {
        let key: String
        let date: Date
        let model: String
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let hourCacheWrite: Int
        let fast: Bool
        var tokens: Int { input + output + cacheRead + cacheWrite }
    }
    private struct FileCache {
        let date: Date
        let size: Int
        let records: [Record]
        let skipped: Int
    }
    private var cache: [String: FileCache] = [:]

    static func roots(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return [URL(fileURLWithPath: custom).appendingPathComponent("projects")]
        }
        return [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects"),
            home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"),
            home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")]
    }

    func scan(roots: [URL] = ClaudeLocalUsageScanner.roots(), now: Date = Date()) async throws -> ClaudeLocalUsageSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        var paths: Set<String> = []
        var files: [URL] = []
        var unreadable = 0
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [], errorHandler: { _, _ in unreadable += 1; return true }) else { unreadable += 1; continue }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                let resolved = url.resolvingSymlinksInPath()
                if paths.insert(resolved.path).inserted { files.append(resolved) }
            }
        }
        cache = cache.filter { paths.contains($0.key) }
        var records: [Record] = []
        var skipped = 0
        for file in files.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: file.path)
                let date = attr[.modificationDate] as? Date ?? .distantPast
                let size = attr[.size] as? Int ?? 0
                let cached: FileCache
                if let existing = cache[file.path], existing.date == date, existing.size == size { cached = existing }
                else {
                    let parsed = try Self.read(file, since: start)
                    cached = FileCache(date: date, size: size, records: parsed.0, skipped: parsed.1)
                    cache[file.path] = cached
                }
                records.append(contentsOf: cached.records)
                skipped += cached.skipped
            } catch is CancellationError { throw CancellationError() }
            catch { unreadable += 1 }
        }
        let catalog = records.isEmpty ? nil : await CodexPricingCatalogStore.shared.catalogForScan(now: now)
        return Self.aggregate(records, catalog: catalog, now: now, calendar: calendar,
            fileCount: files.count, unreadable: unreadable, skipped: skipped)
    }

    private static func read(_ file: URL, since start: Date) throws -> ([Record], Int) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var records: [Record] = []
        var buffer = Data()
        var line = 0
        var skipped = 0
        var discarding = false
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            try Task.checkCancellation()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                line += 1
                if !discarding {
                    let data = Data(buffer[..<newline])
                    if let record = parse(data, fallbackKey: file.path + ":" + String(line)) {
                        if record.date >= start { records.append(record) }
                    } else if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["type"] as? String == "assistant" { skipped += 1 }
                }
                buffer.removeSubrange(...newline)
                discarding = false
            }
            if buffer.count > 8 * 1024 * 1024 { buffer.removeAll(keepingCapacity: true); discarding = true; skipped += 1 }
        }
        // A trailing partial line is retried when the file grows; never count incomplete JSON.
        if !discarding, !buffer.isEmpty, let record = parse(buffer, fallbackKey: file.path + ":" + String(line + 1)), record.date >= start { records.append(record) }
        return (records, skipped)
    }

    static func parse(_ data: Data, fallbackKey: String) -> Record? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["type"] as? String == "assistant",
              let message = root["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let timestamp = root["timestamp"] as? String, let date = parseDate(timestamp) else { return nil }
        func count(_ value: Any?) -> Int? {
            guard let value else { return 0 }
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  n.doubleValue >= 0, n.doubleValue <= 1_000_000_000_000, n.doubleValue.rounded(.towardZero) == n.doubleValue else { return nil }
            return n.intValue
        }
        guard let input = count(usage["input_tokens"]), let output = count(usage["output_tokens"]),
              let read = count(usage["cache_read_input_tokens"]), let write = count(usage["cache_creation_input_tokens"]) else { return nil }
        let hourly = (usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"]
        guard let hour = count(hourly) else { return nil }
        guard input + output + read + write > 0 else { return nil }
        if message["stop_reason"] is NSNull && input > 0 && output == 0 && read == 0 && write == 0 { return nil }
        let messageID = message["id"] as? String ?? ""
        let requestID = root["requestId"] as? String ?? ""
        let sessionID = root["sessionId"] as? String ?? ""
        let key: String
        if !messageID.isEmpty && !requestID.isEmpty { key = requestID + ":" + messageID }
        else if !messageID.isEmpty && !sessionID.isEmpty { key = sessionID + ":" + messageID }
        else { key = fallbackKey }
        return Record(key: key, date: date, model: model, input: input, output: output, cacheRead: read,
            cacheWrite: write, hourCacheWrite: hour, fast: usage["speed"] as? String == "fast" || message["speed"] as? String == "fast")
    }

    static func aggregate(_ records: [Record], catalog: CodexPricingCatalog?, now: Date, calendar: Calendar = .current,
                          fileCount: Int = 0, unreadable: Int = 0, skipped: Int = 0) -> ClaudeLocalUsageSnapshot {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        var days: [ClaudeUsageDay] = (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 29, to: today).map { ClaudeUsageDay(id: formatter.string(from: $0)) }
        }
        let indices = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.id, $0.offset) })
        var unique: [String: Record] = [:]
        for record in records where record.date <= now {
            if let old = unique[record.key], old.date > record.date || (old.date == record.date && old.tokens > record.tokens) { continue }
            unique[record.key] = record
        }
        var models: [String: ClaudeModelUsage] = [:]
        var dailyModels: [String: [String: ClaudeModelUsage]] = [:]
        var hourly: [String: ClaudeUsageHour] = [:]
        for record in unique.values {
            guard let index = indices[formatter.string(from: record.date)] else { continue }
            let price = estimate(record, catalog: catalog)
            days[index].input += record.input; days[index].output += record.output
            days[index].cacheRead += record.cacheRead; days[index].cacheWrite += record.cacheWrite
            days[index].requests += 1
            var model = models[record.model] ?? ClaudeModelUsage(id: record.model)
            model.tokens += record.tokens; model.requests += 1
            if let price {
                days[index].cost = (days[index].cost ?? 0) + price
                days[index].pricedTokens += record.tokens; days[index].pricedRequests += 1
                model.cost = (model.cost ?? 0) + price; model.pricedTokens += record.tokens
            }
            models[record.model] = model
            let dayKey = days[index].id
            var dailyModel = dailyModels[dayKey]?[record.model] ?? ClaudeModelUsage(id: record.model)
            dailyModel.tokens += record.tokens; dailyModel.requests += 1
            if let price { dailyModel.cost = (dailyModel.cost ?? 0) + price; dailyModel.pricedTokens += record.tokens }
            dailyModels[dayKey, default: [:]][record.model] = dailyModel
            let hour = calendar.component(.hour, from: record.date)
            let hourKey = dayKey + "-" + String(hour)
            var bucket = hourly[hourKey] ?? ClaudeUsageHour(day: dayKey,
                weekday: (calendar.component(.weekday, from: record.date) + 5) % 7, hour: hour)
            bucket.tokens += record.tokens
            hourly[hourKey] = bucket
        }
        return ClaudeLocalUsageSnapshot(daily: days, models: models.values.sorted { $0.tokens == $1.tokens ? $0.id < $1.id : $0.tokens > $1.tokens },
            fileCount: fileCount, unreadableFiles: unreadable, skippedRecords: skipped, fetchedAt: now,
            dailyModels: dailyModels.mapValues { Array($0.values) }, hourly: hourly.keys.sorted().compactMap { hourly[$0] })
    }

    static func estimate(_ record: Record, catalog: CodexPricingCatalog?) -> Double? {
        let model = record.model.replacingOccurrences(of: "anthropic/", with: "")
        guard let price = catalog?.providers["anthropic"]?.lookup(model: model), !record.fast else { return nil }
        let long = price.threshold.map { record.input + record.cacheRead + record.cacheWrite > $0 } ?? false
        guard let input = long ? price.longInput : price.input,
              let output = long ? price.longOutput : price.output else { return nil }
        let read = long ? price.longCachedRead : price.cachedRead
        let write = long ? price.longCacheWrite : price.cacheWrite
        // cache_creation_input_tokens includes both TTLs. Charge 1h writes at 2x
        // the effective input rate, and only the remaining writes at the 5m rate.
        // Anthropic prompt-caching pricing; same split/clamping as CodexBar.
        let oneHourWrites = min(max(0, record.hourCacheWrite), record.cacheWrite)
        let fiveMinuteWrites = record.cacheWrite - oneHourWrites
        guard record.cacheRead == 0 || read != nil, fiveMinuteWrites == 0 || write != nil else { return nil }
        guard [input, output, read ?? 0, write ?? 0].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let cost = Double(record.input) * input + Double(record.output) * output
            + Double(record.cacheRead) * (read ?? 0)
            + Double(fiveMinuteWrites) * (write ?? 0) + Double(oneHourWrites) * input * 2
        return cost.isFinite && cost >= 0 ? cost : nil
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: text)
    }
}
