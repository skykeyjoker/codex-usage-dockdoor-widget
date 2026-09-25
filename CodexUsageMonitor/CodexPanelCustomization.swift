import DockDoorWidgetSDK
import Foundation

enum CodexPanelContentPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case simplified
    case full
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplified: return CodexLocalization.text("精简", "Simplified")
        case .full: return CodexLocalization.text("完整", "Full")
        case .custom: return CodexLocalization.text("自定义", "Custom")
        }
    }

    var help: String {
        switch self {
        case .simplified:
            return CodexLocalization.text(
                "仅保留各页面最常用的核心信息。",
                "Keep only the most useful information on each page."
            )
        case .full:
            return CodexLocalization.text(
                "展示各页面提供的全部卡片。",
                "Show every card available on each page."
            )
        case .custom:
            return CodexLocalization.text(
                "已单独调整卡片显隐或顺序。",
                "Card visibility or order has been customized."
            )
        }
    }
}

enum CodexPanelConfigurablePage: String, Codable, CaseIterable, Hashable, Identifiable {
    case overview
    case insights
    case work
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return CodexLocalization.text("额度总览", "Quota overview")
        case .insights: return CodexLocalization.text("用量洞察", "Usage insights")
        case .work: return CodexLocalization.text("项目与任务", "Projects & tasks")
        case .status: return CodexLocalization.text("服务状态", "Service status")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .insights: return "chart.xyaxis.line"
        case .work: return "bubble.left.and.text.bubble.right.fill"
        case .status: return "waveform.path.ecg"
        }
    }

    var navigationHelp: String {
        switch self {
        case .overview:
            return CodexLocalization.text("额度总览与消耗节奏", "Quota overview and pace")
        case .insights:
            return CodexLocalization.text(
                "官方活动与本地用量洞察",
                "Official activity and local insights"
            )
        case .work:
            return CodexLocalization.text(
                "项目、对话与任务效率",
                "Projects, conversations, and task efficiency"
            )
        case .status:
            return CodexLocalization.text(
                "OpenAI / Claude / Cursor 服务状态",
                "OpenAI / Claude / Cursor service status"
            )
        }
    }
}

enum CodexPanelCustomizationSection: String, Codable, CaseIterable, Hashable, Identifiable {
    case overview
    case officialInsights
    case localInsights
    case projects
    case conversations
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return CodexLocalization.text("额度总览", "Quota overview")
        case .officialInsights: return CodexLocalization.text("官方活动", "Official activity")
        case .localInsights: return CodexLocalization.text("本地用量", "Local usage")
        case .projects: return CodexLocalization.text("项目", "Projects")
        case .conversations: return CodexLocalization.text("对话 / 任务", "Conversations / Tasks")
        case .status: return CodexLocalization.text("服务状态", "Service status")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .officialInsights: return "checkmark.seal.fill"
        case .localInsights: return "internaldrive.fill"
        case .projects: return "folder.fill"
        case .conversations: return "bubble.left.and.text.bubble.right.fill"
        case .status: return "waveform.path.ecg"
        }
    }

    var defaultCards: [CodexPanelCardID] {
        switch self {
        case .overview:
            return [
                .overviewAccount,
                .overviewWeeklyQuota,
                .overviewSessionQuota,
                .overviewRecentUsage,
                .overviewQuotaSupplement,
                .overviewExtraModels,
                .overviewFooter,
            ]
        case .officialInsights:
            return [
                .officialSummary,
                .officialHeatmap,
                .officialTrend,
                .officialSource,
            ]
        case .localInsights:
            return [
                .localSummary,
                .localComposition,
                .localHourlyActivity,
                .localTopModels,
                .localPricingSource,
            ]
        case .projects:
            return [.projectsSummary, .projectsList, .projectsScope]
        case .conversations:
            return [
                .conversationMetrics,
                .conversationSummary,
                .conversationList,
                .conversationFooter,
            ]
        case .status:
            return [.statusOverall, .statusChatGPT, .statusCodex, .statusClaude, .statusCursor, .statusFooter]
        }
    }

    var simplifiedCards: Set<CodexPanelCardID> {
        switch self {
        case .overview:
            return [.overviewAccount, .overviewWeeklyQuota, .overviewRecentUsage]
        case .officialInsights:
            return [.officialSummary, .officialTrend]
        case .localInsights:
            return [.localSummary, .localComposition]
        case .projects:
            return [.projectsSummary, .projectsList]
        case .conversations:
            return [.conversationSummary, .conversationList]
        case .status:
            return [.statusOverall, .statusClaude, .statusCursor]
        }
    }
}

enum CodexPanelCardID: String, Codable, Hashable, Identifiable {
    case overviewAccount
    case overviewWeeklyQuota
    case overviewSessionQuota
    case overviewRecentUsage
    case overviewQuotaSupplement
    case overviewExtraModels
    case overviewFooter

    case officialSummary
    case officialHeatmap
    case officialTrend
    case officialSource

    case localSummary
    case localHourlyActivity
    case localComposition
    case localTopModels
    case localPricingSource

    case projectsSummary
    case projectsList
    case projectsScope

    case conversationMetrics
    case conversationSummary
    case conversationList
    case conversationFooter

    case statusOverall
    case statusChatGPT
    case statusCodex
    case statusClaude
    case statusCursor
    case statusFooter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overviewAccount: return CodexLocalization.text("账户", "Account")
        case .overviewWeeklyQuota: return CodexLocalization.text("每周额度", "Weekly quota")
        case .overviewSessionQuota: return CodexLocalization.text("短周期额度", "Session quota")
        case .overviewRecentUsage: return CodexLocalization.text("最近 Token 使用", "Recent token usage")
        case .overviewQuotaSupplement: return CodexLocalization.text("额度补充", "Quota supplements")
        case .overviewExtraModels: return CodexLocalization.text("额外模型额度", "Extra model quotas")
        case .overviewFooter: return CodexLocalization.text("更新时间与操作", "Update time and actions")
        case .officialSummary: return CodexLocalization.text("官方汇总", "Official summary")
        case .officialHeatmap: return CodexLocalization.text("近一年活跃度", "Last year activity")
        case .officialTrend: return CodexLocalization.text("使用趋势", "Usage trend")
        case .officialSource: return CodexLocalization.text("数据来源", "Data source")
        case .localSummary: return CodexLocalization.text("本地汇总", "Local summary")
        case .localHourlyActivity: return CodexLocalization.text("小时活跃度", "Hourly activity")
        case .localComposition: return CodexLocalization.text("Token 构成", "Token composition")
        case .localTopModels: return CodexLocalization.text("常用模型", "Top models")
        case .localPricingSource: return CodexLocalization.text("价格说明", "Pricing note")
        case .projectsSummary: return CodexLocalization.text("项目汇总", "Project summary")
        case .projectsList: return CodexLocalization.text("项目列表", "Project list")
        case .projectsScope: return CodexLocalization.text("数据范围", "Data scope")
        case .conversationMetrics: return CodexLocalization.text("上下文与任务效率", "Context and task metrics")
        case .conversationSummary: return CodexLocalization.text("对话汇总", "Conversation summary")
        case .conversationList: return CodexLocalization.text("最近对话 / 任务", "Recent conversations / tasks")
        case .conversationFooter: return CodexLocalization.text("更新时间与操作", "Update time and actions")
        case .statusOverall: return CodexLocalization.text("服务卡片状态摘要", "Service card status summary")
        case .statusChatGPT: return "ChatGPT"
        case .statusClaude: return "Claude"
        case .statusCursor: return "Cursor"
        case .statusCodex: return "Codex"
        case .statusFooter: return CodexLocalization.text("刷新与状态页入口", "Refresh and status page actions")
        }
    }

    var symbol: String {
        switch self {
        case .overviewAccount: return "person.crop.circle"
        case .overviewWeeklyQuota: return "calendar"
        case .overviewSessionQuota: return "timer"
        case .overviewRecentUsage: return "chart.bar.fill"
        case .overviewQuotaSupplement: return "arrow.counterclockwise.circle.fill"
        case .overviewExtraModels: return "sparkles"
        case .overviewFooter, .conversationFooter: return "clock"
        case .officialSummary, .localSummary: return "square.grid.2x2.fill"
        case .officialHeatmap: return "calendar.badge.clock"
        case .officialTrend: return "chart.xyaxis.line"
        case .officialSource: return "checkmark.seal.fill"
        case .localHourlyActivity: return "clock.badge"
        case .localComposition: return "chart.bar.doc.horizontal"
        case .localTopModels: return "cpu"
        case .localPricingSource: return "dollarsign.circle"
        case .projectsSummary: return "chart.bar.xaxis"
        case .projectsList: return "folder.fill"
        case .projectsScope: return "lock.shield.fill"
        case .conversationMetrics: return "brain.head.profile"
        case .conversationSummary: return "rectangle.grid.3x1.fill"
        case .conversationList: return "bubble.left.and.text.bubble.right.fill"
        case .statusOverall: return "circle.circle.fill"
        case .statusChatGPT: return "bubble.left.and.bubble.right.fill"
        case .statusClaude: return "asterisk"
        case .statusCursor: return "cube.fill"
        case .statusCodex: return "terminal.fill"
        case .statusFooter: return "arrow.up.right.square"
        }
    }
}

struct CodexPanelCardPreference: Codable, Equatable, Identifiable {
    let id: CodexPanelCardID
    var isVisible: Bool
}

struct CodexPanelCardConfiguration: Codable, Equatable {
    static let storageKey = "panelCardConfigurationV1"
    private static let version = 4

    var schemaVersion: Int
    var preset: CodexPanelContentPreset
    var sections: [String: [CodexPanelCardPreference]]
    // Optional keeps existing V1 payloads decodable. A missing value means
    // every page is visible, which is also the migration default.
    var hiddenPages: Set<CodexPanelConfigurablePage>?

    static var full: CodexPanelCardConfiguration {
        make(preset: .full)
    }

    static func load(widgetId: String) -> CodexPanelCardConfiguration {
        let raw = WidgetDefaults.string(key: storageKey, widgetId: widgetId)
        guard let data = raw.data(using: .utf8),
              var decoded = try? JSONDecoder().decode(CodexPanelCardConfiguration.self, from: data)
        else {
            var migrated = CodexPanelCardConfiguration.full
            let showsLegacyExtraModels = WidgetDefaults.bool(
                key: "showExtraModelQuotas",
                widgetId: widgetId,
                default: true
            )
            if !showsLegacyExtraModels {
                migrated.setVisible(
                    false,
                    card: .overviewExtraModels,
                    in: .overview
                )
            }
            return migrated
        }
        decoded.normalize()
        return decoded
    }

    static func make(preset: CodexPanelContentPreset) -> CodexPanelCardConfiguration {
        let resolvedPreset = preset == .custom ? CodexPanelContentPreset.full : preset
        let sections = Dictionary(uniqueKeysWithValues: CodexPanelCustomizationSection.allCases.map { section in
            let cards = section.defaultCards.map { card in
                CodexPanelCardPreference(
                    id: card,
                    isVisible: resolvedPreset == .full || section.simplifiedCards.contains(card)
                )
            }
            return (section.rawValue, cards)
        })
        return CodexPanelCardConfiguration(
            schemaVersion: version,
            preset: resolvedPreset,
            sections: sections,
            hiddenPages: []
        )
    }

    var visiblePages: [CodexPanelConfigurablePage] {
        CodexPanelConfigurablePage.allCases.filter(isPageVisible)
    }

    func isPageVisible(_ page: CodexPanelConfigurablePage) -> Bool {
        !(hiddenPages ?? []).contains(page)
    }

    func preferences(for section: CodexPanelCustomizationSection) -> [CodexPanelCardPreference] {
        sections[section.rawValue] ?? section.defaultCards.map {
            CodexPanelCardPreference(id: $0, isVisible: true)
        }
    }

    func visibleCards(in section: CodexPanelCustomizationSection) -> [CodexPanelCardID] {
        preferences(for: section).filter(\.isVisible).map(\.id)
    }

    func isVisible(_ card: CodexPanelCardID, in section: CodexPanelCustomizationSection) -> Bool {
        preferences(for: section).first(where: { $0.id == card })?.isVisible ?? true
    }

    mutating func apply(_ newPreset: CodexPanelContentPreset) {
        guard newPreset != .custom else {
            preset = .custom
            return
        }
        self = Self.make(preset: newPreset)
    }

    mutating func setVisible(
        _ visible: Bool,
        card: CodexPanelCardID,
        in section: CodexPanelCustomizationSection
    ) {
        normalize()
        guard var cards = sections[section.rawValue],
              let index = cards.firstIndex(where: { $0.id == card })
        else { return }

        if !visible, cards.filter(\.isVisible).count <= 1 {
            return
        }
        cards[index].isVisible = visible
        sections[section.rawValue] = cards
        preset = .custom
    }

    mutating func setPageVisible(
        _ visible: Bool,
        page: CodexPanelConfigurablePage
    ) {
        normalize()
        var hidden = hiddenPages ?? []
        if visible {
            hidden.remove(page)
        } else {
            guard visiblePages.count > 1 else { return }
            hidden.insert(page)
        }
        hiddenPages = hidden
        preset = .custom
    }

    mutating func move(
        card: CodexPanelCardID,
        in section: CodexPanelCustomizationSection,
        offset: Int
    ) {
        normalize()
        guard var cards = sections[section.rawValue],
              let source = cards.firstIndex(where: { $0.id == card })
        else { return }
        let destination = source + offset
        guard cards.indices.contains(destination) else { return }
        cards.swapAt(source, destination)
        sections[section.rawValue] = cards
        preset = .custom
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private mutating func normalize() {
        let requiresHourlyLocationMigration = schemaVersion < 3
        schemaVersion = Self.version
        let allowedPages = Set(CodexPanelConfigurablePage.allCases)
        var normalizedHiddenPages = (hiddenPages ?? []).intersection(allowedPages)
        if normalizedHiddenPages.count == allowedPages.count {
            normalizedHiddenPages.remove(.overview)
        }
        hiddenPages = normalizedHiddenPages

        let previousHourlyVisibility = sections[CodexPanelCustomizationSection.overview.rawValue]?
            .first(where: { $0.id == .localHourlyActivity })?.isVisible
            ?? sections[CodexPanelCustomizationSection.localInsights.rawValue]?
                .first(where: { $0.id == .localHourlyActivity })?.isVisible
        let previousLocalSummaryVisibility = sections[CodexPanelCustomizationSection.localInsights.rawValue]?
            .first(where: { $0.id == .localSummary })?.isVisible

        for section in CodexPanelCustomizationSection.allCases {
            let allowed = Set(section.defaultCards)
            var seen = Set<CodexPanelCardID>()
            var cards = (sections[section.rawValue] ?? []).filter { preference in
                allowed.contains(preference.id) && seen.insert(preference.id).inserted
            }
            for card in section.defaultCards where !seen.contains(card) {
                let isVisible: Bool
                if card == .localHourlyActivity {
                    if let previousHourlyVisibility {
                        isVisible = previousHourlyVisibility
                    } else if preset == .simplified {
                        isVisible = false
                    } else {
                        isVisible = previousLocalSummaryVisibility ?? true
                    }
                } else {
                    isVisible = true
                }
                let preference = CodexPanelCardPreference(id: card, isVisible: isVisible)
                let defaultIndex = section.defaultCards.firstIndex(of: card) ?? section.defaultCards.count
                let followingCards = section.defaultCards.dropFirst(defaultIndex + 1)
                let insertionIndex = followingCards.compactMap { followingCard in
                    cards.firstIndex(where: { $0.id == followingCard })
                }.first ?? cards.count
                cards.insert(preference, at: insertionIndex)
                seen.insert(card)
            }
            if requiresHourlyLocationMigration,
               section == .localInsights,
               let hourlyIndex = cards.firstIndex(where: { $0.id == .localHourlyActivity })
            {
                let hourlyPreference = cards.remove(at: hourlyIndex)
                let insertionIndex = cards.firstIndex(where: { $0.id == .localTopModels })
                    ?? cards.firstIndex(where: { $0.id == .localPricingSource })
                    ?? cards.count
                cards.insert(hourlyPreference, at: insertionIndex)
            }
            if !cards.contains(where: \.isVisible), !cards.isEmpty {
                cards[0].isVisible = true
            }
            sections[section.rawValue] = cards
        }
    }
}
