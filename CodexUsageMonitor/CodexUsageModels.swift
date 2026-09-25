import Foundation
import SwiftUI

enum CodexTypography {
    /// Numeric face shared by Token, cost, count, percentage, and duration values.
    /// Keeping this in one place prevents Insights cards from drifting away from
    /// the Recent Token Usage card's typography.
    static func tokenNumber(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum CodexLocalization {
    static var isChinese: Bool {
        let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        return identifier.lowercased().hasPrefix("zh")
    }

    static var locale: Locale {
        Locale(identifier: isChinese ? "zh_CN" : "en_US")
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}

enum CodexQuotaUsageSource: String, CaseIterable, Identifiable {
    case automatic
    case oauth
    case cli

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return CodexLocalization.text("自动", "Automatic")
        case .oauth: return "OAuth API"
        case .cli: return "CLI (RPC)"
        }
    }

    var sourceLabel: String {
        switch self {
        case .automatic: return "auto"
        case .oauth: return "oauth"
        case .cli: return "cli"
        }
    }

    static func resolve(title: String) -> CodexQuotaUsageSource {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .automatic
    }

    private var localizedTitles: [String] {
        switch self {
        case .automatic: return ["自动", "Automatic"]
        case .oauth: return ["OAuth API"]
        case .cli: return ["CLI (RPC)"]
        }
    }
}

struct CodexQuotaFetchResult {
    let snapshot: CodexUsageSnapshot
    let resolvedSource: CodexQuotaUsageSource
}

enum CodexPalette {
    static let teal = Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
    static let cyan = Color(red: 82 / 255, green: 197 / 255, blue: 211 / 255)
    static let indigo = Color(red: 115 / 255, green: 107 / 255, blue: 212 / 255)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let yellow = Color(red: 0.96, green: 0.77, blue: 0.13)
    static let red = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let softCritical = Color(red: 0.93, green: 0.31, blue: 0.38)

    static func green(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.32, green: 0.66, blue: 0.41) : green
    }

    static func yellow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.64, blue: 0.27) : yellow
    }

    static func red(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.76, green: 0.40, blue: 0.36) : red
    }

    static func softCritical(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.76, green: 0.43, blue: 0.49) : softCritical
    }

    static func orange(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.50, blue: 0.28) : .orange
    }

    static var quotaGradient: LinearGradient {
        LinearGradient(colors: [teal, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum CodexColorTheme: String, CaseIterable, Identifiable {
    case systemAccent
    case codex
    case ocean
    case purple
    case blueMagenta
    case mint
    case sunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemAccent: return CodexLocalization.text("系统强调色", "System Accent")
        case .codex: return CodexLocalization.text("Codex 青", "Codex Teal")
        case .ocean: return "Ocean"
        case .purple: return CodexLocalization.text("紫罗兰", "Violet")
        case .blueMagenta: return CodexLocalization.text("蓝洋红", "Blue Magenta")
        case .mint: return CodexLocalization.text("薄荷", "Mint")
        case .sunset: return CodexLocalization.text("日落", "Sunset")
        }
    }

    private var localizedTitles: [String] {
        switch self {
        case .systemAccent: return ["系统强调色", "System Accent"]
        case .codex: return ["Codex 青", "Codex Teal"]
        case .ocean: return ["Ocean"]
        case .purple: return ["紫罗兰", "Violet"]
        case .blueMagenta: return ["蓝洋红", "Blue Magenta"]
        case .mint: return ["薄荷", "Mint"]
        case .sunset: return ["日落", "Sunset"]
        }
    }

    func colors(for colorScheme: ColorScheme) -> CodexThemeColors {
        if colorScheme == .dark {
            return darkColors
        }

        switch self {
        case .systemAccent:
            return CodexThemeColors(
                primary: .accentColor,
                secondary: .accentColor.opacity(0.48)
            )
        case .codex:
            return CodexThemeColors(
                primary: Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255),
                secondary: Color(red: 115 / 255, green: 107 / 255, blue: 212 / 255)
            )
        case .ocean:
            return CodexThemeColors(
                primary: Color(red: 0.10, green: 0.72, blue: 0.94),
                secondary: Color(red: 0.18, green: 0.36, blue: 0.98)
            )
        case .purple:
            return CodexThemeColors(
                primary: Color(red: 0.56, green: 0.35, blue: 0.96),
                secondary: Color(red: 0.76, green: 0.32, blue: 0.92)
            )
        case .blueMagenta:
            return CodexThemeColors(
                primary: Color(red: 0.10, green: 0.53, blue: 0.98),
                secondary: Color(red: 0.86, green: 0.17, blue: 0.91)
            )
        case .mint:
            return CodexThemeColors(
                primary: Color(red: 0.16, green: 0.76, blue: 0.61),
                secondary: Color(red: 0.10, green: 0.70, blue: 0.86)
            )
        case .sunset:
            return CodexThemeColors(
                primary: Color(red: 0.98, green: 0.47, blue: 0.20),
                secondary: Color(red: 0.96, green: 0.25, blue: 0.51)
            )
        }
    }

    private var darkColors: CodexThemeColors {
        switch self {
        case .systemAccent:
            return CodexThemeColors(
                primary: .accentColor.opacity(0.78),
                secondary: .accentColor.opacity(0.38)
            )
        case .codex:
            return CodexThemeColors(
                primary: Color(red: 0.29, green: 0.59, blue: 0.63),
                secondary: Color(red: 0.45, green: 0.43, blue: 0.68)
            )
        case .ocean:
            return CodexThemeColors(
                primary: Color(red: 0.22, green: 0.58, blue: 0.70),
                secondary: Color(red: 0.30, green: 0.43, blue: 0.71)
            )
        case .purple:
            return CodexThemeColors(
                primary: Color(red: 0.50, green: 0.40, blue: 0.71),
                secondary: Color(red: 0.63, green: 0.38, blue: 0.68)
            )
        case .blueMagenta:
            return CodexThemeColors(
                primary: Color(red: 0.27, green: 0.51, blue: 0.77),
                secondary: Color(red: 0.66, green: 0.36, blue: 0.67)
            )
        case .mint:
            return CodexThemeColors(
                primary: Color(red: 0.29, green: 0.63, blue: 0.55),
                secondary: Color(red: 0.27, green: 0.58, blue: 0.66)
            )
        case .sunset:
            return CodexThemeColors(
                primary: Color(red: 0.78, green: 0.48, blue: 0.28),
                secondary: Color(red: 0.74, green: 0.37, blue: 0.48)
            )
        }
    }

    static func resolve(widgetId: String) -> CodexColorTheme {
        let title = UserDefaults.standard.string(
            forKey: "widget.\(widgetId).colorTheme"
        ) ?? CodexColorTheme.codex.title
        return allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .codex
    }
}

struct CodexThemeColors {
    let primary: Color
    let secondary: Color

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct CodexQuotaWindow: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetAt: Date?
    let durationSeconds: Int

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var usedRatio: Double { max(0, min(1, usedPercent / 100)) }
    var remainingRatio: Double { max(0, min(1, remainingPercent / 100)) }

    func resetDescription(now: Date = Date()) -> String {
        guard let resetAt else {
            return CodexLocalization.text("暂无重置时间", "Reset time unavailable")
        }
        let seconds = max(0, resetAt.timeIntervalSince(now))
        if seconds < 60 { return CodexLocalization.text("即将重置", "Resetting soon") }
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if days > 0 {
            return CodexLocalization.text(
                "\(days)天 \(hours)小时后重置",
                "Resets in \(days)d \(hours)h"
            )
        }
        if hours > 0 {
            return CodexLocalization.text(
                "\(hours)小时 \(minutes)分钟后重置",
                "Resets in \(hours)h \(minutes)m"
            )
        }
        return CodexLocalization.text("\(minutes)分钟后重置", "Resets in \(minutes)m")
    }
}

struct CodexMonthlyCreditLimit: Codable, Equatable, Sendable {
    let used: Double
    let limit: Double
    let remainingPercent: Double
}

enum CodexCostProvenance: String, Codable, Equatable, Sendable {
    case modelsDev
    case builtIn
    case mixed
    case unknown

    var title: String {
        switch self {
        case .modelsDev:
            CodexLocalization.text("models.dev 动态价表", "models.dev pricing")
        case .builtIn:
            CodexLocalization.text("内置价表", "Built-in pricing")
        case .mixed:
            CodexLocalization.text("models.dev + 内置回退", "models.dev + built-in fallback")
        case .unknown:
            CodexLocalization.text("价格未知", "Unknown pricing")
        }
    }
}

struct CodexCostCoverage: Codable, Equatable, Sendable {
    let pricedTokens: Int
    let totalTokens: Int
    let pricedRequests: Int
    let totalRequests: Int

    static let empty = CodexCostCoverage(
        pricedTokens: 0,
        totalTokens: 0,
        pricedRequests: 0,
        totalRequests: 0
    )

    var tokenFraction: Double? {
        guard totalTokens > 0 else { return nil }
        return min(1, max(0, Double(pricedTokens) / Double(totalTokens)))
    }

    var tokenPercent: Double? { tokenFraction.map { $0 * 100 } }
    var isComplete: Bool { totalTokens == 0 || pricedTokens >= totalTokens }

    static func combining<S: Sequence>(_ values: S) -> CodexCostCoverage
    where S.Element == CodexCostCoverage {
        values.reduce(.empty) { partial, value in
            CodexCostCoverage(
                pricedTokens: partial.pricedTokens + value.pricedTokens,
                totalTokens: partial.totalTokens + value.totalTokens,
                pricedRequests: partial.pricedRequests + value.pricedRequests,
                totalRequests: partial.totalRequests + value.totalRequests
            )
        }
    }
}

struct CodexHourlyUsageBucket: Codable, Equatable, Identifiable, Sendable {
    let weekday: Int
    let hour: Int
    let tokens: Int
    let requestCount: Int

    var id: String { "\(weekday)-\(hour)" }
}

struct CodexLocalScanCoverage: Codable, Equatable, Sendable {
    let scannedFiles: Int
    let totalFiles: Int
    let historyDays: Int
    let isComplete: Bool

    static let empty = CodexLocalScanCoverage(
        scannedFiles: 0,
        totalFiles: 0,
        historyDays: 0,
        isComplete: true
    )

    var fraction: Double {
        guard totalFiles > 0 else { return isComplete ? 1 : 0 }
        return min(1, max(0, Double(scannedFiles) / Double(totalFiles)))
    }
}

struct CodexTokenUsageDay: Codable, Equatable, Identifiable, Sendable {
    let dayKey: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let priorityTokens: Int
    let requestCount: Int
    let turnCount: Int
    let estimatedCostUSD: Double?
    let costCoverage: CodexCostCoverage
    let costProvenance: CodexCostProvenance

    var id: String { dayKey }
    var totalTokens: Int { inputTokens + outputTokens }
    var standardTokens: Int { max(0, totalTokens - priorityTokens) }
    var uncachedInputTokens: Int {
        max(0, inputTokens - cachedInputTokens - cacheWriteInputTokens)
    }
    var visibleOutputTokens: Int { max(0, outputTokens - reasoningOutputTokens) }
    var cacheHitPercent: Double? {
        guard inputTokens > 0 else { return nil }
        return min(100, max(0, Double(cachedInputTokens) / Double(inputTokens) * 100))
    }

    init(
        dayKey: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int = 0,
        priorityTokens: Int,
        requestCount: Int = 0,
        turnCount: Int = 0,
        estimatedCostUSD: Double?,
        costCoverage: CodexCostCoverage = .empty,
        costProvenance: CodexCostProvenance = .unknown
    ) {
        self.dayKey = dayKey
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.priorityTokens = priorityTokens
        self.requestCount = requestCount
        self.turnCount = turnCount
        self.estimatedCostUSD = estimatedCostUSD
        self.costCoverage = costCoverage
        self.costProvenance = costProvenance
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case inputTokens
        case cachedInputTokens
        case cacheWriteInputTokens
        case outputTokens
        case reasoningOutputTokens
        case priorityTokens
        case requestCount
        case turnCount
        case estimatedCostUSD
        case costCoverage
        case costProvenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cachedInputTokens = try container.decode(Int.self, forKey: .cachedInputTokens)
        cacheWriteInputTokens = try container.decode(Int.self, forKey: .cacheWriteInputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        reasoningOutputTokens = try container.decodeIfPresent(
            Int.self,
            forKey: .reasoningOutputTokens
        ) ?? 0
        priorityTokens = try container.decode(Int.self, forKey: .priorityTokens)
        requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount) ?? 0
        turnCount = try container.decodeIfPresent(Int.self, forKey: .turnCount) ?? 0
        estimatedCostUSD = try container.decodeIfPresent(
            Double.self,
            forKey: .estimatedCostUSD
        )
        costCoverage = try container.decodeIfPresent(
            CodexCostCoverage.self,
            forKey: .costCoverage
        ) ?? CodexCostCoverage(
            pricedTokens: estimatedCostUSD == nil ? 0 : inputTokens + outputTokens,
            totalTokens: inputTokens + outputTokens,
            pricedRequests: estimatedCostUSD == nil ? 0 : requestCount,
            totalRequests: requestCount
        )
        costProvenance = try container.decodeIfPresent(
            CodexCostProvenance.self,
            forKey: .costProvenance
        ) ?? (estimatedCostUSD == nil ? .unknown : .mixed)
    }
}

struct CodexUsagePeriodSummary: Codable, Equatable, Sendable {
    let dayCount: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let priorityTokens: Int
    let estimatedCostUSD: Double?
    let requestCount: Int
    let turnCount: Int
    let activeDays: Int
    let peakDayKey: String?
    let peakDayTokens: Int
    let costCoverage: CodexCostCoverage
    let costProvenance: CodexCostProvenance

    var totalTokens: Int { inputTokens + outputTokens }
    var standardTokens: Int { max(0, totalTokens - priorityTokens) }
    var uncachedInputTokens: Int {
        max(0, inputTokens - cachedInputTokens - cacheWriteInputTokens)
    }
    var visibleOutputTokens: Int { max(0, outputTokens - reasoningOutputTokens) }
    var cacheHitPercent: Double? {
        guard inputTokens > 0 else { return nil }
        return min(100, max(0, Double(cachedInputTokens) / Double(inputTokens) * 100))
    }

    static let empty = CodexUsagePeriodSummary(
        dayCount: 0,
        inputTokens: 0,
        cachedInputTokens: 0,
        cacheWriteInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        priorityTokens: 0,
        estimatedCostUSD: nil,
        requestCount: 0,
        turnCount: 0,
        activeDays: 0,
        peakDayKey: nil,
        peakDayTokens: 0,
        costCoverage: .empty,
        costProvenance: .unknown
    )

    init(
        dayCount: Int,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int,
        priorityTokens: Int,
        estimatedCostUSD: Double?,
        requestCount: Int,
        turnCount: Int,
        activeDays: Int,
        peakDayKey: String?,
        peakDayTokens: Int,
        costCoverage: CodexCostCoverage = .empty,
        costProvenance: CodexCostProvenance = .unknown
    ) {
        self.dayCount = dayCount
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.priorityTokens = priorityTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.requestCount = requestCount
        self.turnCount = turnCount
        self.activeDays = activeDays
        self.peakDayKey = peakDayKey
        self.peakDayTokens = peakDayTokens
        self.costCoverage = costCoverage
        self.costProvenance = costProvenance
    }

    private enum CodingKeys: String, CodingKey {
        case dayCount, inputTokens, cachedInputTokens, cacheWriteInputTokens
        case outputTokens, reasoningOutputTokens, priorityTokens, estimatedCostUSD
        case requestCount, turnCount, activeDays, peakDayKey, peakDayTokens
        case costCoverage, costProvenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayCount = try container.decode(Int.self, forKey: .dayCount)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cachedInputTokens = try container.decode(Int.self, forKey: .cachedInputTokens)
        cacheWriteInputTokens = try container.decode(Int.self, forKey: .cacheWriteInputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        reasoningOutputTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        priorityTokens = try container.decode(Int.self, forKey: .priorityTokens)
        estimatedCostUSD = try container.decodeIfPresent(Double.self, forKey: .estimatedCostUSD)
        requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount) ?? 0
        turnCount = try container.decodeIfPresent(Int.self, forKey: .turnCount) ?? 0
        activeDays = try container.decodeIfPresent(Int.self, forKey: .activeDays) ?? 0
        peakDayKey = try container.decodeIfPresent(String.self, forKey: .peakDayKey)
        peakDayTokens = try container.decodeIfPresent(Int.self, forKey: .peakDayTokens) ?? 0
        let total = inputTokens + outputTokens
        costCoverage = try container.decodeIfPresent(CodexCostCoverage.self, forKey: .costCoverage)
            ?? CodexCostCoverage(
                pricedTokens: estimatedCostUSD == nil ? 0 : total,
                totalTokens: total,
                pricedRequests: estimatedCostUSD == nil ? 0 : requestCount,
                totalRequests: requestCount
            )
        costProvenance = try container.decodeIfPresent(CodexCostProvenance.self, forKey: .costProvenance)
            ?? (estimatedCostUSD == nil ? .unknown : .mixed)
    }
}

struct CodexUsageComparison: Codable, Equatable, Sendable {
    let previousDayTokens: Int
    let dayOverDayChangePercent: Double?
    let previous7DaysTokens: Int
    let sevenDayChangePercent: Double?

    static let empty = CodexUsageComparison(
        previousDayTokens: 0,
        dayOverDayChangePercent: nil,
        previous7DaysTokens: 0,
        sevenDayChangePercent: nil
    )
}

struct CodexModelUsageSummary: Codable, Equatable, Identifiable, Sendable {
    let model: String
    let tokens: Int
    let estimatedCostUSD: Double?
    let requestCount: Int
    let turnCount: Int
    let standardTokens: Int
    let priorityTokens: Int
    let standardRequestCount: Int
    let priorityRequestCount: Int
    var costCoverage: CodexCostCoverage? = nil
    var costProvenance: CodexCostProvenance? = nil

    var id: String { model }
}

struct CodexProjectUsageSummary: Codable, Equatable, Identifiable, Sendable {
    let projectName: String
    /// Kept for local open/tooltip actions. It is never derived from prompt content.
    let projectPath: String
    let tokens: Int
    let estimatedCostUSD: Double?
    let requestCount: Int
    let turnCount: Int
    let sessionCount: Int
    let lastActiveAt: Date
    var costCoverage: CodexCostCoverage? = nil
    var costProvenance: CodexCostProvenance? = nil

    var id: String { projectPath }
}

struct CodexSessionUsageSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let projectName: String
    /// Kept for local open/tooltip actions. Only the final component is shown by default.
    let projectPath: String
    let dominantModel: String?
    let tokens: Int
    let estimatedCostUSD: Double?
    let requestCount: Int
    let turnCount: Int
    let completedTurnCount: Int
    let abortedTurnCount: Int
    let startedAt: Date
    let lastActiveAt: Date
    let averageTurnDurationSeconds: Double?
    let averageTimeToFirstTokenMilliseconds: Double?
    let compactionCount: Int
    let isActive: Bool
    var costCoverage: CodexCostCoverage? = nil
    var costProvenance: CodexCostProvenance? = nil
}

struct CodexContextHealthSnapshot: Codable, Equatable, Identifiable, Sendable {
    let sessionID: String
    let parentSessionID: String?
    let projectName: String
    /// Kept for local open/tooltip actions and never populated from message content.
    let projectPath: String
    let model: String?
    let capturedAt: Date
    let contextWindowTokens: Int
    let usedContextTokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let compactionCount: Int
    let isSubagent: Bool
    let isActive: Bool

    var id: String { sessionID }
    var remainingContextTokens: Int {
        max(0, contextWindowTokens - usedContextTokens)
    }
    var usedPercent: Double {
        guard contextWindowTokens > 0 else { return 0 }
        return min(
            100,
            max(0, Double(usedContextTokens) / Double(contextWindowTokens) * 100)
        )
    }
    var cacheHitPercent: Double? {
        guard inputTokens > 0 else { return nil }
        return min(100, max(0, Double(cachedInputTokens) / Double(inputTokens) * 100))
    }
}

struct CodexRecentUsageSnapshot: Codable, Equatable, Sendable {
    let todayTokens: Int
    let todayEstimatedCostUSD: Double?
    let last30DaysTokens: Int
    let last30DaysEstimatedCostUSD: Double?
    let daily: [CodexTokenUsageDay]
    let mostUsedModel: String?
    let pricingSource: String?
    let updatedAt: Date
    let last7DaysSummary: CodexUsagePeriodSummary
    let last30DaysSummary: CodexUsagePeriodSummary
    let allTimeSummary: CodexUsagePeriodSummary
    let comparison: CodexUsageComparison
    let topModels: [CodexModelUsageSummary]
    let topProjects: [CodexProjectUsageSummary]
    let recentSessions: [CodexSessionUsageSummary]
    let recentContextHealth: [CodexContextHealthSnapshot]
    let hourly: [CodexHourlyUsageBucket]
    let hourlyLastYear: [CodexHourlyUsageBucket]
    let historyStart: Date?
    let historyEnd: Date?
    let timeZoneIdentifier: String
    let scanCoverage: CodexLocalScanCoverage

    var chartDays: [CodexTokenUsageDay] {
        Array(daily.suffix(8))
    }

    var latestContextHealth: CodexContextHealthSnapshot? {
        recentContextHealth.first
    }

    init(
        todayTokens: Int,
        todayEstimatedCostUSD: Double?,
        last30DaysTokens: Int,
        last30DaysEstimatedCostUSD: Double?,
        daily: [CodexTokenUsageDay],
        mostUsedModel: String?,
        pricingSource: String?,
        updatedAt: Date,
        last7DaysSummary: CodexUsagePeriodSummary = .empty,
        last30DaysSummary: CodexUsagePeriodSummary = .empty,
        allTimeSummary: CodexUsagePeriodSummary = .empty,
        comparison: CodexUsageComparison = .empty,
        topModels: [CodexModelUsageSummary] = [],
        topProjects: [CodexProjectUsageSummary] = [],
        recentSessions: [CodexSessionUsageSummary] = [],
        recentContextHealth: [CodexContextHealthSnapshot] = [],
        hourly: [CodexHourlyUsageBucket] = [],
        hourlyLastYear: [CodexHourlyUsageBucket]? = nil,
        historyStart: Date? = nil,
        historyEnd: Date? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        scanCoverage: CodexLocalScanCoverage = .empty
    ) {
        self.todayTokens = todayTokens
        self.todayEstimatedCostUSD = todayEstimatedCostUSD
        self.last30DaysTokens = last30DaysTokens
        self.last30DaysEstimatedCostUSD = last30DaysEstimatedCostUSD
        self.daily = daily
        self.mostUsedModel = mostUsedModel
        self.pricingSource = pricingSource
        self.updatedAt = updatedAt
        self.last7DaysSummary = last7DaysSummary
        self.last30DaysSummary = last30DaysSummary
        self.allTimeSummary = allTimeSummary
        self.comparison = comparison
        self.topModels = topModels
        self.topProjects = topProjects
        self.recentSessions = recentSessions
        self.recentContextHealth = recentContextHealth
        self.hourly = hourly
        self.hourlyLastYear = hourlyLastYear ?? hourly
        self.historyStart = historyStart
        self.historyEnd = historyEnd
        self.timeZoneIdentifier = timeZoneIdentifier
        self.scanCoverage = scanCoverage
    }

    private enum CodingKeys: String, CodingKey {
        case todayTokens
        case todayEstimatedCostUSD
        case last30DaysTokens
        case last30DaysEstimatedCostUSD
        case daily
        case mostUsedModel
        case pricingSource
        case updatedAt
        case last7DaysSummary
        case last30DaysSummary
        case allTimeSummary
        case comparison
        case topModels
        case topProjects
        case recentSessions
        case recentContextHealth
        case hourly
        case hourlyLastYear
        case historyStart
        case historyEnd
        case timeZoneIdentifier
        case scanCoverage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        todayTokens = try container.decode(Int.self, forKey: .todayTokens)
        todayEstimatedCostUSD = try container.decodeIfPresent(
            Double.self,
            forKey: .todayEstimatedCostUSD
        )
        last30DaysTokens = try container.decode(Int.self, forKey: .last30DaysTokens)
        last30DaysEstimatedCostUSD = try container.decodeIfPresent(
            Double.self,
            forKey: .last30DaysEstimatedCostUSD
        )
        daily = try container.decode([CodexTokenUsageDay].self, forKey: .daily)
        mostUsedModel = try container.decodeIfPresent(String.self, forKey: .mostUsedModel)
        pricingSource = try container.decodeIfPresent(String.self, forKey: .pricingSource)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        last7DaysSummary = try container.decodeIfPresent(
            CodexUsagePeriodSummary.self,
            forKey: .last7DaysSummary
        ) ?? .empty
        last30DaysSummary = try container.decodeIfPresent(
            CodexUsagePeriodSummary.self,
            forKey: .last30DaysSummary
        ) ?? .empty
        allTimeSummary = try container.decodeIfPresent(
            CodexUsagePeriodSummary.self,
            forKey: .allTimeSummary
        ) ?? last30DaysSummary
        comparison = try container.decodeIfPresent(
            CodexUsageComparison.self,
            forKey: .comparison
        ) ?? .empty
        topModels = try container.decodeIfPresent(
            [CodexModelUsageSummary].self,
            forKey: .topModels
        ) ?? []
        topProjects = try container.decodeIfPresent(
            [CodexProjectUsageSummary].self,
            forKey: .topProjects
        ) ?? []
        recentSessions = try container.decodeIfPresent(
            [CodexSessionUsageSummary].self,
            forKey: .recentSessions
        ) ?? []
        recentContextHealth = try container.decodeIfPresent(
            [CodexContextHealthSnapshot].self,
            forKey: .recentContextHealth
        ) ?? []
        hourly = try container.decodeIfPresent(
            [CodexHourlyUsageBucket].self,
            forKey: .hourly
        ) ?? []
        hourlyLastYear = try container.decodeIfPresent(
            [CodexHourlyUsageBucket].self,
            forKey: .hourlyLastYear
        ) ?? hourly
        historyStart = try container.decodeIfPresent(Date.self, forKey: .historyStart)
        historyEnd = try container.decodeIfPresent(Date.self, forKey: .historyEnd)
        timeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .timeZoneIdentifier
        ) ?? TimeZone.current.identifier
        scanCoverage = try container.decodeIfPresent(
            CodexLocalScanCoverage.self,
            forKey: .scanCoverage
        ) ?? .empty
    }
}

struct CodexUsageSnapshot: Codable, Equatable {
    let accountEmail: String?
    let plan: String?
    let sessionWindow: CodexQuotaWindow?
    let weeklyWindow: CodexQuotaWindow?
    var monthlyWindow: CodexQuotaWindow? = nil
    var monthlyCreditLimit: CodexMonthlyCreditLimit? = nil
    let extraWindows: [CodexQuotaWindow]
    let creditsBalance: Double?
    let resetCreditsAvailable: Int?
    let resetCreditsExpiresAt: Date?
    let fetchedAt: Date

    var displayPlan: String {
        guard let plan, !plan.isEmpty else { return "Codex" }
        switch plan.lowercased() {
        case "pro", "prolite", "pro_lite": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return plan.capitalized
        }
    }
}

enum OpenAIServiceIndicator: String, Codable, Equatable {
    case operational
    case degraded
    case partialOutage
    case majorOutage
    case maintenance
    case unknown

    init(status: String) {
        switch status {
        case "operational": self = .operational
        case "degraded_performance": self = .degraded
        case "partial_outage": self = .partialOutage
        case "major_outage", "full_outage": self = .majorOutage
        case "under_maintenance": self = .maintenance
        default: self = .unknown
        }
    }

    init(overallIndicator: String) {
        switch overallIndicator {
        case "none": self = .operational
        case "minor": self = .degraded
        case "major": self = .partialOutage
        case "critical": self = .majorOutage
        case "maintenance": self = .maintenance
        default: self = .unknown
        }
    }

    var rank: Int {
        switch self {
        case .operational: return 0
        case .maintenance, .unknown: return 1
        case .degraded: return 2
        case .partialOutage: return 3
        case .majorOutage: return 4
        }
    }

    var label: String {
        switch self {
        case .operational: return CodexLocalization.text("正常运行", "Operational")
        case .degraded: return CodexLocalization.text("性能下降", "Degraded")
        case .partialOutage: return CodexLocalization.text("部分中断", "Partial outage")
        case .majorOutage: return CodexLocalization.text("服务中断", "Major outage")
        case .maintenance: return CodexLocalization.text("维护中", "Maintenance")
        case .unknown: return CodexLocalization.text("状态未知", "Unknown")
        }
    }

    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .operational: return CodexPalette.green(for: colorScheme)
        case .maintenance, .degraded: return CodexPalette.yellow(for: colorScheme)
        case .partialOutage, .majorOutage: return CodexPalette.red(for: colorScheme)
        case .unknown: return .secondary
        }
    }
}

struct OpenAIStatusComponent: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let indicator: OpenAIServiceIndicator
}

struct OpenAIStatusGroup: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let components: [OpenAIStatusComponent]

    var indicator: OpenAIServiceIndicator {
        components.max { $0.indicator.rank < $1.indicator.rank }?.indicator ?? .unknown
    }
}

struct OpenAIStatusSnapshot: Codable, Equatable {
    let overallIndicator: OpenAIServiceIndicator
    let description: String?
    let groups: [OpenAIStatusGroup]
    let fetchedAt: Date

    func group(named name: String) -> OpenAIStatusGroup? {
        groups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var codex: OpenAIStatusGroup? { group(named: "Codex") }
    var chatGPT: OpenAIStatusGroup? { group(named: "ChatGPT") }
}

enum CodexDisplayLimit: String, CaseIterable, Identifiable {
    case weekly
    case session
    case monthly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: CodexLocalization.text("每周额度", "Weekly quota")
        case .session: CodexLocalization.text("短周期额度", "Session quota")
        case .monthly: CodexLocalization.text("月度额度", "Monthly quota")
        }
    }
    var shortLabel: String {
        switch self {
        case .weekly: "WEEK"
        case .session: "SESSION"
        case .monthly: "MONTH"
        }
    }

    static func resolve(title: String) -> CodexDisplayLimit {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .weekly
    }

    private var localizedTitles: [String] {
        switch self {
        case .weekly: ["每周额度", "Weekly quota"]
        case .session: ["短周期额度", "Session quota"]
        case .monthly: ["月度额度", "Monthly quota"]
        }
    }
}

enum CodexDockProvider: String, CaseIterable, Identifiable {
    case codex
    case cursor
    case both
    case claude
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .claude: "Claude"
        case .all: CodexLocalization.text("全部服务", "All providers")
        case .both: CodexLocalization.text("同时展示", "Codex + Cursor")
        }
    }

    static func resolve(title: String) -> CodexDockProvider {
        if ["all", "全部服务", "All providers"].contains(title) { return .all }
        if ["both", "同时展示", "Codex + Cursor", "Both"].contains(title) {
            return .both
        }
        return allCases.first { title == $0.rawValue || title == $0.title } ?? .codex
    }
}

enum CodexDisplayMetric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
    var title: String {
        self == .remaining
            ? CodexLocalization.text("显示剩余", "Show remaining")
            : CodexLocalization.text("显示已用", "Show used")
    }

    static func resolve(title: String) -> CodexDisplayMetric {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .remaining
    }

    private var localizedTitles: [String] {
        self == .remaining ? ["显示剩余", "Show remaining"] : ["显示已用", "Show used"]
    }
}

enum CodexHourlyActivityRange: String, CaseIterable, Identifiable {
    case currentWeek
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWeek: return CodexLocalization.text("本周", "This week")
        case .lastYear: return CodexLocalization.text("近一年", "Last year")
        }
    }

    static func resolve(title: String) -> CodexHourlyActivityRange {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .currentWeek
    }

    private var localizedTitles: [String] {
        switch self {
        case .currentWeek: return ["本周", "This week"]
        case .lastYear: return ["近一年", "Last year"]
        }
    }
}

enum CodexTokenFormat: String, CaseIterable, Identifiable {
    case automatic
    case exact
    case millionsTwoDecimals
    case millionsOneDecimal
    case billionsTwoDecimals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return CodexLocalization.text("自动（240.2M）", "Automatic (240.2M)")
        case .exact:
            return CodexLocalization.text("完整（240,176,932）", "Exact (240,176,932)")
        case .millionsTwoDecimals:
            return CodexLocalization.text("百万两位（240.18M）", "Millions · 2 decimals (240.18M)")
        case .millionsOneDecimal:
            return CodexLocalization.text("百万一位（240.2M）", "Millions · 1 decimal (240.2M)")
        case .billionsTwoDecimals:
            return CodexLocalization.text("十亿两位（0.24B）", "Billions · 2 decimals (0.24B)")
        }
    }

    static func resolve(title: String) -> CodexTokenFormat {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .automatic
    }

    func format(_ value: Int) -> String {
        format(Int64(value))
    }

    func format(_ value: Int64) -> String {
        switch self {
        case .automatic:
            return adaptive(value)
        case .exact:
            return value.formatted(.number.locale(CodexLocalization.locale))
        case .millionsTwoDecimals:
            return fixed(value, divisor: 1_000_000, suffix: "M", fractionDigits: 2)
        case .millionsOneDecimal:
            return fixed(value, divisor: 1_000_000, suffix: "M", fractionDigits: 1)
        case .billionsTwoDecimals:
            return fixed(value, divisor: 1_000_000_000, suffix: "B", fractionDigits: 2)
        }
    }

    private var localizedTitles: [String] {
        switch self {
        case .automatic:
            return ["自动（240.2M）", "Automatic (240.2M)", "自动", "Automatic"]
        case .exact:
            return ["完整（240,176,932）", "Exact (240,176,932)", "完整数字", "Exact"]
        case .millionsTwoDecimals:
            return ["百万两位（240.18M）", "Millions · 2 decimals (240.18M)"]
        case .millionsOneDecimal:
            return ["百万一位（240.2M）", "Millions · 1 decimal (240.2M)"]
        case .billionsTwoDecimals:
            return ["十亿两位（0.24B）", "Billions · 2 decimals (0.24B)"]
        }
    }

    private func adaptive(_ value: Int64) -> String {
        let absolute = abs(Double(value))
        switch absolute {
        case 1_000_000_000...:
            return adaptive(value, divisor: 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return adaptive(value, divisor: 1_000_000, suffix: "M")
        case 1_000...:
            return adaptive(value, divisor: 1_000, suffix: "K")
        default:
            return value.formatted(.number.locale(CodexLocalization.locale))
        }
    }

    private func adaptive(
        _ value: Int64,
        divisor: Double,
        suffix: String
    ) -> String {
        let scaled = Double(value) / divisor
        let fractionDigits = scaled.magnitude >= 100 ? 1 : 2
        let number = scaled.formatted(
            .number
                .locale(CodexLocalization.locale)
                .precision(.fractionLength(0...fractionDigits))
        )
        return number + suffix
    }

    private func fixed(
        _ value: Int64,
        divisor: Double,
        suffix: String,
        fractionDigits: Int
    ) -> String {
        let number = (Double(value) / divisor).formatted(
            .number
                .locale(CodexLocalization.locale)
                .precision(.fractionLength(fractionDigits))
        )
        return number + suffix
    }
}

enum CodexTerminalApplication: String, CaseIterable, Identifiable {
    case automatic
    case terminal
    case ghostty
    case iTerm2
    case warp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return CodexLocalization.text("自动", "Automatic")
        case .terminal:
            return "Terminal"
        case .ghostty:
            return "Ghostty"
        case .iTerm2:
            return "iTerm2"
        case .warp:
            return "Warp"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .automatic:
            return nil
        case .terminal:
            return "com.apple.Terminal"
        case .ghostty:
            return "com.mitchellh.ghostty"
        case .iTerm2:
            return "com.googlecode.iterm2"
        case .warp:
            return "dev.warp.Warp-Stable"
        }
    }

    static func resolve(title: String) -> CodexTerminalApplication {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .automatic
    }

    private var localizedTitles: [String] {
        switch self {
        case .automatic:
            return ["自动", "Automatic"]
        case .terminal:
            return ["Terminal"]
        case .ghostty:
            return ["Ghostty"]
        case .iTerm2:
            return ["iTerm2", "iTerm"]
        case .warp:
            return ["Warp"]
        }
    }
}

enum CodexRingStyle: String, CaseIterable, Identifiable {
    case classic
    case concentric
    case segmented
    case carousel

    static let carouselStyles: [CodexRingStyle] = [
        .classic,
        .concentric,
        .segmented,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return CodexLocalization.text("原版圆环", "Classic Ring")
        case .concentric: return CodexLocalization.text("同心多环", "Concentric Rings")
        case .segmented: return CodexLocalization.text("分段圆环", "Segmented Ring")
        case .carousel: return CodexLocalization.text("自动轮播", "Auto Carousel")
        }
    }

    static func resolve(title: String) -> CodexRingStyle {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .concentric
    }

    private var localizedTitles: [String] {
        switch self {
        case .classic: return ["原版圆环", "Classic Ring"]
        case .concentric: return ["同心多环", "Concentric Rings"]
        case .segmented: return ["分段圆环", "Segmented Ring"]
        case .carousel: return ["自动轮播", "Auto Carousel"]
        }
    }
}

enum CodexRefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .oneMinute: return CodexLocalization.text("1 分钟", "1 minute")
        case .fiveMinutes: return CodexLocalization.text("5 分钟", "5 minutes")
        case .fifteenMinutes: return CodexLocalization.text("15 分钟", "15 minutes")
        case .thirtyMinutes: return CodexLocalization.text("30 分钟", "30 minutes")
        }
    }

    static func resolve(title: String) -> CodexRefreshInterval {
        allCases.first { item in
            title == String(item.rawValue) || item.localizedTitles.contains(title)
        } ?? .fiveMinutes
    }

    private var localizedTitles: [String] {
        switch self {
        case .oneMinute: return ["1 分钟", "1 minute"]
        case .fiveMinutes: return ["5 分钟", "5 minutes"]
        case .fifteenMinutes: return ["15 分钟", "15 minutes"]
        case .thirtyMinutes: return ["30 分钟", "30 minutes"]
        }
    }
}

extension Date {
    var codexShortTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var codexRelativeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
