import AppKit
import SwiftUI

struct CursorUsagePanelView: View {
    let snapshot: CursorUsageSnapshot?
    let error: String?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenStatus: () -> Void
    let onOpenCursor: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.codexCurrencyContext) private var currencyContext
    #if CODEX_USAGE_TESTING
    @State private var hoveredDayID: String? = UserDefaults.standard.string(
        forKey: "codexUsage.testing.cursorHoveredDayID"
    )
    @State private var hoveredChartLocation: CGPoint? = UserDefaults.standard.string(
        forKey: "codexUsage.testing.cursorHoveredDayID"
    ) == nil ? nil : CGPoint(x: 250, y: 74)
    #else
    @State private var hoveredDayID: String?
    @State private var hoveredChartLocation: CGPoint?
    #endif
    @State private var chartTooltipSize = CGSize(width: 156, height: 72)

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.68, blue: 0.60)
            : Color(red: 0.00, green: 0.70, blue: 0.61)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                accountCard(snapshot)
                if let error {
                    staleDataWarning(error)
                }
                quotaCard(snapshot)
                usageCard(snapshot)
                if !snapshot.topModels.isEmpty {
                    topModelsCard(snapshot)
                }
                sourceFooter(snapshot)
            } else if let error {
                errorCard(error)
            } else {
                loadingCard
            }
        }
    }

    private func staleDataWarning(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(CodexLocalization.text(
                    "当前显示上次成功更新的数据",
                    "Showing data from the last successful refresh"
                ))
                    .font(.system(size: 9.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 3)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help(CodexLocalization.text("重试 Cursor 刷新", "Retry Cursor refresh"))
        }
        .padding(9)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    private func accountCard(_ snapshot: CursorUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent.opacity(0.14))
                .overlay {
                    CodexProviderIcon(brand: .cursor, size: 18, color: accent)
                }
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.accountEmail ?? CodexLocalization.text("Cursor 账户", "Cursor account"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(CodexLocalization.text(
                    "\(snapshot.displayPlan) · \(snapshot.fetchedAt.codexRelativeText)更新",
                    "\(snapshot.displayPlan) · updated \(snapshot.fetchedAt.codexRelativeText)"
                ))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onOpenDashboard) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help(CodexLocalization.text("打开 Cursor 用量仪表盘", "Open the Cursor usage dashboard"))
        }
        .padding(10)
        .background(CodexGlassCard())
    }

    private func quotaCard(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(CodexLocalization.text("Cursor 额度", "Cursor quotas"), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.displayPlan)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)

            ForEach(Array(snapshot.quotaWindows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    Divider().opacity(colorScheme == .dark ? 0.22 : 0.32)
                        .padding(.vertical, 8)
                }
                quotaRow(window)
            }
            if snapshot.hasOnDemandUsage {
                Divider().opacity(colorScheme == .dark ? 0.22 : 0.32)
                    .padding(.vertical, 10)
                CursorOnDemandUsageView(snapshot: snapshot, accent: accent)
            }
        }
        .padding(11)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func quotaRow(_ window: CodexQuotaWindow) -> some View {
        CodexProviderQuotaRow(window: window, accent: accent)
    }

    private func usageCard(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(CodexLocalization.text("最近 30 天用量", "Last 30 days"), systemImage: "chart.bar.fill")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpenDashboard) {
                    Text("Cursor Dashboard")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(CodexLocalization.text("打开 Cursor 用量仪表盘", "Open the Cursor usage dashboard"))
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                usageMetric(
                    CodexLocalization.text("Cursor 计量", "Cursor metered"),
                    currency(snapshot.last30DaysMeteredCostUSD)
                )
                usageMetric(
                    CodexLocalization.text("API 等价", "API equivalent"),
                    currency(snapshot.last30DaysAPIEquivalentCostUSD)
                )
                usageMetric(
                    CodexLocalization.text("今日 Token", "Today tokens"),
                    compact(snapshot.todayTokens)
                )
                usageMetric(
                    CodexLocalization.text("近 30 天 Token", "30-day tokens"),
                    compact(snapshot.last30DaysTokens)
                )
            }

            usageChart(snapshot)
                .frame(height: 92)

            if let model = snapshot.topModels.first {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .foregroundStyle(accent)
                    Text(CodexLocalization.text("最常用模型：", "Top model: ") + model.model)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Text(CodexLocalization.text(
                "费用来自 Cursor Dashboard：Cursor 计量是实际计划扣减，API 等价按供应商 Token 费率计算。",
                "Costs come from Cursor Dashboard: metered cost is the plan deduction; API equivalent uses vendor token rates."
            ))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func usageMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(CodexTypography.tokenNumber(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025), in: RoundedRectangle(cornerRadius: 8))
    }

    private func usageChart(_ snapshot: CursorUsageSnapshot) -> some View {
        let points = chartPoints(snapshot)
        let maximum = max(points.map(\.value).max() ?? 0, 0.001)
        let hoveredPoint = points.first { $0.id == hoveredDayID }

        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(points) { point in
                        let hovered = hoveredDayID == point.id
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(accent.opacity(hovered ? 1 : (hoveredDayID == nil ? 0.78 : 0.22)))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: point.value > 0 ? 2 : 1,
                                maxHeight: max(2, proxy.size.height * CGFloat(point.value / maximum))
                            )
                            .overlay {
                                if hovered {
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(.easeOut(duration: 0.13), value: hoveredDayID)

                if let hoveredPoint, let hoveredChartLocation {
                    let origin = cursorTooltipOrigin(
                        pointer: hoveredChartLocation,
                        tooltipSize: chartTooltipSize,
                        chartSize: proxy.size
                    )
                    cursorUsageTooltip(hoveredPoint)
                        .background {
                            GeometryReader { tooltipProxy in
                                Color.clear.preference(
                                    key: CursorUsageTooltipSizePreferenceKey.self,
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
                    updateCursorHover(
                        at: location,
                        chartWidth: proxy.size.width,
                        points: points
                    )
                case .ended:
                    hoveredDayID = nil
                    hoveredChartLocation = nil
                }
            }
            .onPreferenceChange(CursorUsageTooltipSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                chartTooltipSize = size
            }
        }
    }

    private func cursorUsageTooltip(_ point: CursorChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cursorTooltipDate(point.date))
                .font(.system(size: 8.5, weight: .semibold))
            Text("\(compact(point.day?.totalTokens ?? 0)) Token")
                .font(CodexTypography.tokenNumber(size: 8, weight: .semibold))
            if let day = point.day {
                Text(CodexLocalization.text(
                    "输入 \(compact(day.inputTokens)) · 输出 \(compact(day.outputTokens))",
                    "Input \(compact(day.inputTokens)) · Output \(compact(day.outputTokens))"
                ))
                    .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                    .foregroundStyle(.secondary)
                if day.cacheReadTokens > 0 || day.cacheWriteTokens > 0 {
                    Text(CodexLocalization.text(
                        "Cache 读 \(compact(day.cacheReadTokens)) · 写 \(compact(day.cacheWriteTokens))",
                        "Cache read \(compact(day.cacheReadTokens)) · write \(compact(day.cacheWriteTokens))"
                    ))
                        .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(CodexLocalization.text(
                    "\(day.requestCount) 次请求 · API \(currency(day.apiEquivalentCostUSD))",
                    "\(day.requestCount) requests · API \(currency(day.apiEquivalentCostUSD))"
                ))
                    .font(CodexTypography.tokenNumber(size: 7.4, weight: .medium))
                    .foregroundStyle(.secondary)
                if let metered = day.meteredCostUSD {
                    Text(CodexLocalization.text(
                        "Cursor 计量 \(currency(metered))",
                        "Cursor metered \(currency(metered))"
                    ))
                        .font(CodexTypography.tokenNumber(size: 7.6, weight: .semibold))
                        .foregroundStyle(accent)
                }
            } else {
                Text(CodexLocalization.text("当天没有本地用量", "No local usage for this day"))
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(accent.opacity(0.30), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 6, y: 3)
        .allowsHitTesting(false)
    }

    private func updateCursorHover(
        at location: CGPoint,
        chartWidth: CGFloat,
        points: [CursorChartPoint]
    ) {
        guard !points.isEmpty, chartWidth > 0 else {
            hoveredDayID = nil
            hoveredChartLocation = nil
            return
        }
        let spacing: CGFloat = 4
        let totalSpacing = spacing * CGFloat(max(0, points.count - 1))
        let barWidth = max(1, (chartWidth - totalSpacing) / CGFloat(points.count))
        let index = min(
            points.count - 1,
            max(0, Int(max(0, location.x) / (barWidth + spacing)))
        )
        hoveredDayID = points[index].id
        hoveredChartLocation = location
    }

    private func cursorTooltipOrigin(
        pointer: CGPoint,
        tooltipSize: CGSize,
        chartSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 2
        let gap: CGFloat = 8
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

    private func cursorTooltipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func topModelsCard(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(CodexLocalization.text("常用模型", "Top models"), systemImage: "cpu")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
            ForEach(Array(snapshot.topModels.prefix(5).enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider()
                        .opacity(colorScheme == .dark ? 0.22 : 0.32)
                        .padding(.leading, 16)
                }
                HStack(spacing: 8) {
                    Circle().fill(accent.opacity(max(0.35, 1 - Double(index) * 0.14))).frame(width: 7, height: 7)
                    Text(model.model)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(compact(model.tokens))
                            .font(CodexTypography.tokenNumber(size: 9.5, weight: .bold))
                        Text(currency(model.apiEquivalentCostUSD))
                            .font(CodexTypography.tokenNumber(size: 7.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(11)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func sourceFooter(_ snapshot: CursorUsageSnapshot) -> some View {
        HStack(spacing: 12) {
            Label(
                CodexLocalization.text(
                    "\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) · Cursor.app 只读",
                    "\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) · Cursor.app read-only"
                ),
                systemImage: "checkmark.circle"
            )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(CodexLocalization.text(
                    "登录信息只读自 Cursor.app，额度与用量来自 cursor.com",
                    "Login is read-only from Cursor.app; quota and usage come from cursor.com"
                ))
            Spacer()
            Button(action: onOpenStatus) {
                Image(systemName: "waveform.path.ecg")
            }
                .buttonStyle(.plain)
                .modifier(CodexFooterActionHover(
                    testingID: "cursor-status",
                    help: CodexLocalization.text("打开 Cursor 官方状态页", "Open official Cursor status page"),
                    accent: accent,
                    restingColor: .secondary,
                    tipAlignment: .top
                ))
            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .modifier(CodexFooterActionHover(
                testingID: "cursor-refresh",
                help: isRefreshing
                    ? CodexLocalization.text("正在刷新 Cursor 数据", "Refreshing Cursor data")
                    : CodexLocalization.text("立即刷新 Cursor 数据", "Refresh Cursor data now"),
                accent: accent,
                restingColor: .secondary,
                tipAlignment: .topTrailing
            ))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            CodexProviderIcon(brand: .cursor, size: 30, color: accent)
            Text(CodexLocalization.text("无法读取 Cursor 数据", "Unable to load Cursor data"))
                .font(.system(size: 13, weight: .bold))
            Text(message)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(CodexLocalization.text("打开 Cursor", "Open Cursor"), action: onOpenCursor)
                Button(CodexLocalization.text("重试", "Retry"), action: onRefresh)
                    .disabled(isRefreshing)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(CodexLocalization.text("正在读取 Cursor 数据…", "Loading Cursor data…"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(CodexGlassCard(cornerRadius: 13))
    }

    private func chartPoints(_ snapshot: CursorUsageSnapshot) -> [CursorChartPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: snapshot.fetchedAt)
        let byDate = Dictionary(uniqueKeysWithValues: snapshot.daily.map { ($0.date, $0) })
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (-29...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let key = formatter.string(from: date)
            let day = byDate[key]
            let value = Double(day?.totalTokens ?? 0)
            return CursorChartPoint(id: key, date: date, value: value, day: day)
        }
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return currencyContext.formatUSD(value)
    }

    private func compact(_ value: Int) -> String {
        CodexTokenFormat.automatic.format(value)
    }

    private struct CursorChartPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let day: CursorUsageDay?
    }
}

private struct CursorUsageTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}
