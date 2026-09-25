import AppKit
import SwiftUI

struct ProviderInsightsView: View {
    let provider: UsageProvider
    let official: Bool
    @ObservedObject var monitor: CodexUsageMonitor
    let configuration: CodexPanelCardConfiguration
    let tokenFormat: CodexTokenFormat
    let showOtherSource: () -> Void
    @Environment(\.colorScheme) private var appearance
    @Environment(\.codexCurrencyContext) private var currency
    @State private var period = 7
    private var accent: Color { provider == .claude ? ClaudeUsagePanelView.accent(for: appearance) : .teal }
    private var section: CodexPanelCustomizationSection { official ? .officialInsights : .localInsights }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if official {
                if provider == .cursor { cursorOfficial }
                else { claudeOfficialUnavailable }
            } else {
                if provider == .claude { claudeLocal }
                else { cursorLocal }
            }
        }
    }

    @ViewBuilder private var claudeLocal: some View {
        HStack {
            Label(CodexLocalization.text("本机日志", "Local logs"), systemImage: "internaldrive").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $period) {
                Text(CodexLocalization.text("今天", "Today")).tag(1)
                Text(CodexLocalization.text("7 天", "7 days")).tag(7)
                Text(CodexLocalization.text("30 天", "30 days")).tag(30)
            }.labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 165)
        }
        if let error = monitor.claudeLocalUsageError { notice(error) }
        if let source = monitor.claudeLocalUsage {
            let snapshot = source.period(period)
            if visible(.localSummary) {
                metrics([
                    (CodexLocalization.text("总 Token", "Total tokens"), number(snapshot.tokens)),
                    (CodexLocalization.text("API 等价估算", "API equivalent"), cost(snapshot.requestCount == 0 ? 0 : snapshot.cost, partial: !snapshot.coverage.isComplete)),
                    (CodexLocalization.text("请求数", "Requests"), String(snapshot.requestCount)),
                    (CodexLocalization.text("活跃日", "Active days"), "\(snapshot.daily.filter { $0.requests > 0 }.count) / \(period)"),
                    (CodexLocalization.text("单日峰值", "Peak daily tokens"), number(snapshot.daily.map(\.tokens).max() ?? 0)),
                    (CodexLocalization.text("费用覆盖", "Cost coverage"), snapshot.coverage.tokenPercent.map { "\(Int($0.rounded()))%" } ?? "—")])
                trend(snapshot.daily.map { ProviderUsageBar(id: $0.id, tokens: $0.tokens, inputTokens: $0.input, outputTokens: $0.output,
                    cacheReadTokens: $0.cacheRead, cacheWriteTokens: $0.cacheWrite, requestCount: $0.requests, apiCostUSD: $0.cost, meteredCostUSD: nil) })
            }
            if visible(.localHourlyActivity) { hourlyHeatmap(snapshot.hourly) }
            if visible(.localComposition) { composition(input: snapshot.inputTokens, output: snapshot.outputTokens, read: snapshot.cacheReadTokens, write: snapshot.cacheWriteTokens) }
            if visible(.localTopModels) {
                modelList(snapshot.models.map { InsightModel(id: $0.id, tokens: $0.tokens, cost: $0.cost, partial: $0.pricedTokens < $0.tokens) })
            }
            if visible(.localPricingSource) {
                sourceFooter(CodexLocalization.text("本机 Claude Code 日志 · 按本地时区统计。费用为 API 等价估算，并非订阅账单；可能包含切换账户前的记录。", "Local Claude Code logs, in local time. API-equivalent estimates are not subscription bills and may include records from earlier accounts."), date: snapshot.fetchedAt, refresh: monitor.refreshClaudeLocal)
            }
            if snapshot.unreadableFiles > 0 || snapshot.skippedRecords > 0 {
                notice(CodexLocalization.text("部分统计：\(snapshot.unreadableFiles) 个文件不可读，\(snapshot.skippedRecords) 条记录未计入。", "Partial statistics: \(snapshot.unreadableFiles) unreadable files; \(snapshot.skippedRecords) excluded records."))
            }
        } else { loadingOrEmpty(monitor.isRefreshingClaudeLocal) }
    }

    @ViewBuilder private var cursorOfficial: some View {
        if let snapshot = monitor.cursorUsage {
            let failure = monitor.cursorUsageError ?? snapshot.activityError
            if let failure { notice(CodexLocalization.text("官方活动获取失败：", "Official activity fetch failed: ") + failure) }
            if snapshot.activityIsPartial == true { notice(CodexLocalization.text("已达到单次读取上限，当前展示部分活动。", "The fetch limit was reached; showing partial activity.")) }
            if snapshot.activityError == nil {
                let days = cursorDays(snapshot)
                if visible(.officialSummary) {
                    metrics([
                        (CodexLocalization.text("近 30 天 Token", "30-day tokens"), number(snapshot.last30DaysTokens)),
                        (CodexLocalization.text("API 等价金额", "API-equivalent amount"), cost(snapshot.last30DaysAPIEquivalentCostUSD, partial: !snapshot.costCoverage.isComplete)),
                        (CodexLocalization.text("含 Token 的请求", "Requests with tokens"), String(snapshot.daily.reduce(0) { $0 + $1.requestCount })),
                        (CodexLocalization.text("活跃日", "Active days"), "\(snapshot.daily.filter { $0.requestCount > 0 }.count) / 30"),
                        (CodexLocalization.text("官方计费金额", "Reported charges"), cost(snapshot.last30DaysMeteredCostUSD)),
                        (CodexLocalization.text("单日峰值", "Peak daily tokens"), number(snapshot.daily.map(\.totalTokens).max() ?? 0))])
                }
                if visible(.officialHeatmap) { dailyHeatmap(days) }
                if visible(.officialTrend) {
                    trend(days)
                    composition(input: snapshot.daily.reduce(0) { $0 + $1.inputTokens }, output: snapshot.daily.reduce(0) { $0 + $1.outputTokens },
                        read: snapshot.daily.reduce(0) { $0 + $1.cacheReadTokens }, write: snapshot.daily.reduce(0) { $0 + $1.cacheWriteTokens })
                    modelList(snapshot.topModels.map { InsightModel(id: $0.model, tokens: $0.tokens, cost: $0.apiEquivalentCostUSD, partial: true) })
                }
            }
            if visible(.officialSource) {
                sourceFooter(CodexLocalization.text("Cursor 官方用量事件 · 近 30 天，按本地时区归日；图表统计返回 Token 的请求，不代表账户累计或团队全部活动。计费金额来自事件明细，不等于整张订阅账单。", "Cursor official usage events over 30 days, grouped in local time. Charts cover requests with token data, not lifetime or whole-team activity. Event charges are not the full subscription bill."), date: snapshot.fetchedAt, refresh: monitor.refreshCursor)
                Button(CodexLocalization.text("打开 Cursor 用量仪表盘", "Open Cursor usage dashboard")) { NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard/usage")!) }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
            }
        } else if let error = monitor.cursorUsageError { notice(error) }
        else { loadingOrEmpty(monitor.isRefreshingCursor) }
    }

    private var claudeOfficialUnavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(CodexLocalization.text("当前登录不提供官方活动历史", "Official activity history is unavailable for this sign-in"), systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            if let account = monitor.claudeUsage {
                Text([account.accountEmail, account.plan?.capitalized].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(CodexLocalization.text("Claude 的个人 Pro / Max 计划目前不开放官方用量分析。组织分析需要管理员权限；当前组件只读取现有订阅登录。你可以在本地洞察中查看 Token、费用估算、趋势和模型分布。", "Claude does not offer official usage analytics for individual Pro / Max plans. Organization analytics require admin access; this widget reads the existing subscription sign-in. Local insights provide tokens, estimates, trends and models."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(CodexLocalization.text("查看 Claude 本地洞察", "View Claude local insights"), action: showOtherSource)
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            Link(CodexLocalization.text("官方数据可用范围说明", "Official analytics availability"), destination: URL(string: "https://support.claude.com/en/articles/12157520-claude-code-usage-analytics")!)
                .font(.system(size: 9))
        }.padding(12).background(CodexGlassCard(cornerRadius: 11))
    }

    @ViewBuilder private var cursorLocal: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(CodexLocalization.text("本地活动与上下文", "Local activity & context"), systemImage: "internaldrive")
                .font(.system(size: 12, weight: .bold))
            Text(CodexLocalization.text("Cursor 本地对话索引没有完整的 Token 与费用明细；此处展示保存的会话和上下文。Token、模型用量及计费请查看官方活动。", "The Cursor local conversation index does not provide complete token or cost details. Saved conversations and context appear here; use Official Activity for tokens, model usage and charges."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(CodexLocalization.text("查看 Cursor 官方活动", "View Cursor official activity"), action: showOtherSource)
                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
        }.padding(12).background(CodexGlassCard(cornerRadius: 11))
        if let snapshot = monitor.providerWork[.cursor] {
            let samples = snapshot.conversations.filter { $0.contextPercent != nil }
            if visible(.localSummary) {
                metrics([(CodexLocalization.text("本地对话", "Local conversations"), String(snapshot.conversations.count)),
                    (CodexLocalization.text("项目", "Projects"), String(snapshot.projectPaths.count)),
                    (CodexLocalization.text("上下文采样", "Context samples"), String(samples.count)),
                    (CodexLocalization.text("近 24 小时更新", "Updated in 24h"), String(snapshot.conversations.filter { Date().timeIntervalSince($0.modifiedAt) < 86400 }.count))])
            }
            if visible(.localComposition) {
                VStack(alignment: .leading, spacing: 10) {
                    heading(CodexLocalization.text("最近保存的上下文占用", "Last saved context usage"), "brain.head.profile")
                    if samples.isEmpty { Text(CodexLocalization.text("暂无上下文采样", "No context samples")).font(.system(size: 10)).foregroundStyle(.secondary) }
                    ForEach(samples.prefix(10)) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.title).lineLimit(1)
                                Spacer()
                                Text("\(Int((record.contextPercent ?? 0).rounded()))%").monospacedDigit()
                            }.font(.system(size: 10, weight: .medium))
                            ProgressView(value: record.contextPercent ?? 0, total: 100).tint(accent)
                        }
                    }
                }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
            }
            if snapshot.unavailableSources > 0 { notice(CodexLocalization.text("部分本地来源暂时不可读", "Some local sources are currently unreadable")) }
            if visible(.localPricingSource) {
                sourceFooter(CodexLocalization.text("本机 Cursor 索引 · 最多 500 条；上下文为最近保存值，不表示实时运行状态。当前不从本地索引估算 Token 或费用。", "Local Cursor index · up to 500 entries. Context values are last saved samples, not live running state. Tokens and costs are not estimated from this index."), date: snapshot.fetchedAt, refresh: monitor.refreshProviderWork)
            }
        } else { loadingOrEmpty(monitor.isRefreshingProviderWork) }
    }

    private func visible(_ card: CodexPanelCardID) -> Bool { configuration.isVisible(card, in: section) }
    private func number(_ value: Int) -> String { tokenFormat.format(value) }
    private func cost(_ value: Double?, partial: Bool = false) -> String {
        value.map { (partial ? "~" : "") + currency.formatUSD($0) } ?? "—"
    }
    private func heading(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11.5, weight: .bold)).foregroundStyle(.secondary)
    }
    private func metrics(_ values: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(item.1).font(CodexTypography.tokenNumber(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 10))
            }
        }
    }
    private func trend(_ days: [ProviderUsageBar]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(CodexLocalization.text("每日用量趋势", "Daily usage trend"), "chart.bar.fill")
            CodexProviderUsageBars(bars: days, accent: accent, testingID: provider.rawValue + "-insights")
            HStack { Text(days.first?.id ?? ""); Spacer(); Text(days.last?.id ?? "") }.font(.system(size: 8)).foregroundStyle(.tertiary)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private func composition(input: Int, output: Int, read: Int, write: Int) -> some View {
        let values = [(CodexLocalization.text("输入", "Input"), input), (CodexLocalization.text("输出", "Output"), output),
            (CodexLocalization.text("缓存读取", "Cache read"), read), (CodexLocalization.text("缓存写入", "Cache write"), write)]
        let total = max(1, input + output + read + write)
        return VStack(alignment: .leading, spacing: 9) {
            heading(CodexLocalization.text("Token 构成", "Token composition"), "chart.pie")
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                HStack { Text(value.0); Spacer(); Text(number(value.1)); Text(String(format: "%.1f%%", Double(value.1) / Double(total) * 100)).frame(width: 43, alignment: .trailing) }
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private struct InsightModel: Identifiable { let id: String; let tokens: Int; let cost: Double?; let partial: Bool }
    private func modelList(_ models: [InsightModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(CodexLocalization.text("常用模型", "Top models"), "cpu")
            if models.isEmpty { Text(CodexLocalization.text("当前周期暂无模型用量", "No model usage in this period")).font(.system(size: 10)).foregroundStyle(.secondary) }
            ForEach(models.prefix(8)) { model in
                HStack {
                    Text(model.id).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(number(model.tokens)).font(CodexTypography.tokenNumber(size: 10, weight: .semibold))
                        Text(cost(model.cost, partial: model.partial)).font(CodexTypography.tokenNumber(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private func dailyHeatmap(_ days: [ProviderUsageBar]) -> some View {
        let peak = max(1, days.map(\.tokens).max() ?? 0)
        return VStack(alignment: .leading, spacing: 9) {
            heading(CodexLocalization.text("近 30 天活跃度", "30-day activity"), "calendar")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3).fill(accent.opacity(day.tokens == 0 ? 0.07 : 0.2 + 0.8 * Double(day.tokens) / Double(peak)))
                        .frame(height: 14).help(day.id + " · " + number(day.tokens) + " Token")
                }
            }
            Text(CodexLocalization.text("每格一天 · 悬停查看 Token", "One day per cell · hover for tokens")).font(.system(size: 8)).foregroundStyle(.tertiary)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private func hourlyHeatmap(_ hours: [ClaudeUsageHour]) -> some View {
        let grouped = Dictionary(grouping: hours) { $0.weekday * 24 + $0.hour }.mapValues { $0.reduce(0) { $0 + $1.tokens } }
        let peak = max(1, grouped.values.max() ?? 0)
        let weekdays = CodexLocalization.isChinese ? ["一", "二", "三", "四", "五", "六", "日"] : ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: 8) {
            heading(CodexLocalization.text("小时活跃度", "Hourly activity"), "clock")
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 3) {
                        Text(weekdays[day]).font(.system(size: 8)).foregroundStyle(.tertiary).frame(width: 10)
                        ForEach(0..<24, id: \.self) { hour in
                            let tokens = grouped[day * 24 + hour] ?? 0
                            RoundedRectangle(cornerRadius: 1).fill(accent.opacity(tokens == 0 ? 0.07 : 0.2 + 0.8 * Double(tokens) / Double(peak)))
                                .frame(maxWidth: .infinity).frame(height: 8)
                                .help("\(weekdays[day]) · \(hour):00 · \(number(tokens)) Token")
                        }
                    }
                }
            }
            HStack { Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("23:00") }.font(.system(size: 8)).foregroundStyle(.tertiary)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private func sourceFooter(_ text: String, date: Date, refresh: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CodexLocalization.text("更新于 \(date.formatted(date: .omitted, time: .shortened))", "Updated \(date.formatted(date: .omitted, time: .shortened))"))
                Spacer()
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help(CodexLocalization.text("刷新数据", "Refresh data"))
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true).padding(11).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }
    private func loadingOrEmpty(_ loading: Bool) -> some View {
        HStack {
            if loading { ProgressView().controlSize(.small) }
            Text(loading ? CodexLocalization.text("正在读取…", "Loading…") : CodexLocalization.text("暂无可读取的数据", "No readable data"))
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(16)
    }
    private func cursorDays(_ snapshot: CursorUsageSnapshot) -> [ProviderUsageBar] {
        let calendar = Calendar.current
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let indexed = Dictionary(uniqueKeysWithValues: snapshot.daily.map { ($0.date, $0) })
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 29, to: snapshot.fetchedAt) else { return nil }
            let key = formatter.string(from: date); let day = indexed[key]
            return ProviderUsageBar(id: key, tokens: day?.totalTokens ?? 0, inputTokens: day?.inputTokens ?? 0, outputTokens: day?.outputTokens ?? 0,
                cacheReadTokens: day?.cacheReadTokens ?? 0, cacheWriteTokens: day?.cacheWriteTokens ?? 0, requestCount: day?.requestCount ?? 0,
                apiCostUSD: day?.apiEquivalentCostUSD, meteredCostUSD: day?.meteredCostUSD)
        }
    }
}
