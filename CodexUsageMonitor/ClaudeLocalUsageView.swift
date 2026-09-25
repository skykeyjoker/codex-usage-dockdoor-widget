import SwiftUI

struct ClaudeLocalUsageView: View {
    let snapshot: ClaudeLocalUsageSnapshot?
    let error: String?
    let isRefreshing: Bool
    var compact = false
    @Environment(\.colorScheme) private var appearance
    @Environment(\.codexCurrencyContext) private var currency
    private var accent: Color { ClaudeUsagePanelView.accent(for: appearance) }

    var body: some View {
        if compact {
            content
        } else {
            VStack(alignment: .leading, spacing: 12) {
                content.padding(11).background(CodexGlassCard(cornerRadius: 13))
                if let snapshot, snapshot.hasData {
                    breakdown(snapshot)
                    modelCard(snapshot)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                Label(CodexLocalization.text("最近 30 天用量", "Last 30 days"), systemImage: "chart.bar.fill")
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9)).foregroundStyle(.orange)
            }
            if let snapshot, snapshot.hasData {
                HStack(spacing: 8) {
                    metric(CodexLocalization.text("今日", "Today"),
                        cost: snapshot.today.flatMap { $0.requests == 0 ? 0 : $0.cost }, tokens: snapshot.today?.tokens ?? 0,
                        coverage: snapshot.today?.coverage ?? .empty)
                    metric(CodexLocalization.text("近 30 天", "Last 30 days"), cost: snapshot.cost,
                        tokens: snapshot.tokens, coverage: snapshot.coverage)
                }
                CodexProviderUsageBars(bars: (compact ? Array(snapshot.daily.suffix(12)) : snapshot.daily).map {
                    ProviderUsageBar(id: $0.id, tokens: $0.tokens, inputTokens: $0.input, outputTokens: $0.output,
                        cacheReadTokens: $0.cacheRead, cacheWriteTokens: $0.cacheWrite, requestCount: $0.requests,
                        apiCostUSD: $0.cost, meteredCostUSD: nil)
                }, accent: accent, testingID: compact ? "claude" : "claude-detail")
                if let model = snapshot.models.first {
                    Label(CodexLocalization.text("最常用模型：", "Top model: ") + model.id, systemImage: "cpu")
                        .font(.system(size: compact ? 8.5 : 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(CodexLocalization.text("本机日志 · API 等价估算，非订阅账单", "Local logs · API-equivalent estimate, not a bill"))
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
            } else if isRefreshing && snapshot == nil {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text(CodexLocalization.text("正在读取本地用量…", "Loading local usage…"))
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                Label(CodexLocalization.text("暂无可读取的本地用量记录", "No readable local usage history"), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(CodexLocalization.text("在本机使用 Claude Code 产生会话记录后，会显示近期消耗、每日用量和常用模型。网页聊天和其他设备的历史不在本地统计范围内。", "Recent usage, daily history and top models appear after Claude Code writes local session logs. Web chats and other devices are outside this local history."))
                    .font(.system(size: 8.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot, snapshot.unreadableFiles > 0 || snapshot.skippedRecords > 0 {
                Text(CodexLocalization.text("部分记录未计入：\(snapshot.unreadableFiles) 个文件不可读，\(snapshot.skippedRecords) 条记录不完整或不可解析。", "Partial history: \(snapshot.unreadableFiles) unreadable files, \(snapshot.skippedRecords) incomplete or unsupported records."))
                    .font(.system(size: 8)).foregroundStyle(.orange)
            }
        }
    }

    private func metric(_ title: String, cost: Double?, tokens: Int, coverage: CodexCostCoverage) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            Text(costText(cost, partial: !coverage.isComplete))
                .font(CodexTypography.tokenNumber(size: 11.5, weight: .bold)).lineLimit(1)
            Text(CodexTokenFormat.automatic.format(tokens) + " Token")
                .font(CodexTypography.tokenNumber(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func breakdown(_ snapshot: ClaudeLocalUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(CodexLocalization.text("Token 构成与覆盖范围", "Token mix & coverage"), systemImage: "chart.pie")
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.secondary)
            detail(CodexLocalization.text("输入 / 输出", "Input / output"), "\(number(snapshot.inputTokens)) / \(number(snapshot.outputTokens))")
            detail(CodexLocalization.text("缓存读取 / 写入", "Cache read / write"), "\(number(snapshot.cacheReadTokens)) / \(number(snapshot.cacheWriteTokens))")
            detail(CodexLocalization.text("请求 / 活跃天数", "Requests / active days"), "\(snapshot.requestCount) / \(snapshot.daily.filter { $0.requests > 0 }.count)")
            detail(CodexLocalization.text("费用覆盖", "Cost coverage"), snapshot.coverage.tokenPercent.map { "\(Int($0.rounded()))%" } ?? "—")
            Text(CodexLocalization.text("基于本机近 30 天会话；切换账户前的本地记录也可能包含在内。费用按 models.dev 可用费率估算，缺少费率时保留 Token 数而不猜测费用。", "Based on this machine’s last 30 days, which may include earlier accounts. Costs use available models.dev rates; missing prices retain token counts without inventing cost."))
                .font(.system(size: 8.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(11).background(CodexGlassCard(cornerRadius: 13))
    }

    private func modelCard(_ snapshot: ClaudeLocalUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(CodexLocalization.text("常用模型", "Top models"), systemImage: "cpu")
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.secondary)
            ForEach(snapshot.models.prefix(8)) { model in
                HStack {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(model.id).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(number(model.tokens)).font(CodexTypography.tokenNumber(size: 9.5, weight: .bold))
                        Text(costText(model.cost, partial: model.pricedTokens < model.tokens))
                            .font(CodexTypography.tokenNumber(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(11).background(CodexGlassCard(cornerRadius: 13))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 9)).foregroundStyle(.secondary)
    }
    private func number(_ value: Int) -> String { CodexTokenFormat.automatic.format(value) }
    private func costText(_ value: Double?, partial: Bool) -> String {
        guard let value else { return "—" }
        return (partial ? "~" : "") + currency.formatUSD(value)
    }
}
