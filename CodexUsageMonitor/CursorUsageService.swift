import Foundation
import SQLite3

// Cursor provider behavior is adapted from steipete/CodexBar (MIT), reduced to
// the read-only Cursor.app auth path needed by this DockDoor widget.

struct CursorUsageDay: Codable, Equatable, Identifiable, Sendable {
    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let requestCount: Int
    let apiEquivalentCostUSD: Double?
    let meteredCostUSD: Double?

    var id: String { date }
    var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }
}

struct CursorModelUsage: Codable, Equatable, Identifiable, Sendable {
    let model: String
    let tokens: Int
    let requestCount: Int
    let apiEquivalentCostUSD: Double?

    var id: String { model }
}

struct CursorUsageSnapshot: Codable, Equatable, Sendable {
    let accountEmail: String?
    let accountName: String?
    let membershipType: String?
    let quotaWindows: [CodexQuotaWindow]
    let planUsedUSD: Double
    let planLimitUSD: Double
    let onDemandUsedUSD: Double
    let onDemandLimitUSD: Double?
    let personalOnDemandUsedUSD: Double?
    let todayTokens: Int
    let last30DaysTokens: Int
    let todayAPIEquivalentCostUSD: Double?
    let last30DaysAPIEquivalentCostUSD: Double?
    let last30DaysMeteredCostUSD: Double?
    let costCoverage: CodexCostCoverage
    let daily: [CursorUsageDay]
    let topModels: [CursorModelUsage]
    let fetchedAt: Date
    let sourceLabel: String

    var displayPlan: String {
        guard let membershipType, !membershipType.isEmpty else { return "Cursor" }
        return "Cursor " + membershipType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var primaryWindow: CodexQuotaWindow? {
        quotaWindows.first
    }
}

struct CursorUsageService: Sendable {
    private let authStore: CursorAppAuthStore
    private let session: URLSession
    private let baseURL = URL(string: "https://cursor.com")!

    init(
        authStore: CursorAppAuthStore = CursorAppAuthStore(),
        session: URLSession = .shared
    ) {
        self.authStore = authStore
        self.session = session
    }

    func fetch(now: Date = Date()) async throws -> CursorUsageSnapshot {
        guard let appSession = try authStore.loadSession() else {
            throw CursorUsageError.notLoggedIn
        }
        guard appSession.isUsable(now: now) else {
            throw CursorUsageError.expiredSession
        }

        let cookieHeader = try appSession.cookieHeader()
        let summary: CursorUsageSummaryResponse = try await request(
            path: "/api/usage-summary",
            cookieHeader: cookieHeader
        )
        let identity = try? await fetchIdentity(cookieHeader: cookieHeader)
        let sand = try? await fetchSandUsage(cookieHeader: cookieHeader)
        let requestUsage = try? await fetchLegacyRequestUsage(
            userID: identity?.sub ?? appSession.userID,
            cookieHeader: cookieHeader
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let events = (try? await fetchUsageEvents(
            cookieHeader: cookieHeader,
            since: startDate,
            until: now
        )) ?? []
        let eventSummary = Self.aggregateEvents(events, calendar: calendar, today: today)

        return Self.makeSnapshot(
            summary: summary,
            identity: identity,
            identityFallback: appSession.identity,
            sand: sand,
            requestUsage: requestUsage,
            eventSummary: eventSummary,
            now: now
        )
    }

    private func fetchIdentity(cookieHeader: String) async throws -> CursorUserInfoResponse {
        try await request(path: "/api/auth/me", cookieHeader: cookieHeader)
    }

    private func fetchSandUsage(cookieHeader: String) async throws -> CursorSandUsageResponse {
        try await request(
            path: "/api/dashboard/get-sand-usage-status",
            method: "POST",
            cookieHeader: cookieHeader,
            body: Data("{}".utf8)
        )
    }

    private func fetchLegacyRequestUsage(
        userID: String,
        cookieHeader: String
    ) async throws -> CursorLegacyUsageResponse {
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID
        return try await request(
            path: "/api/usage?user=\(encoded)",
            cookieHeader: cookieHeader
        )
    }

    private func fetchUsageEvents(
        cookieHeader: String,
        since: Date,
        until: Date
    ) async throws -> [CursorUsageEventResponse] {
        let pageSize = 1_000
        let maxPages = 50
        var pages: [[CursorUsageEventResponse]] = []
        var expectedTotal: Int?

        for page in 1...maxPages {
            let body = CursorUsageEventsRequest(
                page: page,
                pageSize: pageSize,
                startDate: String(Int64((since.timeIntervalSince1970 * 1_000).rounded())),
                endDate: String(Int64((until.timeIntervalSince1970 * 1_000).rounded()))
            )
            let data = try JSONEncoder().encode(body)
            let response: CursorUsageEventsPageResponse = try await request(
                path: "/api/dashboard/get-filtered-usage-events",
                method: "POST",
                cookieHeader: cookieHeader,
                body: data
            )
            if let total = response.totalUsageEventsCount {
                expectedTotal = total
            }
            if response.usageEventsDisplay.isEmpty { break }
            pages.append(response.usageEventsDisplay)
            let received = pages.reduce(0) { $0 + $1.count }
            if response.usageEventsDisplay.count < pageSize || received >= (expectedTotal ?? Int.max) {
                break
            }
        }

        let events = pages.flatMap(\.self)
        guard let expectedTotal, events.count > expectedTotal else { return events }
        return Array(events.prefix(expectedTotal))
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        cookieHeader: String,
        body: Data? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw CursorUsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "CodexUsageDockDoorWidget/\(CodexReleaseUpdateService.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorUsageError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorUsageError.notLoggedIn
        }
        guard http.statusCode == 200 else {
            throw CursorUsageError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CursorUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func makeSnapshot(
        summary: CursorUsageSummaryResponse,
        identity: CursorUserInfoResponse?,
        identityFallback: CursorSessionIdentity?,
        sand: CursorSandUsageResponse?,
        requestUsage: CursorLegacyUsageResponse?,
        eventSummary: CursorEventAggregation,
        now: Date
    ) -> CursorUsageSnapshot {
        let cycleStart = parseISO8601(summary.billingCycleStart)
        let cycleEnd = parseISO8601(summary.billingCycleEnd)
        let duration = max(0, Int(cycleEnd?.timeIntervalSince(cycleStart ?? now) ?? 0))
        let plan = summary.individualUsage?.plan
        let overall = summary.individualUsage?.overall
        let pooled = summary.teamUsage?.pooled

        let autoPercent = clampPercent(plan?.autoPercentUsed)
        let apiPercent = clampPercent(plan?.apiPercentUsed)
        let planUsed = Double(plan?.used ?? 0)
        let planLimit = Double(plan?.limit ?? 0)
        let overallUsed = overall?.used.map(Double.init)
        let overallLimit = overall?.limit.map(Double.init)
        let pooledUsed = pooled?.used.map(Double.init)
        let pooledLimit = pooled?.limit.map(Double.init)

        let requestsUsed = requestUsage?.gpt4?.numRequestsTotal
            ?? requestUsage?.gpt4?.numRequests
        let requestsLimit = requestUsage?.gpt4?.maxRequestUsage
        let totalPercent: Double
        if let requestsUsed, let requestsLimit, requestsLimit > 0 {
            totalPercent = clampPercent(Double(requestsUsed) / Double(requestsLimit) * 100) ?? 0
        } else if let value = plan?.totalPercentUsed {
            totalPercent = clampPercent(value) ?? 0
        } else if let autoPercent, let apiPercent {
            totalPercent = (autoPercent + apiPercent) / 2
        } else if let autoPercent {
            totalPercent = autoPercent
        } else if let apiPercent {
            totalPercent = apiPercent
        } else if planLimit > 0 {
            totalPercent = min(100, max(0, planUsed / planLimit * 100))
        } else if let overallUsed, let overallLimit, overallLimit > 0 {
            totalPercent = min(100, max(0, overallUsed / overallLimit * 100))
        } else if let pooledUsed, let pooledLimit, pooledLimit > 0 {
            totalPercent = min(100, max(0, pooledUsed / pooledLimit * 100))
        } else {
            totalPercent = 0
        }

        var windows = [CodexQuotaWindow(
            id: "cursor-total",
            title: CodexLocalization.text("总计", "Total"),
            usedPercent: totalPercent,
            resetAt: cycleEnd,
            durationSeconds: duration
        )]
        if requestsLimit == nil, let autoPercent {
            windows.append(CodexQuotaWindow(
                id: "cursor-included",
                title: "Cursor",
                usedPercent: autoPercent,
                resetAt: cycleEnd,
                durationSeconds: duration
            ))
        }
        if requestsLimit == nil, let apiPercent {
            windows.append(CodexQuotaWindow(
                id: "cursor-third-party",
                title: "Third Party",
                usedPercent: apiPercent,
                resetAt: cycleEnd,
                durationSeconds: duration
            ))
        }
        if requestsLimit == nil,
           sand?.hasNonZeroIncludedLimit == true,
           let usagePercent = clampPercent(sand?.usagePercent)
        {
            let sandStart = parseISO8601(sand?.currentPeriodStart)
            let sandEnd = parseISO8601(sand?.nextResetTimestampUtc)
            windows.append(CodexQuotaWindow(
                id: "cursor-grok-bot",
                title: "Grok Bot",
                usedPercent: usagePercent,
                resetAt: sandEnd,
                durationSeconds: max(0, Int(sandEnd?.timeIntervalSince(sandStart ?? now) ?? 0))
            ))
        }

        let resolvedPlanUsed: Double
        let resolvedPlanLimit: Double
        if planLimit > 0 || planUsed > 0 {
            resolvedPlanUsed = planUsed / 100
            resolvedPlanLimit = planLimit / 100
        } else if let overallUsed, let overallLimit {
            resolvedPlanUsed = overallUsed / 100
            resolvedPlanLimit = overallLimit / 100
        } else if let pooledUsed, let pooledLimit {
            resolvedPlanUsed = pooledUsed / 100
            resolvedPlanLimit = pooledLimit / 100
        } else {
            resolvedPlanUsed = 0
            resolvedPlanLimit = 0
        }

        let personalOnDemandUsed = Double(summary.individualUsage?.onDemand?.used ?? 0) / 100
        let personalOnDemandLimit = summary.individualUsage?.onDemand?.limit.map { Double($0) / 100 }
        let teamOnDemandUsed = summary.teamUsage?.onDemand?.used.map { Double($0) / 100 }
        let teamOnDemandLimit = summary.teamUsage?.onDemand?.limit.map { Double($0) / 100 }
        let onDemandUsed: Double
        let onDemandLimit: Double?
        let personalRider: Double?
        if (personalOnDemandLimit ?? 0) > 0 {
            onDemandUsed = personalOnDemandUsed
            onDemandLimit = personalOnDemandLimit
            personalRider = nil
        } else if (teamOnDemandLimit ?? 0) > 0 {
            onDemandUsed = teamOnDemandUsed ?? 0
            onDemandLimit = teamOnDemandLimit
            personalRider = personalOnDemandUsed > 0 ? personalOnDemandUsed : nil
        } else {
            onDemandUsed = personalOnDemandUsed
            onDemandLimit = personalOnDemandLimit
            personalRider = nil
        }

        return CursorUsageSnapshot(
            accountEmail: identity?.email ?? identityFallback?.email,
            accountName: identity?.name,
            membershipType: summary.membershipType,
            quotaWindows: windows,
            planUsedUSD: resolvedPlanUsed,
            planLimitUSD: resolvedPlanLimit,
            onDemandUsedUSD: onDemandUsed,
            onDemandLimitUSD: onDemandLimit,
            personalOnDemandUsedUSD: personalRider,
            todayTokens: eventSummary.todayTokens,
            last30DaysTokens: eventSummary.totalTokens,
            todayAPIEquivalentCostUSD: eventSummary.todayAPIEquivalentCostUSD,
            last30DaysAPIEquivalentCostUSD: eventSummary.apiEquivalentCostUSD,
            last30DaysMeteredCostUSD: eventSummary.meteredCostUSD,
            costCoverage: eventSummary.costCoverage,
            daily: eventSummary.daily,
            topModels: eventSummary.topModels,
            fetchedAt: now,
            sourceLabel: "Cursor.app local auth"
        )
    }

    private static func aggregateEvents(
        _ events: [CursorUsageEventResponse],
        calendar: Calendar,
        today: Date
    ) -> CursorEventAggregation {
        var days: [String: CursorDayAccumulator] = [:]
        var models: [String: CursorModelAccumulator] = [:]
        var pricedTokens = 0
        var totalTokens = 0
        var pricedRequests = 0
        var totalRequests = 0
        var meteredTotal = 0.0
        var meteredComplete = !events.isEmpty

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: today)

        for event in events {
            guard let timestamp = event.timestampMS, timestamp > 0,
                  let usage = event.tokenUsage,
                  usage.totalTokens > 0
            else { continue }
            let date = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
            let key = formatter.string(from: date)
            let modelName = event.model?.isEmpty == false ? event.model! : "unknown"
            var day = days[key] ?? CursorDayAccumulator()
            var model = models[modelName] ?? CursorModelAccumulator()

            day.input += usage.inputTokens
            day.output += usage.outputTokens
            day.cacheWrite += usage.cacheWriteTokens
            day.cacheRead += usage.cacheReadTokens
            day.requests += 1
            model.tokens += usage.totalTokens
            model.requests += 1
            totalTokens += usage.totalTokens
            totalRequests += 1

            if let cents = usage.totalCents, cents.isFinite, cents >= 0 {
                day.apiCost += cents / 100
                day.pricedTokens += usage.totalTokens
                day.pricedRequests += 1
                model.apiCost += cents / 100
                model.hasKnownCost = true
                pricedTokens += usage.totalTokens
                pricedRequests += 1
            }
            if let cents = event.chargedCents, cents.isFinite, cents >= 0 {
                day.meteredCost += cents / 100
            } else {
                day.meteredComplete = false
                meteredComplete = false
            }
            if day.requests == 1 { day.meteredComplete = event.chargedCents != nil }
            days[key] = day
            models[modelName] = model
        }

        let daily = days.keys.sorted().map { key in
            let day = days[key]!
            if day.meteredComplete { meteredTotal += day.meteredCost }
            return CursorUsageDay(
                date: key,
                inputTokens: day.input,
                outputTokens: day.output,
                cacheWriteTokens: day.cacheWrite,
                cacheReadTokens: day.cacheRead,
                requestCount: day.requests,
                apiEquivalentCostUSD: day.pricedRequests > 0 ? day.apiCost : nil,
                meteredCostUSD: day.meteredComplete ? day.meteredCost : nil
            )
        }
        let todayDay = daily.first(where: { $0.date == todayKey })
        let todayAPICost: Double?
        if let todayDay {
            todayAPICost = todayDay.apiEquivalentCostUSD
        } else {
            // A successful priced history fetch with no row for today means
            // today is genuinely zero, not that pricing data is unavailable.
            todayAPICost = pricedRequests > 0 ? 0 : nil
        }
        let apiTotal = daily.compactMap(\.apiEquivalentCostUSD).reduce(0, +)
        var topModels: [CursorModelUsage] = []
        for (name, value) in models {
            topModels.append(CursorModelUsage(
                model: name,
                tokens: value.tokens,
                requestCount: value.requests,
                apiEquivalentCostUSD: value.hasKnownCost ? value.apiCost : nil
            ))
        }
        topModels.sort { lhs, rhs in
            lhs.tokens == rhs.tokens ? lhs.model < rhs.model : lhs.tokens > rhs.tokens
        }

        return CursorEventAggregation(
            todayTokens: todayDay?.totalTokens ?? 0,
            totalTokens: totalTokens,
            todayAPIEquivalentCostUSD: todayAPICost,
            apiEquivalentCostUSD: pricedRequests > 0 ? apiTotal : nil,
            meteredCostUSD: totalRequests > 0 && meteredComplete ? meteredTotal : nil,
            costCoverage: CodexCostCoverage(
                pricedTokens: pricedTokens,
                totalTokens: totalTokens,
                pricedRequests: pricedRequests,
                totalRequests: totalRequests
            ),
            daily: daily,
            topModels: Array(topModels.prefix(8))
        )
    }

    private static func clampPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, value))
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct CursorAppAuthStore: Sendable {
    let databasePath: String

    init(databasePath: String? = nil) {
        self.databasePath = databasePath
            ?? NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    fileprivate func loadSession() throws -> CursorAppSession? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
        guard let token = try value(for: "cursorAuth/accessToken"), !token.isEmpty else { return nil }
        return try CursorAppSession(accessToken: token)
    }

    private func value(for key: String) throws -> String? {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(database)
            throw CursorUsageError.localDatabase(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw CursorUsageError.localDatabase("query preparation failed")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, cursorSQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }
}

fileprivate struct CursorAppSession: Sendable {
    let accessToken: String
    let userID: String
    let expiresAt: Date
    let identity: CursorSessionIdentity

    init(accessToken: String) throws {
        let payload = try CursorSessionIdentity.payload(jwt: accessToken)
        guard let subject = payload["sub"] as? String,
              let userID = subject.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init),
              !userID.isEmpty,
              let expiration = payload["exp"] as? NSNumber
        else {
            throw CursorUsageError.invalidLocalSession
        }
        self.accessToken = accessToken
        self.userID = userID
        self.expiresAt = Date(timeIntervalSince1970: expiration.doubleValue)
        self.identity = CursorSessionIdentity(
            subject: subject,
            email: payload["email"] as? String
        )
    }

    func isUsable(now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > 60
    }

    func cookieHeader() throws -> String {
        let encodedUser = userID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userID
        return "WorkosCursorSessionToken=\(encodedUser)%3A%3A\(accessToken)"
    }
}

fileprivate struct CursorSessionIdentity: Sendable {
    let subject: String?
    let email: String?

    static func payload(jwt: String) throws -> [String: Any] {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw CursorUsageError.invalidLocalSession }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CursorUsageError.invalidLocalSession }
        return object
    }
}

private struct CursorUsageSummaryResponse: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let individualUsage: CursorIndividualUsageResponse?
    let teamUsage: CursorTeamUsageResponse?
}

private struct CursorIndividualUsageResponse: Decodable {
    let plan: CursorPlanUsageResponse?
    let onDemand: CursorMoneyUsageResponse?
    let overall: CursorMoneyUsageResponse?
}

private struct CursorTeamUsageResponse: Decodable {
    let onDemand: CursorMoneyUsageResponse?
    let pooled: CursorMoneyUsageResponse?
}

private struct CursorPlanUsageResponse: Decodable {
    let used: Int?
    let limit: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

private struct CursorMoneyUsageResponse: Decodable {
    let used: Int?
    let limit: Int?
}

private struct CursorUserInfoResponse: Decodable {
    let email: String?
    let name: String?
    let sub: String?
}

private struct CursorSandUsageResponse: Decodable {
    let currentPeriodStart: String?
    let nextResetTimestampUtc: String?
    let usagePercent: Double?
    let hasNonZeroIncludedLimit: Bool?
}

private struct CursorLegacyUsageResponse: Decodable {
    let gpt4: CursorLegacyModelUsage?

    enum CodingKeys: String, CodingKey {
        case gpt4 = "gpt-4"
    }
}

private struct CursorLegacyModelUsage: Decodable {
    let numRequests: Int?
    let numRequestsTotal: Int?
    let maxRequestUsage: Int?
}

private struct CursorUsageEventsRequest: Encodable {
    let page: Int
    let pageSize: Int
    let startDate: String
    let endDate: String
}

private struct CursorUsageEventsPageResponse: Decodable {
    let totalUsageEventsCount: Int?
    let usageEventsDisplay: [CursorUsageEventResponse]
}

private struct CursorUsageEventResponse: Decodable {
    let timestampMS: Int64?
    let model: String?
    let tokenUsage: CursorEventTokenUsageResponse?
    let chargedCents: Double?

    enum CodingKeys: String, CodingKey {
        case timestampMS = "timestamp"
        case model
        case tokenUsage
        case chargedCents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampMS = CursorFlexibleNumber.int64(container, .timestampMS)
        model = try? container.decode(String.self, forKey: .model)
        tokenUsage = try? container.decode(CursorEventTokenUsageResponse.self, forKey: .tokenUsage)
        chargedCents = CursorFlexibleNumber.double(container, .chargedCents)
    }
}

private struct CursorEventTokenUsageResponse: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let totalCents: Double?

    enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens, totalCents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = CursorFlexibleNumber.int(container, .inputTokens)
        outputTokens = CursorFlexibleNumber.int(container, .outputTokens)
        cacheWriteTokens = CursorFlexibleNumber.int(container, .cacheWriteTokens)
        cacheReadTokens = CursorFlexibleNumber.int(container, .cacheReadTokens)
        totalCents = CursorFlexibleNumber.double(container, .totalCents)
    }

    var totalTokens: Int {
        var total = 0
        for value in [inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens] {
            guard value >= 0 else { return 0 }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return 0 }
            total = sum
        }
        return total
    }
}

private enum CursorFlexibleNumber {
    static func int<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(exactly: value) ?? 0 }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    static func int64<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int64(value) }
        return nil
    }

    static func double<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
        if let value = try? container.decode(String.self, forKey: key),
           let number = Double(value), number.isFinite { return number }
        return nil
    }
}

private struct CursorDayAccumulator {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var requests = 0
    var apiCost = 0.0
    var meteredCost = 0.0
    var pricedTokens = 0
    var pricedRequests = 0
    var meteredComplete = true
}

private struct CursorModelAccumulator {
    var tokens = 0
    var requests = 0
    var apiCost = 0.0
    var hasKnownCost = false
}

private struct CursorEventAggregation {
    let todayTokens: Int
    let totalTokens: Int
    let todayAPIEquivalentCostUSD: Double?
    let apiEquivalentCostUSD: Double?
    let meteredCostUSD: Double?
    let costCoverage: CodexCostCoverage
    let daily: [CursorUsageDay]
    let topModels: [CursorModelUsage]
}

enum CursorUsageError: LocalizedError {
    case notLoggedIn
    case expiredSession
    case invalidLocalSession
    case localDatabase(String)
    case invalidResponse
    case httpStatus(Int)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return CodexLocalization.text(
                "未找到可用的 Cursor 登录，请先登录 Cursor.app",
                "No usable Cursor login was found. Sign in to Cursor.app first."
            )
        case .expiredSession:
            return CodexLocalization.text(
                "Cursor.app 登录已过期，请打开 Cursor 重新登录",
                "The Cursor.app session has expired. Open Cursor and sign in again."
            )
        case .invalidLocalSession:
            return CodexLocalization.text("Cursor 本地登录数据无效", "Cursor local auth data is invalid.")
        case let .localDatabase(message):
            return CodexLocalization.text(
                "读取 Cursor 本地数据库失败：\(message)",
                "Unable to read the Cursor local database: \(message)"
            )
        case .invalidResponse:
            return CodexLocalization.text("Cursor 返回了无效响应", "Cursor returned an invalid response.")
        case let .httpStatus(status):
            return CodexLocalization.text(
                "Cursor 请求失败（HTTP \(status)）",
                "Cursor request failed (HTTP \(status))."
            )
        case let .parseFailed(message):
            return CodexLocalization.text(
                "无法解析 Cursor 数据：\(message)",
                "Unable to parse Cursor data: \(message)"
            )
        }
    }
}

private let cursorSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
