import Foundation

/// Account-level Codex usage and quota information returned by one read-only
/// Codex app-server session.
///
/// The service intentionally requests only aggregate account metadata. It does
/// not read conversation text, credentials, prompts, or tool output.
struct CodexAccountInsightsSnapshot: Codable, Equatable, Sendable {
    let officialUsage: CodexOfficialAccountUsage?
    let quotaDiagnostics: CodexAccountQuotaDiagnostics?
    let fetchedAt: Date
    let issues: [CodexAccountInsightIssue]

    var hasData: Bool {
        officialUsage != nil || quotaDiagnostics != nil
    }
}

struct CodexOfficialAccountUsage: Codable, Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
    let dailyUsageBuckets: [CodexOfficialDailyUsageBucket]
}

struct CodexOfficialDailyUsageBucket: Codable, Equatable, Sendable, Identifiable {
    let startDate: String
    let tokens: Int64

    var id: String { startDate }
}

struct CodexAccountQuotaDiagnostics: Codable, Equatable, Sendable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: CodexAccountRateLimitWindow?
    let secondary: CodexAccountRateLimitWindow?
    let credits: CodexAccountCreditsDiagnostics?
    let individualLimit: CodexAccountIndividualLimit?
    let spendControlReached: Bool?
    let rateLimitReachedType: CodexAccountRateLimitReachedType?
    let resetCredits: CodexAccountResetCreditInventory?
    let additionalLimits: [CodexAccountAdditionalRateLimit]
}

struct CodexAccountRateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Double?
    let windowDurationMinutes: Int?
    let resetsAt: Date?
}

struct CodexAccountCreditsDiagnostics: Codable, Equatable, Sendable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?
}

struct CodexAccountIndividualLimit: Codable, Equatable, Sendable {
    let used: String?
    let limit: String?
    let remainingPercent: Int?
    let resetsAt: Date?
}

enum CodexAccountRateLimitReachedType: Equatable, Sendable {
    case rateLimitReached
    case workspaceOwnerCreditsDepleted
    case workspaceMemberCreditsDepleted
    case workspaceOwnerUsageLimitReached
    case workspaceMemberUsageLimitReached
    case unknown(String)

    var rawValue: String {
        switch self {
        case .rateLimitReached:
            return "rate_limit_reached"
        case .workspaceOwnerCreditsDepleted:
            return "workspace_owner_credits_depleted"
        case .workspaceMemberCreditsDepleted:
            return "workspace_member_credits_depleted"
        case .workspaceOwnerUsageLimitReached:
            return "workspace_owner_usage_limit_reached"
        case .workspaceMemberUsageLimitReached:
            return "workspace_member_usage_limit_reached"
        case let .unknown(value):
            return value
        }
    }
}

extension CodexAccountRateLimitReachedType: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self.decode(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func decode(_ value: String) -> Self {
        switch value {
        case "rate_limit_reached", "rateLimitReached":
            return .rateLimitReached
        case "workspace_owner_credits_depleted", "workspaceOwnerCreditsDepleted":
            return .workspaceOwnerCreditsDepleted
        case "workspace_member_credits_depleted", "workspaceMemberCreditsDepleted":
            return .workspaceMemberCreditsDepleted
        case "workspace_owner_usage_limit_reached", "workspaceOwnerUsageLimitReached":
            return .workspaceOwnerUsageLimitReached
        case "workspace_member_usage_limit_reached", "workspaceMemberUsageLimitReached":
            return .workspaceMemberUsageLimitReached
        default:
            return .unknown(value)
        }
    }
}

struct CodexAccountResetCreditInventory: Codable, Equatable, Sendable {
    let availableCount: Int

    /// `nil` means the server returned only the summary count. An empty array
    /// means details were requested and no detail rows were returned.
    let credits: [CodexAccountResetCredit]?
}

struct CodexAccountResetCredit: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let status: CodexAccountResetCreditStatus?
    let grantedAt: Date?
    let expiresAt: Date?
    let title: String?
    let description: String?
}

enum CodexAccountResetCreditStatus: Equatable, Sendable {
    case available
    case redeeming
    case redeemed
    case unknown(String)

    var rawValue: String {
        switch self {
        case .available: return "available"
        case .redeeming: return "redeeming"
        case .redeemed: return "redeemed"
        case let .unknown(value): return value
        }
    }
}

extension CodexAccountResetCreditStatus: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self.decode(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func decode(_ value: String) -> Self {
        switch value.lowercased() {
        case "available": return .available
        case "redeeming": return .redeeming
        case "redeemed": return .redeemed
        default: return .unknown(value)
        }
    }
}

struct CodexAccountAdditionalRateLimit: Codable, Equatable, Sendable, Identifiable {
    /// Stable dictionary key returned by the app-server.
    let id: String
    let limitId: String?
    let limitName: String?
    let primary: CodexAccountRateLimitWindow?
    let secondary: CodexAccountRateLimitWindow?
}

struct CodexAccountInsightIssue: Codable, Equatable, Sendable {
    enum Component: String, Codable, Equatable, Sendable {
        case officialUsage
        case rateLimits
    }

    enum Reason: String, Codable, Equatable, Sendable {
        case methodUnavailable
        case timedOut
        case requestFailed
        case invalidResponse
    }

    let component: Component
    let reason: Reason

    /// JSON-RPC error code only. Server messages are deliberately not retained.
    let rpcCode: Int?
}

/// Fetches aggregate account insights from the installed Codex CLI.
///
/// Request failures are isolated per component and returned through
/// `CodexAccountInsightsSnapshot.issues`. Launch or initialization failures are
/// the only errors thrown by `fetch()`.
struct CodexAccountInsightsService: Sendable {
    enum ServiceError: LocalizedError, Sendable {
        case cliNotInstalled
        case launchFailed
        case initializationTimedOut
        case initializationFailed

        var errorDescription: String? {
            switch self {
            case .cliNotInstalled:
                return "Codex CLI was not found."
            case .launchFailed:
                return "Codex CLI could not be started."
            case .initializationTimedOut:
                return "Codex app-server initialization timed out."
            case .initializationFailed:
                return "Codex app-server initialization failed."
            }
        }
    }

    func fetch() async throws -> CodexAccountInsightsSnapshot {
        let rpc: CodexAccountInsightsRPCClient
        do {
            rpc = try CodexAccountInsightsRPCClient()
        } catch let error as CodexAccountInsightsRPCError {
            throw Self.serviceError(for: error)
        } catch {
            throw ServiceError.launchFailed
        }
        defer { rpc.shutdown() }

        do {
            try await rpc.initialize()
        } catch let error as CodexAccountInsightsRPCError {
            throw Self.serviceError(for: error)
        } catch {
            throw ServiceError.initializationFailed
        }

        var issues: [CodexAccountInsightIssue] = []
        var quotaDiagnostics: CodexAccountQuotaDiagnostics?
        var officialUsage: CodexOfficialAccountUsage?

        // Requests are intentionally sequential. A single app-server session is
        // reused, while avoiding concurrent consumers racing on its stdout stream.
        do {
            let response: CodexAccountRateLimitsWireResponse = try await rpc.requestDecoded(
                method: "account/rateLimits/read"
            )
            quotaDiagnostics = Self.makeQuotaDiagnostics(from: response)
            if quotaDiagnostics == nil {
                issues.append(
                    CodexAccountInsightIssue(
                        component: .rateLimits,
                        reason: .invalidResponse,
                        rpcCode: nil
                    )
                )
            }
        } catch {
            issues.append(Self.issue(for: error, component: .rateLimits))
        }

        do {
            let response: CodexAccountUsageWireResponse = try await rpc.requestDecoded(
                method: "account/usage/read"
            )
            officialUsage = Self.makeOfficialUsage(from: response)
            if officialUsage == nil {
                issues.append(
                    CodexAccountInsightIssue(
                        component: .officialUsage,
                        reason: .invalidResponse,
                        rpcCode: nil
                    )
                )
            }
        } catch {
            issues.append(Self.issue(for: error, component: .officialUsage))
        }

        return CodexAccountInsightsSnapshot(
            officialUsage: officialUsage,
            quotaDiagnostics: quotaDiagnostics,
            fetchedAt: Date(),
            issues: issues
        )
    }

    private static func makeOfficialUsage(
        from response: CodexAccountUsageWireResponse
    ) -> CodexOfficialAccountUsage? {
        guard response.summary != nil || response.dailyUsageBuckets != nil else {
            return nil
        }

        let buckets = (response.dailyUsageBuckets ?? [])
            .compactMap { bucket -> CodexOfficialDailyUsageBucket? in
                guard let startDate = bucket.startDate, let tokens = bucket.tokens else {
                    return nil
                }
                return CodexOfficialDailyUsageBucket(
                    startDate: startDate,
                    tokens: max(0, tokens)
                )
            }
            .sorted { $0.startDate < $1.startDate }

        return CodexOfficialAccountUsage(
            lifetimeTokens: response.summary?.lifetimeTokens,
            peakDailyTokens: response.summary?.peakDailyTokens,
            longestRunningTurnSeconds: response.summary?.longestRunningTurnSeconds,
            currentStreakDays: response.summary?.currentStreakDays,
            longestStreakDays: response.summary?.longestStreakDays,
            dailyUsageBuckets: buckets
        )
    }

    private static func makeQuotaDiagnostics(
        from response: CodexAccountRateLimitsWireResponse
    ) -> CodexAccountQuotaDiagnostics? {
        let main = response.rateLimits
        let additional = (response.rateLimitsByLimitId ?? [:])
            .filter { key, value in
                guard let main else { return true }
                if let mainID = main.limitId {
                    return key != mainID && value.limitId != mainID
                }
                return true
            }
            .map { key, value in
                CodexAccountAdditionalRateLimit(
                    id: key,
                    limitId: value.limitId,
                    limitName: value.limitName,
                    primary: makeWindow(from: value.primary),
                    secondary: makeWindow(from: value.secondary)
                )
            }
            .sorted {
                let lhs = $0.limitName ?? $0.limitId ?? $0.id
                let rhs = $1.limitName ?? $1.limitId ?? $1.id
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

        let resetCredits = response.rateLimitResetCredits.map { summary in
            CodexAccountResetCreditInventory(
                availableCount: max(0, summary.availableCount ?? summary.credits?.count ?? 0),
                credits: summary.credits.map { credits in
                    credits.compactMap(makeResetCredit(from:))
                }
            )
        }

        guard main != nil || !additional.isEmpty || resetCredits != nil else {
            return nil
        }

        return CodexAccountQuotaDiagnostics(
            limitId: main?.limitId,
            limitName: main?.limitName,
            planType: main?.planType,
            primary: makeWindow(from: main?.primary),
            secondary: makeWindow(from: main?.secondary),
            credits: main?.credits.map {
                CodexAccountCreditsDiagnostics(
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited,
                    balance: $0.balance
                )
            },
            individualLimit: main?.individualLimit.map {
                CodexAccountIndividualLimit(
                    used: $0.used,
                    limit: $0.limit,
                    remainingPercent: $0.remainingPercent,
                    resetsAt: date(fromUnixTimestamp: $0.resetsAt)
                )
            },
            spendControlReached: main?.spendControlReached,
            rateLimitReachedType: main?.rateLimitReachedType.map(
                CodexAccountRateLimitReachedType.decode
            ),
            resetCredits: resetCredits,
            additionalLimits: additional
        )
    }

    private static func makeWindow(
        from wire: CodexAccountRateLimitWindowWire?
    ) -> CodexAccountRateLimitWindow? {
        guard let wire else { return nil }
        return CodexAccountRateLimitWindow(
            usedPercent: wire.usedPercent.map { max(0, min(100, $0)) },
            windowDurationMinutes: wire.windowDurationMinutes,
            resetsAt: date(fromUnixTimestamp: wire.resetsAt)
        )
    }

    private static func makeResetCredit(
        from wire: CodexAccountResetCreditWire
    ) -> CodexAccountResetCredit? {
        guard let id = wire.id, !id.isEmpty else { return nil }
        return CodexAccountResetCredit(
            id: id,
            status: wire.status.map(CodexAccountResetCreditStatus.decode),
            grantedAt: date(fromUnixTimestamp: wire.grantedAt),
            expiresAt: date(fromUnixTimestamp: wire.expiresAt),
            title: wire.title,
            description: wire.description
        )
    }

    private static func date(fromUnixTimestamp timestamp: Int64?) -> Date? {
        guard let timestamp, timestamp > 0 else { return nil }
        let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1_000 : Double(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }

    private static func issue(
        for error: Error,
        component: CodexAccountInsightIssue.Component
    ) -> CodexAccountInsightIssue {
        guard let rpcError = error as? CodexAccountInsightsRPCError else {
            return CodexAccountInsightIssue(
                component: component,
                reason: .invalidResponse,
                rpcCode: nil
            )
        }
        switch rpcError {
        case .methodUnavailable:
            return CodexAccountInsightIssue(
                component: component,
                reason: .methodUnavailable,
                rpcCode: -32601
            )
        case .timeout:
            return CodexAccountInsightIssue(
                component: component,
                reason: .timedOut,
                rpcCode: nil
            )
        case let .requestFailed(code):
            return CodexAccountInsightIssue(
                component: component,
                reason: .requestFailed,
                rpcCode: code
            )
        case .invalidResponse, .streamEnded:
            return CodexAccountInsightIssue(
                component: component,
                reason: .invalidResponse,
                rpcCode: nil
            )
        case .notInstalled, .launchFailed:
            return CodexAccountInsightIssue(
                component: component,
                reason: .requestFailed,
                rpcCode: nil
            )
        }
    }

    private static func serviceError(
        for error: CodexAccountInsightsRPCError
    ) -> ServiceError {
        switch error {
        case .notInstalled:
            return .cliNotInstalled
        case .launchFailed:
            return .launchFailed
        case .timeout:
            return .initializationTimedOut
        case .methodUnavailable, .requestFailed, .invalidResponse, .streamEnded:
            return .initializationFailed
        }
    }
}

// MARK: - Wire models

private struct CodexAccountUsageWireResponse: Decodable {
    let summary: CodexAccountUsageSummaryWire?
    let dailyUsageBuckets: [CodexAccountDailyUsageBucketWire]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        summary = container.decodeFirst(
            CodexAccountUsageSummaryWire.self,
            keys: ["summary"]
        )
        dailyUsageBuckets = container.decodeFirst(
            [CodexAccountDailyUsageBucketWire].self,
            keys: ["dailyUsageBuckets", "daily_usage_buckets"]
        )
    }
}

private struct CodexAccountUsageSummaryWire: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        lifetimeTokens = container.flexibleInt64(keys: ["lifetimeTokens", "lifetime_tokens"])
        peakDailyTokens = container.flexibleInt64(keys: ["peakDailyTokens", "peak_daily_tokens"])
        longestRunningTurnSeconds = container.flexibleInt64(
            keys: ["longestRunningTurnSec", "longest_running_turn_sec"]
        )
        currentStreakDays = container.flexibleInt64(
            keys: ["currentStreakDays", "current_streak_days"]
        )
        longestStreakDays = container.flexibleInt64(
            keys: ["longestStreakDays", "longest_streak_days"]
        )
    }
}

private struct CodexAccountDailyUsageBucketWire: Decodable {
    let startDate: String?
    let tokens: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        startDate = container.flexibleString(keys: ["startDate", "start_date"])
        tokens = container.flexibleInt64(keys: ["tokens"])
    }
}

private struct CodexAccountRateLimitsWireResponse: Decodable {
    let rateLimits: CodexAccountRateLimitSnapshotWire?
    let rateLimitsByLimitId: [String: CodexAccountRateLimitSnapshotWire]?
    let rateLimitResetCredits: CodexAccountResetCreditInventoryWire?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        rateLimits = container.decodeFirst(
            CodexAccountRateLimitSnapshotWire.self,
            keys: ["rateLimits", "rate_limits"]
        )
        rateLimitsByLimitId = container.decodeFirst(
            [String: CodexAccountRateLimitSnapshotWire].self,
            keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"]
        )
        rateLimitResetCredits = container.decodeFirst(
            CodexAccountResetCreditInventoryWire.self,
            keys: ["rateLimitResetCredits", "rate_limit_reset_credits"]
        )
    }
}

private struct CodexAccountRateLimitSnapshotWire: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: CodexAccountRateLimitWindowWire?
    let secondary: CodexAccountRateLimitWindowWire?
    let credits: CodexAccountCreditsWire?
    let individualLimit: CodexAccountIndividualLimitWire?
    let spendControlReached: Bool?
    let planType: String?
    let rateLimitReachedType: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        limitId = container.flexibleString(keys: ["limitId", "limit_id"])
        limitName = container.flexibleString(keys: ["limitName", "limit_name"])
        primary = container.decodeFirst(
            CodexAccountRateLimitWindowWire.self,
            keys: ["primary"]
        )
        secondary = container.decodeFirst(
            CodexAccountRateLimitWindowWire.self,
            keys: ["secondary"]
        )
        credits = container.decodeFirst(CodexAccountCreditsWire.self, keys: ["credits"])
        individualLimit = container.decodeFirst(
            CodexAccountIndividualLimitWire.self,
            keys: ["individualLimit", "individual_limit"]
        )
        spendControlReached = container.flexibleBool(
            keys: ["spendControlReached", "spend_control_reached"]
        )
        planType = container.flexibleString(keys: ["planType", "plan_type"])
        rateLimitReachedType = container.flexibleString(
            keys: ["rateLimitReachedType", "rate_limit_reached_type"]
        )
    }
}

private struct CodexAccountRateLimitWindowWire: Decodable {
    let usedPercent: Double?
    let windowDurationMinutes: Int?
    let resetsAt: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        usedPercent = container.flexibleDouble(keys: ["usedPercent", "used_percent"])
        windowDurationMinutes = container.flexibleInt(
            keys: [
                "windowDurationMins",
                "window_duration_mins",
                "windowMinutes",
                "window_minutes",
            ]
        )
        resetsAt = container.flexibleInt64(keys: ["resetsAt", "resets_at"])
    }
}

private struct CodexAccountCreditsWire: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        hasCredits = container.flexibleBool(keys: ["hasCredits", "has_credits"])
        unlimited = container.flexibleBool(keys: ["unlimited"])
        balance = container.flexibleString(keys: ["balance"])
    }
}

private struct CodexAccountIndividualLimitWire: Decodable {
    let used: String?
    let limit: String?
    let remainingPercent: Int?
    let resetsAt: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        used = container.flexibleString(keys: ["used"])
        limit = container.flexibleString(keys: ["limit"])
        remainingPercent = container.flexibleInt(
            keys: ["remainingPercent", "remaining_percent"]
        )
        resetsAt = container.flexibleInt64(keys: ["resetsAt", "resets_at"])
    }
}

private struct CodexAccountResetCreditInventoryWire: Decodable {
    let availableCount: Int?
    let credits: [CodexAccountResetCreditWire]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        availableCount = container.flexibleInt(keys: ["availableCount", "available_count"])
        credits = container.decodeFirst(
            [CodexAccountResetCreditWire].self,
            keys: ["credits"]
        )
    }
}

private struct CodexAccountResetCreditWire: Decodable {
    let id: String?
    let status: String?
    let grantedAt: Int64?
    let expiresAt: Int64?
    let title: String?
    let description: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexAccountInsightCodingKey.self)
        id = container.flexibleString(keys: ["id"])
        status = container.flexibleString(keys: ["status"])
        grantedAt = container.flexibleInt64(keys: ["grantedAt", "granted_at"])
        expiresAt = container.flexibleInt64(keys: ["expiresAt", "expires_at"])
        title = container.flexibleString(keys: ["title"])
        description = container.flexibleString(keys: ["description"])
    }
}

private struct CodexAccountInsightCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == CodexAccountInsightCodingKey {
    func decodeFirst<T: Decodable>(_ type: T.Type, keys: [String]) -> T? {
        for name in keys {
            guard let key = CodexAccountInsightCodingKey(stringValue: name) else { continue }
            if let value = try? decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }

    func flexibleString(keys: [String]) -> String? {
        if let value = decodeFirst(String.self, keys: keys) { return value }
        if let value = flexibleInt64(keys: keys) { return String(value) }
        if let value = flexibleDouble(keys: keys), value.isFinite { return String(value) }
        return nil
    }

    func flexibleInt(keys: [String]) -> Int? {
        guard let value = flexibleInt64(keys: keys),
              value <= Int64(Int.max),
              value >= Int64(Int.min)
        else { return nil }
        return Int(value)
    }

    func flexibleInt64(keys: [String]) -> Int64? {
        if let value = decodeFirst(Int64.self, keys: keys) { return value }
        if let value = decodeFirst(Int.self, keys: keys) { return Int64(value) }
        if let value = decodeFirst(Double.self, keys: keys), value.isFinite {
            return Int64(value)
        }
        if let value = decodeFirst(String.self, keys: keys) {
            if let integer = Int64(value) { return integer }
            if let double = Double(value), double.isFinite { return Int64(double) }
        }
        return nil
    }

    func flexibleDouble(keys: [String]) -> Double? {
        if let value = decodeFirst(Double.self, keys: keys) { return value }
        if let value = decodeFirst(Int64.self, keys: keys) { return Double(value) }
        if let value = decodeFirst(String.self, keys: keys) { return Double(value) }
        return nil
    }

    func flexibleBool(keys: [String]) -> Bool? {
        if let value = decodeFirst(Bool.self, keys: keys) { return value }
        if let value = decodeFirst(Int.self, keys: keys) { return value != 0 }
        if let value = decodeFirst(String.self, keys: keys) {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}

// MARK: - Read-only app-server transport

private enum CodexAccountInsightsRPCError: Error, Sendable {
    case notInstalled
    case launchFailed
    case timeout
    case methodUnavailable
    case requestFailed(code: Int?)
    case invalidResponse
    case streamEnded
}

private final class CodexAccountInsightsRPCClient: @unchecked Sendable {
    private struct SendableMessage: @unchecked Sendable {
        let value: [String: Any]
    }

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lines: AsyncStream<Data>
    private let lineContinuation: AsyncStream<Data>.Continuation
    private var nextID = 1

    init() throws {
        var continuation: AsyncStream<Data>.Continuation!
        lines = AsyncStream<Data> { continuation = $0 }
        lineContinuation = continuation

        guard let executable = Self.resolveExecutable() else {
            throw CodexAccountInsightsRPCError.notInstalled
        }

        var environment = ProcessInfo.processInfo.environment
        let supportPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (supportPaths + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CodexAccountInsightsRPCError.launchFailed
        }

        let lineBuffer = CodexAccountInsightsLineBuffer()
        let streamContinuation = lineContinuation
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                streamContinuation.finish()
                return
            }
            guard let drained = lineBuffer.appendAndDrain(data) else {
                handle.readabilityHandler = nil
                process?.terminate()
                streamContinuation.finish()
                return
            }
            drained.forEach { streamContinuation.yield($0) }
        }

        // Drain stderr to prevent a full pipe from blocking Codex, but never
        // retain or emit its contents.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "dockdoor-codex-account-insights",
                    "version": "1.0",
                ],
            ],
            timeout: 8
        )
        try sendPayload(["method": "initialized", "params": [:]])
    }

    func requestDecoded<T: Decodable>(method: String) async throws -> T {
        let message = try await request(method: method, timeout: 5)
        guard let result = message["result"],
              JSONSerialization.isValidJSONObject(result)
        else {
            throw CodexAccountInsightsRPCError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CodexAccountInsightsRPCError.invalidResponse
        }
    }

    func shutdown() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        lineContinuation.finish()
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func request(
        method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try sendPayload(["id": id, "method": method, "params": params])

        let message = try await withThrowingTaskGroup(of: SendableMessage.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw CodexAccountInsightsRPCError.streamEnded
                }
                while true {
                    let value = try await self.readNextMessage()
                    guard value["id"] != nil else { continue }
                    guard self.integerID(value["id"]) == id else { continue }
                    if let error = value["error"] as? [String: Any] {
                        let code = self.integerID(error["code"])
                        if code == -32601 {
                            throw CodexAccountInsightsRPCError.methodUnavailable
                        }
                        throw CodexAccountInsightsRPCError.requestFailed(code: code)
                    }
                    return SendableMessage(value: value)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CodexAccountInsightsRPCError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CodexAccountInsightsRPCError.timeout
            }
            return first
        }
        return message.value
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CodexAccountInsightsRPCError.invalidResponse
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            try stdinPipe.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
        } catch {
            throw CodexAccountInsightsRPCError.requestFailed(code: nil)
        }
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await line in lines {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else {
                continue
            }
            return json
        }
        throw CodexAccountInsightsRPCError.streamEnded
    }

    private func integerID(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    private static func resolveExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["CODEX_CLI_PATH", "CODEX_BIN"] {
            if let path = environment[key],
               FileManager.default.isExecutableFile(atPath: path)
            {
                return path
            }
        }

        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".npm-global/bin/codex").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private final class CodexAccountInsightsLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let maximumBytes = 4 * 1_048_576

    func appendAndDrain(_ data: Data) -> [Data]? {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        guard buffer.count <= maximumBytes else { return nil }

        var output: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D {
                line.removeLast()
            }
            output.append(line)
        }
        return output
    }
}
