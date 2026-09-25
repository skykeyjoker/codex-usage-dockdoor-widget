import AppKit
import SwiftUI
import SQLite3

@main
enum ClaudeUsageTests {
    @MainActor
    static func main() async throws {
        try await testInsightsData()
        try await testProviderPages()
        try await testLocalAnalytics()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = Data(#"{"five_hour":{"utilization":34,"resets_at":"2027-01-15T09:00:00.123Z"},"seven_day":{"utilization":81,"resets_at":"2027-01-21T09:00:00Z"},"seven_day_sonnet":null,"seven_day_opus":{"utilization":0},"extra_usage":{"is_enabled":false}}"#.utf8)
        let usage = try ClaudeUsageService.decode(fixture, plan: "max", now: now)
        precondition(usage.windows.count == 3)
        precondition(usage.sessionWindow?.remainingPercent == 66)
        precondition(usage.weeklyWindow?.remainingPercent == 19)
        precondition(usage.sessionWindow?.resetAt != nil && usage.weeklyWindow?.resetAt != nil)
        precondition(usage.windows.last?.remainingPercent == 100)
        for json in ["{}", #"{"seven_day":null}"#, #"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":-1}}"#] {
            do { _ = try ClaudeUsageService.decode(Data(json.utf8)); fatalError("Invalid quota accepted") }
            catch ClaudeUsageError.unavailable { }
        }
        let overflow = try ClaudeUsageService.decode(Data(#"{"five_hour":{"utilization":130}}"#.utf8))
        precondition(overflow.sessionWindow?.remainingPercent == 0)
        let partial = try ClaudeUsageService.decode(Data(#"{"five_hour":{"utilization":"bad"},"seven_day":{"utilization":0,"resets_at":"bad"}}"#.utf8))
        precondition(partial.sessionWindow == nil && partial.weeklyWindow?.remainingPercent == 100)
        precondition(partial.weeklyWindow?.resetAt == nil)
        let scoped = try ClaudeUsageService.decode(Data(#"{"limits":[{"group":"weekly","kind":"weekly_scoped","percent":0,"is_active":false,"resets_at":"2026-09-28T06:59:59.919987+00:00","scope":{"model":{"display_name":"Fable","id":null}}},{"group":"weekly","kind":"weekly_scoped","percent":20,"scope":{"model":{"display_name":"Renamed","id":"fable"}}},{"group":"weekly","kind":"weekly_all","percent":99,"scope":{"model":{"display_name":"All models"}}},{"group":"monthly","kind":"weekly_scoped","percent":99,"scope":{"model":{"display_name":"Wrong window"}}}]}"#.utf8))
        precondition(scoped.windows.count == 1 && scoped.windows[0].remainingPercent == 100)
        precondition(scoped.windows[0].id == "scoped_fable" && scoped.windows[0].title.contains("Fable"))
        precondition(scoped.windows[0].resetAt != nil)
        let credential = try ClaudeUsageService.parseCredential(Data(#"{"claudeAiOauth":{"accessToken":"test-only","expiresAt":1900000000000,"subscriptionType":"pro"}}"#.utf8), now: now)
        precondition(credential.plan == "pro")
        do {
            _ = try ClaudeUsageService.parseCredential(Data(#"{"claudeAiOauth":{"accessToken":"test-only","expiresAt":1}}"#.utf8), now: now)
            fatalError("Expired credentials accepted")
        } catch ClaudeUsageError.expired { }
        do {
            _ = try ClaudeUsageService.parseCredential(Data(#"{"apiKey":"test-only"}"#.utf8), now: now)
            fatalError("API key treated as subscription")
        } catch ClaudeUsageError.notSignedIn { }
        precondition(ClaudeUsageService.retryDate("120", now: now) == now.addingTimeInterval(120))
        precondition(ClaudeUsageService.retryDate("invalid", now: now) == now.addingTimeInterval(300))
        precondition(CodexDockProvider.resolve(title: "Codex + Cursor") == .both)
        precondition(CodexDockProvider.resolve(title: "全部服务") == .all)
        print("PASS: quota parsing, absent vs zero, partial response, scoped limits, credentials, expiry, rate-limit backoff and setting compatibility")
        if CommandLine.arguments.contains("--live-insights") {
            let local = try await ClaudeLocalUsageScanner().scan()
            precondition(local.hourly.reduce(0) { $0 + $1.tokens } == local.tokens)
            for count in [1,7,30] {
                let period = local.period(count)
                precondition(period.models.reduce(0) { $0 + $1.tokens } == period.tokens)
                print("Live Claude \(count)d: \(period.requestCount) requests, \(period.hourly.count) hour buckets, \(period.models.count) models")
            }
            let cursor = try await CursorUsageService().fetch()
            print("Live Cursor official: \(cursor.daily.count) active days, \(cursor.topModels.count) models, history available=\(cursor.activityError == nil), partial=\(cursor.activityIsPartial == true)")
            precondition(cursor.activityError == nil, "Cursor official history failed")
        }
        if CommandLine.arguments.contains("--live-provider-pages") {
            let scanner = ProviderWorkScanner()
            for provider in [UsageProvider.claude, .cursor] {
                let local = provider == .claude ? await scanner.scanClaude() : await scanner.scanCursor()
                print("Live \(provider.title): \(local.conversations.count) conversations, \(local.projectPaths.count) projects, \(local.unavailableSources) unavailable sources, context samples: \(local.conversations.filter { $0.contextPercent != nil }.count)")
                let status = try await ProviderStatusService().fetch(provider)
                print("Live \(provider.title) official status: \(status.components.count) components, \(status.incidents.count) incidents")
            }
        }
        if CommandLine.arguments.contains("--live-local") {
            let live = try await ClaudeLocalUsageScanner().scan()
            print("Live local files: \(live.fileCount), requests: \(live.requestCount), tokens: \(live.tokens)")
            for day in live.daily.suffix(2) {
                print("Day \(day.id): tokens=\(day.tokens), costUSD=\(day.cost.map { String(format: "%.6f", $0) } ?? "nil"), pricedRequests=\(day.pricedRequests)/\(day.requests), pricedTokens=\(day.pricedTokens)/\(day.tokens)")
            }
            print("30d costUSD=\(live.cost.map { String(format: "%.6f", $0) } ?? "nil"), coverage=\(live.coverage.tokenPercent ?? 0)%")
        }
        if CommandLine.arguments.contains("--live") {
            do {
                let live = try await ClaudeUsageService().fetch()
                print("Live Claude quota: \(live.windows.count) windows; email available: \(live.accountEmail?.contains("@") == true)")
                let local = try await ClaudeLocalUsageScanner().scan()
                print("Live Claude history: \(local.fileCount) files, \(local.requestCount) requests, \(local.unreadableFiles) unreadable")
            } catch {
                print("Live Claude quota unavailable: \(error.localizedDescription)")
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            try await renderFixtures(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            try await testGeometryObserverIsReadOnly()
        }
    }

    static func testInsightsData() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = Date(timeIntervalSince1970: 1_790_294_400)
        func record(_ key: String, day: Int, tokens: Int) -> ClaudeLocalUsageScanner.Record {
            ClaudeLocalUsageScanner.Record(key:key,date:calendar.date(byAdding:.day,value:-day,to:now)!,model:day == 0 ? "today-model" : "older-model",
                input:tokens,output:20,cacheRead:30,cacheWrite:0,hourCacheWrite:0,fast:false)
        }
        let recent = record("same",day:0,tokens:100)
        let records = [recent,recent,record("yesterday",day:1,tokens:200),record("old",day:15,tokens:300)]
        let snapshot = ClaudeLocalUsageScanner.aggregate(records,catalog:nil,now:now,calendar:calendar)
        precondition(snapshot.requestCount == 3 && snapshot.hourly.reduce(0) { $0 + $1.tokens } == snapshot.tokens)
        precondition(snapshot.period(1).requestCount == 1 && snapshot.period(7).requestCount == 2 && snapshot.period(30).requestCount == 3)
        for count in [1,7,30] {
            let period = snapshot.period(count)
            precondition(period.tokens == period.models.reduce(0) { $0 + $1.tokens })
            precondition(period.tokens == period.hourly.reduce(0) { $0 + $1.tokens })
            precondition(period.cost == nil && !period.coverage.isComplete)
        }
        precondition(snapshot.period(1).models.map(\.id) == ["today-model"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let path = root.appendingPathComponent("cursor.vscdb").path
        var database: OpaquePointer?
        precondition(sqlite3_open(path,&database) == SQLITE_OK)
        let payload = try JSONSerialization.data(withJSONObject:["sub":"test-user","exp":Date().timeIntervalSince1970+3600]).base64EncodedString()
        let sql = "CREATE TABLE ItemTable(key TEXT,value TEXT); INSERT INTO ItemTable VALUES('cursorAuth/accessToken','test.\(payload).test');"
        precondition(sqlite3_exec(database,sql,nil,nil,nil) == SQLITE_OK)
        sqlite3_close(database)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InsightsFixtureURLProtocol.self]
        let session = URLSession(configuration:config)
        defer { session.invalidateAndCancel() }
        let service = CursorUsageService(authStore:CursorAppAuthStore(databasePath:path),session:session)
        InsightsFixtureURLProtocol.mode = 0
        let failed = try await service.fetch()
        precondition(failed.activityError != nil && !failed.quotaWindows.isEmpty)
        InsightsFixtureURLProtocol.mode = 1
        let empty = try await service.fetch()
        precondition(empty.activityError == nil && empty.daily.isEmpty && empty.activityIsPartial == false)
        InsightsFixtureURLProtocol.mode = 2
        let partial = try await service.fetch()
        precondition(partial.activityError == nil && partial.activityIsPartial == true)
        print("PASS: Claude period/model/hour consistency and deduplication; Cursor failed vs empty vs partial official history")
    }

    static func testProviderPages() async throws {
        let now = Date()
        let status = try ProviderStatusService.decode(Data(#"{"status":{"indicator":"minor"},"components":[{"id":"group","name":"Group","status":"operational","group":true},{"id":"code","name":"Claude Code","status":"degraded_performance","position":2},{"id":"api","name":"API","status":"operational","position":1}],"incidents":[{"id":"active","name":"Degradation","status":"monitoring"},{"id":"old","name":"Resolved","status":"resolved"}]}"#.utf8))
        precondition(status.indicator == .degraded && status.components.map(\.id) == ["api", "code"] && status.incidents.count == 1)
        let normal = (0..<12).map { OpenAIStatusComponent(id:"normal-\($0)",name:"Normal \($0)",indicator:.operational) }
        let failed = (0..<7).map { OpenAIStatusComponent(id:"failed-\($0)",name:"Failed \($0)",indicator:.degraded) }
        let snapshot = ProviderServiceStatus(indicator:.degraded,components:normal + failed,incidents:[],fetchedAt:now)
        precondition(snapshot.previewComponents.map(\.id) == failed.map(\.id), "Affected services must never be hidden by the preview limit")
        let unknown = OpenAIStatusComponent(id:"unknown",name:"Unknown",indicator:.unknown)
        let partial = ProviderServiceStatus(indicator:.unknown,components:normal+[unknown],incidents:[],fetchedAt:now)
        precondition(partial.previewComponents.count == 6 && partial.previewComponents.first?.id == "unknown")
        let openAI = OpenAIStatusSnapshot(overallIndicator:.operational,description:nil,groups:[
            OpenAIStatusGroup(id:"chat",name:"ChatGPT",components:[normal[0]]),
            OpenAIStatusGroup(id:"code",name:"Codex",components:[normal[0]])],fetchedAt:now)
        let mapped = ProviderServiceStatus.openAI(openAI,visibleGroups:["ChatGPT","Codex"])
        precondition(Set(mapped.components.map(\.id)).count == 2 && mapped.components.first?.name == "Codex · Normal 0")
        precondition(ProviderServiceStatus.openAI(openAI,visibleGroups:["Codex"]).components.count == 1)
        print("PASS: collapsed status preserves every affected/unknown service; OpenAI grouping and card visibility retained")
        let id = UUID().uuidString
        let lines: [[String: Any]] = [
            ["type":"user", "sessionId":id, "cwd":"/tmp/Example Project", "timestamp":ISO8601DateFormatter().string(from:now), "message":["content":"First prompt"]],
            ["type":"custom-title", "sessionId":id,"customTitle":"Renamed task"],
            ["type":"user", "sessionId":id,"isSidechain":true,"cwd":"/wrong"],
            ["type":"custom-title", "sessionId":UUID().uuidString,"customTitle":"Wrong session"]]
        let data = try lines.map { try JSONSerialization.data(withJSONObject:$0) + Data([10]) }.reduce(Data(),+)
        let conversation = ProviderWorkScanner.decodeClaude([data],id:id,modifiedAt:now)
        precondition(conversation?.title == "Renamed task" && conversation?.projectPath == "/tmp/Example Project")
        var header: [String:Any] = ["composerId":id,"name":"Cursor task","createdAt":now.timeIntervalSince1970*1000,"lastUpdatedAt":now.timeIntervalSince1970*1000,"contextUsagePercent":42.5,"workspaceIdentifier":["uri":["scheme":"file","path":"/tmp/Project"]],"totalLinesAdded":12,"totalLinesRemoved":3]
        let cursor = ProviderWorkScanner.decodeCursor(header)
        precondition(cursor?.contextPercent == 42.5 && cursor?.linesAdded == 12 && cursor?.projectPath == "/tmp/Project")
        header["isDraft"] = true
        precondition(ProviderWorkScanner.decodeCursor(header) == nil)
        header["isDraft"] = false; header["isSubagent"] = true
        precondition(ProviderWorkScanner.decodeCursor(header) == nil)
        header["isSubagent"] = false
        precondition(ProviderWorkScanner.localPath("vscode-remote://ssh/path") == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let global = root.appendingPathComponent("globalStorage")
        try FileManager.default.createDirectory(at:global,withIntermediateDirectories:true)
        let databaseURL = global.appendingPathComponent("state.vscdb")
        func database(_ url:URL,_ sql:String) throws {
            var db:OpaquePointer?
            precondition(sqlite3_open(url.path,&db) == SQLITE_OK)
            defer {sqlite3_close(db)}
            precondition(sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK)
        }
        let json = String(data:try JSONSerialization.data(withJSONObject:header),encoding:.utf8)!.replacingOccurrences(of:"'",with:"''")
        try database(databaseURL,"CREATE TABLE composerHeaders (value TEXT,isSubagent INTEGER,recency INTEGER); INSERT INTO composerHeaders VALUES ('\(json)',0,10); INSERT INTO composerHeaders VALUES ('\(json)',1,20);")
        let scanner = ProviderWorkScanner()
        let modern = await scanner.scanCursor(root:root)
        precondition(modern.conversations.count == 1 && modern.unavailableSources == 0)
        try FileManager.default.removeItem(at:databaseURL)
        let workspace = root.appendingPathComponent("workspaceStorage/sample")
        try FileManager.default.createDirectory(at:workspace,withIntermediateDirectories:true)
        try Data(#"{"folder":"file:///tmp/Legacy"}"#.utf8).write(to:workspace.appendingPathComponent("workspace.json"))
        try database(workspace.appendingPathComponent("state.vscdb"),"CREATE TABLE ItemTable (key TEXT,value TEXT); INSERT INTO ItemTable VALUES ('composer.composerData','{\"allComposers\":[\(json)]}');")
        let legacy = await scanner.scanCursor(root:root)
        precondition(legacy.conversations.count == 1 && legacy.unavailableSources == 0)
        let claudeRoot = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at:claudeRoot,withIntermediateDirectories:true)
        try data.write(to:claudeRoot.appendingPathComponent(id+".jsonl"))
        let scanned = await scanner.scanClaude(roots:[claudeRoot])
        precondition(scanned.conversations.count == 1 && scanned.projectPaths.count == 1)
        try FileManager.default.removeItem(at:claudeRoot.appendingPathComponent(id+".jsonl"))
        let removed = await scanner.scanClaude(roots:[claudeRoot])
        precondition(removed.conversations.isEmpty)
        print("PASS: official status parsing, Claude titles/session isolation, Cursor modern/legacy read-only indices, draft/subagent exclusion and deleted-file cache eviction")
    }

    static func testLocalAnalytics() async throws {
        precondition(ClaudeUsageService.decodeEmail(Data(#"{"account":{"email":"sample@example.com"}}"#.utf8)) == "sample@example.com")
        precondition(ClaudeUsageService.decodeEmail(Data(#"{"email_address":"top@example.com"}"#.utf8)) == "top@example.com")
        let now = Date()
        let formatter = ISO8601DateFormatter()
        func line(_ messageID: String, _ requestID: String?, _ output: Int, session: String = "session") throws -> Data {
            var root: [String: Any] = ["type": "assistant", "sessionId": session, "timestamp": formatter.string(from: now.addingTimeInterval(-10)),
                "message": ["id": messageID, "model": "claude-test", "stop_reason": "end_turn",
                    "usage": ["input_tokens":100,"output_tokens":output,"cache_read_input_tokens":50,"cache_creation_input_tokens":0]]]
            if let requestID { root["requestId"] = requestID }
            return try JSONSerialization.data(withJSONObject: root)
        }
        let first = try line("m1", "r1", 20)
        let last = try line("m1", "r1", 40)
        let a = ClaudeLocalUsageScanner.parse(first, fallbackKey: "a")!
        let b = ClaudeLocalUsageScanner.parse(last, fallbackKey: "b")!
        let prices = try JSONDecoder().decode(CodexPricingCatalog.self, from: Data(#"{"anthropic":{"models":{"claude-test":{"id":"claude-test","cost":{"input":2,"output":10,"cache_read":0.2,"cache_write":2.5}}}}}"#.utf8))
        let merged = ClaudeLocalUsageScanner.aggregate([a,b,a], catalog: prices, now: now)
        precondition(merged.requestCount == 1 && merged.tokens == 190)
        precondition(abs(merged.cost! - 0.00061) < 0.000000001)
        precondition(merged.daily.count == 30 && merged.today?.requests == 1)
        func cacheRecord(_ oneHour: Int) -> ClaudeLocalUsageScanner.Record {
            ClaudeLocalUsageScanner.Record(key: "cache", date: now, model: "claude-test", input: 100, output: 40,
                cacheRead: 50, cacheWrite: 100, hourCacheWrite: oneHour, fast: false)
        }
        precondition(abs(ClaudeLocalUsageScanner.estimate(cacheRecord(0), catalog: prices)! - 0.00086) < 1e-10)
        precondition(abs(ClaudeLocalUsageScanner.estimate(cacheRecord(40), catalog: prices)! - 0.00092) < 1e-10)
        precondition(abs(ClaudeLocalUsageScanner.estimate(cacheRecord(100), catalog: prices)! - 0.00101) < 1e-10)
        precondition(abs(ClaudeLocalUsageScanner.estimate(cacheRecord(150), catalog: prices)! - 0.00101) < 1e-10)
        let hourOnlyPrices = try JSONDecoder().decode(CodexPricingCatalog.self, from: Data(#"{"anthropic":{"models":{"claude-test":{"id":"claude-test","cost":{"input":2,"output":10,"cache_read":0.2}}}}}"#.utf8))
        precondition(ClaudeLocalUsageScanner.estimate(cacheRecord(100), catalog: hourOnlyPrices) != nil)
        precondition(ClaudeLocalUsageScanner.estimate(cacheRecord(40), catalog: hourOnlyPrices) == nil)
        let counted = ClaudeLocalUsageScanner.aggregate([cacheRecord(100)], catalog: prices, now: now)
        precondition(counted.today?.cost != nil && counted.coverage.isComplete && counted.tokens == 290)
        print("PASS: 5m/1h/mixed cache-write pricing, clamping, and coverage")
        let other = ClaudeLocalUsageScanner.parse(try line("m1", "r2", 20), fallbackKey: "c")!
        precondition(ClaudeLocalUsageScanner.aggregate([a,other], catalog: nil, now: now).requestCount == 2)
        let fallback1 = ClaudeLocalUsageScanner.parse(try line("m1", nil, 20, session: "s1"), fallbackKey: "d")!
        let fallback2 = ClaudeLocalUsageScanner.parse(try line("m1", nil, 20, session: "s2"), fallbackKey: "e")!
        let noPrice = ClaudeLocalUsageScanner.aggregate([fallback1,fallback2], catalog: nil, now: now)
        precondition(noPrice.requestCount == 2 && noPrice.cost == nil && !noPrice.coverage.isComplete)
        var incomplete = try JSONSerialization.jsonObject(with: first) as! [String:Any]
        var msg = incomplete["message"] as! [String:Any]
        msg["stop_reason"] = NSNull(); msg["usage"] = ["input_tokens":100,"output_tokens":0]
        incomplete["message"] = msg
        let incompleteData = try JSONSerialization.data(withJSONObject: incomplete)
        precondition(ClaudeLocalUsageScanner.parse(incompleteData, fallbackKey: "incomplete") == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scanner = ClaudeLocalUsageScanner()
        let empty = try await scanner.scan(roots: [folder], now: now)
        precondition(!empty.hasData && empty.cost == nil && empty.fileCount == 0)
        let file = folder.appendingPathComponent("session.jsonl")
        try (first + Data([10]) + last + Data([10])).write(to: file)
        let scanned = try await scanner.scan(roots: [folder,folder], now: now)
        precondition(scanned.fileCount == 1 && scanned.requestCount == 1 && scanned.tokens == 190)
        let cached = try await scanner.scan(roots: [folder], now: now)
        precondition(cached.tokens == scanned.tokens)
        try first.write(to: file)
        let truncated = try await scanner.scan(roots: [folder], now: now)
        precondition(truncated.tokens == 170)
        try FileManager.default.removeItem(at: file)
        let removed = try await scanner.scan(roots: [folder], now: now)
        precondition(!removed.hasData)
        print("PASS: profile email; cumulative/cross-file deduplication; distinct requests/sessions; cache tokens; pricing coverage; incomplete records; empty, changed and removed history")
    }

    @MainActor
    static func renderFixtures(to directory: URL) async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let widgetID = "claude-quota-validation"
        let prefix = "widget.\(widgetID)."
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("all", forKey: prefix + "dockProvider")
        UserDefaults.standard.set(true, forKey: prefix + "claudeUsageEnabled")
        UserDefaults.standard.set(true, forKey: prefix + "cursorUsageEnabled")
        let now = Date()
        func window(_ id: String, _ used: Double, _ hours: Double) -> CodexQuotaWindow {
            CodexQuotaWindow(id: id, title: id == "five_hour" ? "会话 · 5 小时" : id == "seven_day" ? "全部模型 · 7 天" : id, usedPercent: used, resetAt: now.addingTimeInterval(hours * 3600), durationSeconds: 604800)
        }
        var claude = ClaudeUsageSnapshot(windows: [window("five_hour", 0, 2.5), window("seven_day", 0, 58), window("Fable · 每周", 0, 58)], plan: "max", fetchedAt: now)
        claude.accountEmail = "claude@example.com"
        let localRecords = (0..<30).map { day in
            ClaudeLocalUsageScanner.Record(key: "fixture-\(day)", date: now.addingTimeInterval(-Double(day) * 86400 - 1),
                model: day % 3 == 0 ? "claude-test-opus" : "claude-test-sonnet", input: 100_000 + day * 1000,
                output: 10_000 + day * 100, cacheRead: 50_000, cacheWrite: 5_000, hourCacheWrite: 0, fast: false)
        }
        let fixturePrices = try JSONDecoder().decode(CodexPricingCatalog.self, from: Data(#"{"anthropic":{"models":{"claude-test-opus":{"id":"claude-test-opus","cost":{"input":5,"output":25,"cache_read":0.5,"cache_write":6.25}},"claude-test-sonnet":{"id":"claude-test-sonnet","cost":{"input":3,"output":15,"cache_read":0.3,"cache_write":3.75}}}}}"#.utf8))
        let localUsage = ClaudeLocalUsageScanner.aggregate(localRecords, catalog: fixturePrices, now: now, fileCount: 30)
        let codex = CodexUsageSnapshot(accountEmail: nil, plan: "pro", sessionWindow: window("session", 25, 3), weeklyWindow: window("weekly", 28, 91), extraWindows: [], creditsBalance: nil, resetCreditsAvailable: nil, resetCreditsExpiresAt: nil, fetchedAt: now)
        let cursor = CursorUsageSnapshot(accountEmail: nil, accountName: nil, membershipType: "pro", quotaWindows: [window("Total", 47, 120)], planUsedUSD: 9.4, planLimitUSD: 20, onDemandUsedUSD: 0, onDemandLimitUSD: nil, personalOnDemandUsedUSD: nil, todayTokens: 0, last30DaysTokens: 0, todayAPIEquivalentCostUSD: nil, last30DaysAPIEquivalentCostUSD: nil, last30DaysMeteredCostUSD: nil, costCoverage: .empty, daily: [], topModels: [], fetchedAt: now, sourceLabel: "fixture")
        let cursorWithExtra = CursorUsageSnapshot(accountEmail: "cursor@example.com", accountName: nil, membershipType: "pro",
            quotaWindows: cursor.quotaWindows, planUsedUSD: 9.4, planLimitUSD: 20, onDemandUsedUSD: 12.5,
            onDemandLimitUSD: 50, personalOnDemandUsedUSD: 8, todayTokens: 0, last30DaysTokens: 0,
            todayAPIEquivalentCostUSD: nil, last30DaysAPIEquivalentCostUSD: nil, last30DaysMeteredCostUSD: nil,
            costCoverage: .empty, daily: [], topModels: [], fetchedAt: now, sourceLabel: "fixture")
        for dark in [false, true] {
            let cursorPreview = CursorUsagePanelView(snapshot: cursorWithExtra, error: nil, isRefreshing: false,
                onRefresh: {}, onOpenDashboard: {}, onOpenStatus: {}, onOpenCursor: {})
                .padding(14).frame(width: 360, height: 560, alignment: .top)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95))
                .environment(\.colorScheme, dark ? .dark : .light)
            try await render(cursorPreview, size: CGSize(width: 360, height: 560), dark: dark,
                to: directory.appendingPathComponent(dark ? "cursor-quota-extra-dark.png" : "cursor-quota-extra-light.png"))
        }
        let monitor = CodexUsageMonitor(widgetId: widgetID)
        monitor.setTestingData(usage: codex, status: nil, cursorUsage: cursorWithExtra, claudeUsage: claude, claudeLocalUsage: localUsage)
        for dark in [false, true] {
            let colorScheme: ColorScheme = dark ? .dark : .light
            let gallery = VStack(alignment: .leading, spacing: 20) {
                Text("CODEX / CLAUDE / CURSOR").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Text(CodexLocalization.text("多服务额度 · 布局预览", "Multi-provider quota · layout preview")).font(.system(size: 24, weight: .bold))
                Text(CodexLocalization.text("匿名示例数据 · 横向 1 / 2 / 3 格", "Synthetic data · horizontal 1 / 2 / 3 slots")).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 22) {
                    ForEach([1, 2, 3], id: \.self) { count in
                        CodexUsageMonitorView(size: CGSize(width: 64 * count, height: 64), isVertical: false, widgetId: widgetID, monitor: monitor)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(CodexLocalization.text("竖向 2 / 3 格", "Vertical 2 / 3 slots")).font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 18) {
                            ForEach([2, 3], id: \.self) { count in
                                CodexUsageMonitorView(size: CGSize(width: 64, height: 64 * count), isVertical: true, widgetId: widgetID, monitor: monitor)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    ClaudeLocalUsageView(snapshot: localUsage, error: nil, isRefreshing: false, compact: true)
                        .padding(12).frame(width: 310).background(CodexGlassCard(cornerRadius: 13))
                }
            }.padding(26).frame(width: 600, height: 600, alignment: .topLeading)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95))
                .environment(\.colorScheme, colorScheme)
            try await render(gallery, size: CGSize(width: 600, height: 600), dark: dark, to: directory.appendingPathComponent(dark ? "quota-preview-dark.png" : "quota-preview-light.png"))
            let overview = CodexProviderOverviewView(codexUsage: codex, codexRecentUsage: nil, codexError: nil,
                cursorUsage: cursorWithExtra, cursorError: nil, showsCursor: true,
                claudeUsage: claude, claudeError: nil, showsClaude: true, claudeLocalUsage: localUsage, onSelectClaude: {},
                codexAccent: .blue, cursorAccent: .green, onSelectCodex: {}, onSelectCursor: {})
                .padding(14).frame(width: 360, height: 1040, alignment: .top)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95)).environment(\.colorScheme, colorScheme)
            try await render(overview, size: CGSize(width: 360, height: 1040), dark: dark,
                to: directory.appendingPathComponent(dark ? "overview-refined-dark.png" : "overview-refined-light.png"))
            let small = HStack(spacing: 20) {
                ForEach([40, 48, 64], id: \.self) { dim in
                    CodexUsageMonitorView(size: CGSize(width: dim, height: dim), isVertical: false, widgetId: widgetID, monitor: monitor)
                }
            }.padding(16).frame(width: 240, height: 100).background(dark ? Color(white: 0.09) : Color(white: 0.95))
                .environment(\.colorScheme, colorScheme)
            try await render(small, size: CGSize(width: 240, height: 100), dark: dark,
                to: directory.appendingPathComponent(dark ? "dock-fonts-dark.png" : "dock-fonts-light.png"))

        }
        let detail = ClaudeUsagePanelView(snapshot: claude, error: nil, isRefreshing: false, onRefresh: {}, localUsage: localUsage)
            .padding(14).frame(width: 360, height: 850, alignment: .top).background(Color(white: 0.95)).environment(\.colorScheme, .light)
        try await render(detail, size: CGSize(width: 360, height: 850), dark: false, to: directory.appendingPathComponent("claude-analytics-detail.png"))
        let empty = ClaudeUsagePanelView(snapshot: claude, error: nil, isRefreshing: false, onRefresh: {}, localUsage: ClaudeLocalUsageScanner.aggregate([], catalog: nil, now: now))
            .padding(14).frame(width: 360, height: 520, alignment: .top).background(Color(white: 0.95)).environment(\.colorScheme, .light)
        try await render(empty, size: CGSize(width: 360, height: 520), dark: false, to: directory.appendingPathComponent("claude-analytics-empty.png"))
        for dark in [false, true] {
            let resetPreview = VStack(alignment: .leading, spacing: 16) {
                Text("Claude · " + CodexLocalization.text("额度重置", "Quota resets")).font(.headline)
                ForEach(claude.windows) { quota in
                    CodexProviderQuotaRow(window: quota, accent: .orange)
                }
                Divider()
                Text("Cursor · " + CodexLocalization.text("额度重置", "Quota resets")).font(.headline)
                CodexProviderQuotaRow(window: cursor.primaryWindow!, accent: .green)
                Divider()
                Text(CodexLocalization.text("概览卡片", "Overview card")).font(.headline)
                CodexProviderQuotaRow(window: claude.windows[1], accent: .orange, compact: true)
                Divider()
                CodexProviderQuotaRow(window: CodexQuotaWindow(id: "unknown", title: "No reset date", usedPercent: 20, resetAt: nil, durationSeconds: 0), accent: .secondary)
            }.padding(14).frame(width: 332, height: 530, alignment: .top)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95)).environment(\.colorScheme, dark ? .dark : .light)
            try await render(resetPreview, size: CGSize(width: 332, height: 530), dark: dark,
                to: directory.appendingPathComponent(dark ? "quota-reset-times-dark.png" : "quota-reset-times-light.png"))
        }
        let widePanel = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: "overview")
        let expectedWide = min(CGFloat(1048), max(360, (NSScreen.main?.visibleFrame.width ?? 1080) - 32))
        precondition(abs(widePanel.testingPanelWidth - expectedWide) < 1)
        for page in ["codex", "claude", "cursor", "insights", "settings"] {
            precondition(CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: page).testingPanelWidth == 360)
        }
        for dark in [false, true] {
            let wide = widePanel.environment(\.colorScheme, dark ? .dark : .light)
            try await render(wide, size: CGSize(width: expectedWide, height: 572), dark: dark,
                to: directory.appendingPathComponent(dark ? "wide-overview-dark.png" : "wide-overview-light.png"))
            let narrow = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: "claude")
                .environment(\.colorScheme, dark ? .dark : .light)
            try await render(narrow, size: CGSize(width: 360, height: 572), dark: dark,
                to: directory.appendingPathComponent(dark ? "narrow-claude-dark.png" : "narrow-claude-light.png"))
        }
        for name in ["overview", "codex", "claude", "cursor", "settings"] {
            let panel = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: name)
            try await render(panel.environment(\.colorScheme, .light), size: CGSize(width: panel.testingPanelWidth, height: 572), dark: false,
                to: directory.appendingPathComponent("adaptive-height-" + name + ".png"))
        }
        print("PASS: overview/status expand; work is 640pt; remaining pages stay 360pt")
        var workRecords: [ProviderConversation] = []
        let workTitles = ["修复项目窗口布局与动画", "完善额度统计和模型展示", "检查最近的构建结果", "新增配置导入", "整理项目文档"]
        for index in 0..<5 {
            let projectPath: String? = index == 4 ? nil : "/Users/demo/Projects/" + (index < 3 ? "Dashboard" : "Widget")
            let modifiedAt = Date().addingTimeInterval(-Double(index) * 3600)
            workRecords.append(ProviderConversation(id: UUID().uuidString, title: workTitles[index], projectPath: projectPath,
                modifiedAt: modifiedAt, isArchived: false, contextPercent: 42, linesAdded: 120, linesRemoved: 18))
        }
        let workSnapshot = ProviderWorkSnapshot(conversations:workRecords,scannedCount:5,unavailableSources:0,fetchedAt:Date())
        func statusComponents(_ names: [String], prefix: String) -> [OpenAIStatusComponent] {
            names.enumerated().map { OpenAIStatusComponent(id: prefix + String($0.offset), name: $0.element, indicator: .operational) }
        }
        let claudeStatus = ProviderServiceStatus(indicator:.operational,components:statusComponents([
            "claude.ai", "Claude Console (platform.claude.com)", "Claude API (api.anthropic.com)", "Claude Code", "Claude Cowork", "Claude for Government"],prefix:"claude"),incidents:[],fetchedAt:Date())
        let cursorStatus = ProviderServiceStatus(indicator:.operational,components:statusComponents([
            "Automations", "Review Agents", "CLI", "Cloud Agents", "cursor.com", "IDE", "Origin", "Grok Bot"],prefix:"cursor"),incidents:[],fetchedAt:Date())
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "yyyy-MM-dd"
        let insightDays = (0..<30).map { index -> CursorUsageDay in
            let key = dateFormatter.string(from: Calendar.current.date(byAdding:.day,value:index-29,to:now)!)
            let scale = (index % 5) + 1
            return CursorUsageDay(date:key,inputTokens:10000*scale,outputTokens:2000*scale,cacheWriteTokens:3000*scale,
                cacheReadTokens:50000*scale,requestCount:scale*4,apiEquivalentCostUSD:Double(scale)*1.3,meteredCostUSD:Double(scale)*0.8)
        }
        let cursorInsights = CursorUsageSnapshot(accountEmail:"cursor@example.com",accountName:nil,membershipType:"pro",quotaWindows:cursor.quotaWindows,
            planUsedUSD:9.4,planLimitUSD:20,onDemandUsedUSD:12.5,onDemandLimitUSD:50,personalOnDemandUsedUSD:8,
            todayTokens:insightDays.last!.totalTokens,last30DaysTokens:insightDays.reduce(0) { $0 + $1.totalTokens },
            todayAPIEquivalentCostUSD:6.5,last30DaysAPIEquivalentCostUSD:117,last30DaysMeteredCostUSD:72,
            costCoverage:CodexCostCoverage(pricedTokens:5850000,totalTokens:5850000,pricedRequests:360,totalRequests:360),
            daily:insightDays,topModels:[CursorModelUsage(model:"claude-opus",tokens:4000000,requestCount:220,apiEquivalentCostUSD:80),CursorModelUsage(model:"gpt-codex",tokens:1850000,requestCount:140,apiEquivalentCostUSD:37)],fetchedAt:now,sourceLabel:"fixture")
        let openAIStatus = OpenAIStatusSnapshot(overallIndicator:.operational,description:nil,groups:[
            OpenAIStatusGroup(id:"chatgpt",name:"ChatGPT",components:statusComponents([
                "Conversations", "Login", "ChatGPT Work", "Codex in ChatGPT Desktop", "Compliance API", "Search", "File uploads", "Voice mode", "GPTs", "Image Generation", "Deep Research", "Agent", "ChatGPT Atlas", "Sites", "Connectors/Apps"],prefix:"chat")),
            OpenAIStatusGroup(id:"codex",name:"Codex",components:statusComponents(["Codex Web", "Codex API", "CLI", "VS Code extension"],prefix:"codex"))],fetchedAt:Date())
        monitor.setTestingData(usage:codex,status:openAIStatus,cursorUsage:cursorInsights,claudeUsage:claude,claudeLocalUsage:localUsage,providerStatuses:[.claude:claudeStatus,.cursor:cursorStatus],providerWork:[.claude:workSnapshot,.cursor:workSnapshot])
        for dark in [false,true] {
            let statusPanel = CodexUsageMonitorPanel(widgetId:widgetID,monitor:monitor,testingPage:"status")
            precondition(statusPanel.testingPanelWidth == expectedWide)
            try await render(statusPanel,size:CGSize(width:expectedWide,height:600),dark:dark,to:directory.appendingPathComponent("providers-status-" + (dark ? "dark" : "light") + ".png"))
            let warning = ProviderServiceStatus(indicator:.degraded,components:cursorStatus.components + [OpenAIStatusComponent(id:"late",name:"Late affected component",indicator:.degraded)],incidents:[ProviderServiceStatus.Incident(id:"incident",name:"Investigating service degradation",status:"monitoring")],fetchedAt:Date())
            let warningView = ProviderStatusView(provider:.cursor,status:warning,error:"Refresh temporarily unavailable",refresh:{}).padding(14)
            try await render(warningView,size:CGSize(width:360,height:470),dark:dark,to:directory.appendingPathComponent("status-error-"+(dark ? "dark" : "light")+".png"))
            for provider in ["claude","cursor"] {
                for section in ["official","local"] {
                    UserDefaults.standard.set(provider,forKey:"codexUsage.testing.insightsProvider")
                    UserDefaults.standard.set(section,forKey:"codexUsage.testing.insightsSection")
                    let panel = CodexUsageMonitorPanel(widgetId:widgetID,monitor:monitor,testingPage:"insights")
                    try await render(panel,size:CGSize(width:360,height:800),dark:dark,to:directory.appendingPathComponent(provider+"-insights-"+section+"-"+(dark ? "dark" : "light")+".png"))
                }
            }
            UserDefaults.standard.removeObject(forKey:"codexUsage.testing.insightsProvider")
            UserDefaults.standard.removeObject(forKey:"codexUsage.testing.insightsSection")
            for provider in ["claude","cursor"] {
                for section in ["projects","conversations"] {
                    UserDefaults.standard.set(provider,forKey:"codexUsage.testing.workProvider")
                    UserDefaults.standard.set(section,forKey:"codexUsage.testing.workSection")
                    let panel = CodexUsageMonitorPanel(widgetId:widgetID,monitor:monitor,testingPage:"work")
                    precondition(panel.testingPanelWidth == min(640,max(360,(NSScreen.main?.visibleFrame.width ?? 1080)-32)))
                    try await render(panel,size:CGSize(width:panel.testingPanelWidth,height:700),dark:dark,to:directory.appendingPathComponent(provider+"-"+section+"-"+(dark ? "dark" : "light")+".png"))
                }
            }
        }
        UserDefaults.standard.removeObject(forKey:"codexUsage.testing.workProvider")
        UserDefaults.standard.removeObject(forKey:"codexUsage.testing.workSection")
        UserDefaults.standard.set("CNY", forKey: prefix + "displayCurrency")
        let settings = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: "settings")
        precondition(settings.testingHealthSourceIDs.count == 10)
        precondition(settings.testingHealthSourceIDs.filter { $0 == "claude" }.count == 1)
        for dark in [false, true] {
            let preview = settings.testingProviderSettingsAndHealth.padding(14)
                .frame(width: 360, height: 700, alignment: .top)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95)).environment(\.colorScheme, dark ? .dark : .light)
            try await render(preview, size: CGSize(width: 360, height: 700), dark: dark,
                to: directory.appendingPathComponent(dark ? "claude-settings-health-dark.png" : "claude-settings-health-light.png"))
        }
        UserDefaults.standard.set(false, forKey: prefix + "claudeUsageEnabled")
        let withoutClaude = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: "settings")
        precondition(withoutClaude.testingHealthSourceIDs.count == 8 && !withoutClaude.testingHealthSourceIDs.contains("claude"))
        UserDefaults.standard.set("USD", forKey: prefix + "displayCurrency")
        let withoutFX = CodexUsageMonitorPanel(widgetId: widgetID, monitor: monitor, testingPage: "settings")
        precondition(withoutFX.testingHealthSourceIDs.count == 7 && !withoutFX.testingHealthSourceIDs.contains("fx"))
        print("PASS: health sources share summary/rows; 10 with provider statuses+FX, 8 without Claude, 7 without FX")
        print("PASS: rendered light/dark, horizontal 1/2/3 slots and vertical 2/3 slots")
    }

    @MainActor
    static func testGeometryObserverIsReadOnly() async throws {
        let panel = NSPanel(contentRect: NSRect(x: 200, y: 59, width: 360, height: 500),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Color.clear.frame(width: 360, height: 500))
        panel.contentView = host
        let originalOptions = host.sizingOptions
        let probe = CodexPanelWindowSizing.SizingView()
        probe.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        var reported: CGSize?
        probe.onAvailableSize = { reported = $0 }
        host.addSubview(probe)
        panel.alphaValue = 0; panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let originalFrame = panel.frame
        for target in [CGSize(width: 1048, height: 900), CGSize(width: 360, height: 300), CGSize(width: 1048, height: 5000)] {
            probe.targetSize = target
            probe.scheduleUpdate()
            try await Task.sleep(for: .milliseconds(100))
            precondition(panel.frame == originalFrame, "Plugin must not move or resize a host-owned popup")
            precondition(host.sizingOptions == originalOptions, "Plugin must not override native hosting sizing")
        }
        precondition(reported != nil && reported!.height <= panel.screen!.visibleFrame.maxY - panel.frame.minY)
        print("PASS: screen observer is read-only; native window position, size and hosting policy remain host-owned")
    }

    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try data.write(to: url)
    }
}


private final class InsightsFixtureURLProtocol: URLProtocol {
    static var mode = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let events = request.url!.path.contains("get-filtered-usage-events")
        let code = events && Self.mode == 0 ? 503 : 200
        let body = events ? (Self.mode == 2 ? #"{"totalUsageEventsCount":10,"usageEventsDisplay":[]}"# : #"{"totalUsageEventsCount":0,"usageEventsDisplay":[]}"#) : "{}"
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
