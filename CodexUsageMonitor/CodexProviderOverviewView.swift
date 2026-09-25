import SwiftUI

struct CodexProviderOverviewView: View {
    let codexUsage: CodexUsageSnapshot?
    let codexRecentUsage: CodexRecentUsageSnapshot?
    let codexError: String?
    let cursorUsage: CursorUsageSnapshot?
    let cursorError: String?
    var showsCursor: Bool = true
    var claudeUsage: ClaudeUsageSnapshot? = nil
    var claudeError: String? = nil
    var showsClaude = false
    var claudeLocalUsage: ClaudeLocalUsageSnapshot? = nil
    var claudeLocalError: String? = nil
    var isRefreshingClaudeLocal = false
    var onSelectClaude: () -> Void = {}
    var columnWidth: CGFloat? = nil
    let codexAccent: Color
    let cursorAccent: Color
    let onSelectCodex: () -> Void
    let onSelectCursor: () -> Void

    @Environment(\.colorScheme) private var appearance
    @Environment(\.codexCurrencyContext) private var currencyContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            combinedUsageCard
            if let columnWidth {
                HStack(alignment: .top, spacing: 12) {
                    codexCard.frame(width: columnWidth)
                    if showsClaude { claudeCard.frame(width: columnWidth) }
                    if showsCursor { cursorCard.frame(width: columnWidth) }
                }
            } else {
                codexCard
                if showsClaude { claudeCard }
                if showsCursor { cursorCard }
            }
        }
    }

    private var combinedUsageCard: some View {
        let costs = [
            codexRecentUsage?.last30DaysEstimatedCostUSD,
            cursorUsage?.last30DaysAPIEquivalentCostUSD,
            showsClaude ? claudeLocalUsage?.cost : nil,
        ].compactMap { $0 }
        let totalCost = costs.isEmpty ? nil : costs.reduce(0, +)
        let totalTokens = (codexRecentUsage?.last30DaysTokens ?? 0)
            + (cursorUsage?.last30DaysTokens ?? 0)
            + (showsClaude ? claudeLocalUsage?.tokens ?? 0 : 0)
        let coverage = CodexCostCoverage.combining([
            codexRecentUsage?.last30DaysSummary.costCoverage ?? .empty,
            cursorUsage?.costCoverage ?? .empty,
            showsClaude ? claudeLocalUsage?.coverage ?? .empty : .empty,
        ])

        return Group {
            if columnWidth != nil {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(CodexLocalization.text("用量与支出 · 30 天", "Usage & spend · 30 days"), systemImage: "square.grid.2x2.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(formatCost(totalCost, coverage: coverage))
                            .font(CodexTypography.tokenNumber(size: 21, weight: .bold))
                    }
                    Divider().frame(height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(formatTokens(totalTokens)) Token")
                            .font(CodexTypography.tokenNumber(size: 13, weight: .semibold))
                        Text(CodexLocalization.text("\(costs.count) / \(1 + (showsCursor ? 1 : 0) + (showsClaude ? 1 : 0)) 个服务有费用数据", "\(costs.count) / \(1 + (showsCursor ? 1 : 0) + (showsClaude ? 1 : 0)) providers with cost data"))
                            .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CodexLocalization.text("费用覆盖 ", "Cost coverage ") + (coverage.tokenPercent.map { "\(Int($0.rounded()))%" } ?? "—"))
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(codexAccent)
                        Text(CodexLocalization.text("API 等价估算，非订阅账单", "API-equivalent estimate, not a bill"))
                            .font(.system(size: 8.5)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(codexAccent)
                        Text(CodexLocalization.text("用量与支出 · 30 天", "Usage & spend · 30 days"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CodexLocalization.text("聚合", "Combined"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(codexAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(codexAccent.opacity(0.10), in: Capsule())
                    }

                    Text(formatCost(totalCost, coverage: coverage))
                        .font(CodexTypography.tokenNumber(size: 21, weight: .bold))

                    Text(CodexLocalization.text(
                        "\(costs.count) / \(1 + (showsCursor ? 1 : 0) + (showsClaude ? 1 : 0)) 个服务有费用数据 · \(formatTokens(totalTokens)) Token",
                        "\(costs.count) / \(1 + (showsCursor ? 1 : 0) + (showsClaude ? 1 : 0)) services have spend data · \(formatTokens(totalTokens)) tokens"
                    ))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text((["Codex"] + (showsClaude ? ["Claude"] : []) + (showsCursor ? ["Cursor"] : [])).joined(separator: " + "))
                        .font(.system(size: 9)).foregroundStyle(.secondary)

                    HStack(spacing: 5) {
                        Text(CodexLocalization.text("费用覆盖", "Cost coverage"))
                        Text(coverage.tokenPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                            .font(CodexTypography.tokenNumber(size: 8.5, weight: .semibold))
                        Text("·")
                        Text(CodexLocalization.text("API 等价估算，非订阅账单", "API-equivalent estimate, not a bill"))
                    }
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(
            ZStack {
                CodexGlassCard(cornerRadius: 13)
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        colors: [codexAccent.opacity(0.10), cursorAccent.opacity(0.075)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        )
    }

    private var codexCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerHeader(
                brand: .codex,
                title: "Codex",
                account: codexUsage?.accountEmail,
                detail: codexUsage?.displayPlan,
                fetchedAt: codexUsage?.fetchedAt,
                accent: codexAccent,
                action: onSelectCodex
            )

            if let error = codexError, codexUsage == nil {
                providerError(error, accent: codexAccent)
            } else if let usage = codexUsage {
                if let error = codexError {
                    providerStaleWarning(error)
                }
                if let weekly = usage.weeklyWindow ?? usage.monthlyWindow {
                    quotaRow(weekly, accent: codexAccent)
                }
                if let resets = usage.resetCreditsAvailable {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise.circle")
                        Text(CodexLocalization.text(
                            "限额重置额度：\(resets) 次可用",
                            "Quota resets: \(resets) available"
                        ))
                    }
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                providerUsageMetrics(
                    todayCost: codexRecentUsage?.todayEstimatedCostUSD,
                    todayTokens: codexRecentUsage?.todayTokens ?? 0,
                    periodCost: codexRecentUsage?.last30DaysEstimatedCostUSD,
                    periodTokens: codexRecentUsage?.last30DaysTokens ?? 0,
                    coverage: codexRecentUsage?.last30DaysSummary.costCoverage ?? .empty
                )
                if let recent = codexRecentUsage {
                    CodexProviderUsageBars(
                        bars: recent.daily.suffix(12).map {
                            ProviderUsageBar(
                                id: $0.dayKey,
                                tokens: $0.totalTokens,
                                inputTokens: $0.inputTokens,
                                outputTokens: $0.outputTokens,
                                cacheReadTokens: $0.cachedInputTokens,
                                cacheWriteTokens: $0.cacheWriteInputTokens,
                                requestCount: $0.requestCount,
                                apiCostUSD: $0.estimatedCostUSD,
                                meteredCostUSD: nil
                            )
                        },
                        accent: codexAccent,
                        testingID: "codex"
                    )
                    providerModelRow(recent.mostUsedModel, accent: codexAccent)
                }
            } else {
                providerLoading
            }
        }
        .padding(12)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private var cursorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerHeader(
                brand: .cursor,
                title: "Cursor",
                account: cursorUsage?.accountEmail,
                detail: cursorUsage?.displayPlan,
                fetchedAt: cursorUsage?.fetchedAt,
                accent: cursorAccent,
                action: onSelectCursor
            )

            if let error = cursorError, cursorUsage == nil {
                providerError(error, accent: cursorAccent)
            } else if let usage = cursorUsage {
                if let error = cursorError {
                    providerStaleWarning(error)
                }
                ForEach(Array(usage.quotaWindows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider().opacity(0.24) }
                    quotaRow(window, accent: cursorAccent)
                }
                if usage.hasOnDemandUsage {
                    Divider().opacity(0.24)
                    CursorOnDemandUsageView(snapshot: usage, accent: cursorAccent, compact: true)
                    Divider().opacity(0.24)
                }
                providerUsageMetrics(
                    todayCost: usage.todayAPIEquivalentCostUSD,
                    todayTokens: usage.todayTokens,
                    periodCost: usage.last30DaysAPIEquivalentCostUSD,
                    periodTokens: usage.last30DaysTokens,
                    coverage: usage.costCoverage
                )
                CodexProviderUsageBars(
                    bars: usage.daily.suffix(12).map {
                        ProviderUsageBar(
                            id: $0.date,
                            tokens: $0.totalTokens,
                            inputTokens: $0.inputTokens,
                            outputTokens: $0.outputTokens,
                            cacheReadTokens: $0.cacheReadTokens,
                            cacheWriteTokens: $0.cacheWriteTokens,
                            requestCount: $0.requestCount,
                            apiCostUSD: $0.apiEquivalentCostUSD,
                            meteredCostUSD: $0.meteredCostUSD
                        )
                    },
                    accent: cursorAccent,
                    testingID: "cursor"
                )
                providerModelRow(usage.topModels.first?.model, accent: cursorAccent)
            } else {
                providerLoading
            }
        }
        .padding(12)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func providerHeader(
        brand: CodexProviderBrand,
        title: String,
        account: String?,
        detail: String?,
        fetchedAt: Date?,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                CodexProviderIcon(brand: brand, size: 18, color: accent)
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .bold))
                    Text(fetchedAt.map {
                        CodexLocalization.text("\($0.codexRelativeText)更新", "Updated \($0.codexRelativeText)")
                    } ?? CodexLocalization.text("等待更新", "Waiting for refresh"))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(account ?? CodexLocalization.text("未连接", "Not connected"))
                    Text(detail ?? "—")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quotaRow(_ window: CodexQuotaWindow, accent: Color) -> some View {
        CodexProviderQuotaRow(window: window, accent: accent, compact: true)
    }

    private var claudeCard: some View {
        let accent = ClaudeUsagePanelView.accent(for: appearance)
        return VStack(alignment: .leading, spacing: 10) {
            providerHeader(brand: .claude, title: "Claude", account: claudeUsage?.accountEmail,
                detail: claudeUsage?.plan?.capitalized, fetchedAt: claudeUsage?.fetchedAt,
                accent: accent, action: onSelectClaude)
            if let error = claudeError, claudeUsage == nil {
                providerError(error, accent: accent)
            } else if let usage = claudeUsage {
                if let error = claudeError { providerStaleWarning(error) }
                ForEach(Array(usage.windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider().opacity(0.24) }
                    quotaRow(window, accent: accent)
                }
            } else {
                providerLoading
            }
            ClaudeLocalUsageView(snapshot: claudeLocalUsage, error: claudeLocalError,
                isRefreshing: isRefreshingClaudeLocal, compact: true)
        }
        .padding(12)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func providerUsageMetrics(
        todayCost: Double?,
        todayTokens: Int,
        periodCost: Double?,
        periodTokens: Int,
        coverage: CodexCostCoverage
    ) -> some View {
        HStack(spacing: 8) {
            providerMetric(
                CodexLocalization.text("今日", "Today"),
                value: formatCost(todayCost, coverage: coverage),
                detail: "\(formatTokens(todayTokens)) Token"
            )
            providerMetric(
                CodexLocalization.text("近 30 天", "Last 30 days"),
                value: formatCost(periodCost, coverage: coverage),
                detail: "\(formatTokens(periodTokens)) Token"
            )
        }
    }

    private func providerMetric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(CodexTypography.tokenNumber(size: 11.5, weight: .bold))
                .lineLimit(1)
            Text(detail)
                .font(CodexTypography.tokenNumber(size: 7.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func providerModelRow(_ model: String?, accent: Color) -> some View {
        if let model, !model.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "cpu").foregroundStyle(accent)
                Text(CodexLocalization.text("最常用模型：\(model)", "Top model: \(model)"))
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func providerError(_ message: String, accent: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(accent)
            Text(message)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerStaleWarning(_ message: String) -> some View {
        Text(CodexLocalization.text("刷新失败，当前显示缓存数据：", "Refresh failed; showing cached data: ") + message)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var providerLoading: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini)
            Text(CodexLocalization.text("正在读取数据…", "Loading data…"))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func formatCost(_ value: Double?, coverage: CodexCostCoverage) -> String {
        guard let value else { return "—" }
        let prefix = coverage.totalTokens > 0 && !coverage.isComplete ? "~" : ""
        return prefix + currencyContext.formatUSD(value)
    }

    private func formatTokens(_ value: Int) -> String {
        CodexTokenFormat.automatic.format(value)
    }

}

struct ProviderUsageBar: Identifiable {
    let id: String
    let tokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let requestCount: Int
    let apiCostUSD: Double?
    let meteredCostUSD: Double?
}

struct CodexProviderUsageBars: View {
    let bars: [ProviderUsageBar]
    let accent: Color
    let testingID: String

    @Environment(\.colorScheme) private var appearance
    @Environment(\.codexCurrencyContext) private var currencyContext
    @State private var hoveredID: String?
    @State private var hoveredLocation: CGPoint?
    @State private var tooltipSize = CGSize(width: 156, height: 70)

    init(bars: [ProviderUsageBar], accent: Color, testingID: String) {
        self.bars = bars
        self.accent = accent
        self.testingID = testingID
        #if CODEX_USAGE_TESTING
        let hovered = UserDefaults.standard.string(
            forKey: "codexUsage.testing.providerChartHover.\(testingID)"
        )
        _hoveredID = State(initialValue: hovered)
        _hoveredLocation = State(initialValue: hovered == nil ? nil : CGPoint(x: 232, y: 58))
        #else
        _hoveredID = State(initialValue: nil)
        _hoveredLocation = State(initialValue: nil)
        #endif
    }

    var body: some View {
        if bars.count > 1 {
            let maximum = max(bars.map(\.tokens).max() ?? 0, 1)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(bars) { bar in
                            let hovered = hoveredID == bar.id
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(accent.opacity(hovered ? 1 : (hoveredID == nil ? 0.72 : 0.20)))
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: bar.tokens > 0 ? 2 : 1,
                                    maxHeight: max(2, 58 * CGFloat(bar.tokens) / CGFloat(maximum))
                                )
                                .overlay {
                                    if hovered {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .animation(.easeOut(duration: 0.13), value: hoveredID)

                    if let bar = bars.first(where: { $0.id == hoveredID }),
                       let hoveredLocation
                    {
                        let origin = tooltipOrigin(
                            pointer: hoveredLocation,
                            tooltipSize: tooltipSize,
                            chartSize: proxy.size
                        )
                        usageTooltip(bar)
                            .background {
                                GeometryReader { tooltipProxy in
                                    Color.clear.preference(
                                        key: CodexProviderTooltipSizePreferenceKey.self,
                                        value: tooltipProxy.size
                                    )
                                }
                            }
                            .offset(x: origin.x, y: origin.y)
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        updateHover(location, chartWidth: proxy.size.width)
                    case .ended:
                        hoveredID = nil
                        hoveredLocation = nil
                    }
                }
                .onPreferenceChange(CodexProviderTooltipSizePreferenceKey.self) { size in
                    guard size.width > 0, size.height > 0 else { return }
                    tooltipSize = size
                }
            }
            .frame(height: 68)
        }
    }

    private func usageTooltip(_ bar: ProviderUsageBar) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateTitle(bar.id))
                .font(.system(size: 8.5, weight: .semibold))
            Text("\(tokenText(bar.tokens)) Token")
                .font(CodexTypography.tokenNumber(size: 8, weight: .semibold))
            Text(CodexLocalization.text(
                "输入 \(tokenText(bar.inputTokens)) · 输出 \(tokenText(bar.outputTokens))",
                "Input \(tokenText(bar.inputTokens)) · Output \(tokenText(bar.outputTokens))"
            ))
                .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                .foregroundStyle(.secondary)
            if bar.cacheReadTokens > 0 || bar.cacheWriteTokens > 0 {
                Text(CodexLocalization.text(
                    "Cache 读 \(tokenText(bar.cacheReadTokens)) · 写 \(tokenText(bar.cacheWriteTokens))",
                    "Cache read \(tokenText(bar.cacheReadTokens)) · write \(tokenText(bar.cacheWriteTokens))"
                ))
                    .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(CodexLocalization.text(
                "\(bar.requestCount) 次请求 · API \(costText(bar.apiCostUSD))",
                "\(bar.requestCount) requests · API \(costText(bar.apiCostUSD))"
            ))
                .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                .foregroundStyle(.secondary)
            if let metered = bar.meteredCostUSD {
                Text(CodexLocalization.text(
                    "Cursor 计量 \(currencyContext.formatUSD(metered))",
                    "Cursor metered \(currencyContext.formatUSD(metered))"
                ))
                    .font(CodexTypography.tokenNumber(size: 7.6, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(accent.opacity(0.30), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(appearance == .dark ? 0.30 : 0.16), radius: 6, y: 3)
        .allowsHitTesting(false)
    }

    private func updateHover(_ location: CGPoint, chartWidth: CGFloat) {
        guard !bars.isEmpty, chartWidth > 0 else { return }
        let spacing: CGFloat = 3
        let totalSpacing = spacing * CGFloat(max(0, bars.count - 1))
        let barWidth = max(1, (chartWidth - totalSpacing) / CGFloat(bars.count))
        let index = min(
            bars.count - 1,
            max(0, Int(max(0, location.x) / (barWidth + spacing)))
        )
        hoveredID = bars[index].id
        hoveredLocation = location
    }

    private func tooltipOrigin(
        pointer: CGPoint,
        tooltipSize: CGSize,
        chartSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 2
        let gap: CGFloat = 7
        let width = max(tooltipSize.width, 1)
        let height = max(tooltipSize.height, 1)
        let rightX = pointer.x + gap
        let x = rightX + width <= chartSize.width - margin
            ? rightX
            : max(margin, pointer.x - gap - width)
        let aboveY = pointer.y - gap - height
        let maxY = max(margin, chartSize.height - height - margin)
        let y = aboveY >= margin
            ? min(aboveY, maxY)
            : min(maxY, pointer.y + gap)
        return CGPoint(x: x, y: max(margin, y))
    }

    private func dateTitle(_ dayKey: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func tokenText(_ value: Int) -> String {
        CodexTokenFormat.automatic.format(value)
    }

    private func costText(_ value: Double?) -> String {
        value.map { currencyContext.formatUSD($0) } ?? "—"
    }
}

private struct CodexProviderTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}
