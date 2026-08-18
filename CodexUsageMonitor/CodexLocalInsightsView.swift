import SwiftUI

/// Detailed, local-only usage analytics derived from Codex session logs.
///
/// The view owns its card styling so it can be embedded without depending on
/// panel-private implementation details.
struct CodexLocalInsightsView: View {
    private static let hourlyCellHeight: CGFloat = 8
    private static let hourlyRowSpacing: CGFloat = 3
    private static let hourlySundayHitPadding: CGFloat = 3
    private static var hourlyGridHeight: CGFloat {
        hourlyCellHeight * 7 + hourlyRowSpacing * 6 + hourlySundayHitPadding
    }

    let snapshot: CodexRecentUsageSnapshot
    let primary: Color
    let secondary: Color
    let tokenFormat: CodexTokenFormat
    let cardOrder: [CodexPanelCardID]
    let showsPeriodHeader: Bool
    let hourlyActivityRange: CodexHourlyActivityRange

    @Environment(\.colorScheme) private var colorScheme
    @State private var period: Period = .sevenDays
    @State private var hoveredMetric: String?
    @State private var hoveredModel: String?
    @State private var hoveredHourID: String?
    @State private var hoveredHourLocation: CGPoint?
    @State private var hourlyTooltipSize = CGSize(width: 142, height: 48)

    init(
        snapshot: CodexRecentUsageSnapshot,
        primary: Color,
        secondary: Color,
        tokenFormat: CodexTokenFormat,
        cardOrder: [CodexPanelCardID] = CodexPanelCustomizationSection.localInsights.defaultCards,
        showsPeriodHeader: Bool = true,
        hourlyActivityRange: CodexHourlyActivityRange = .currentWeek
    ) {
        self.snapshot = snapshot
        self.primary = primary
        self.secondary = secondary
        self.tokenFormat = tokenFormat
        self.cardOrder = cardOrder
        self.showsPeriodHeader = showsPeriodHeader
        self.hourlyActivityRange = hourlyActivityRange
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsPeriodHeader {
                periodHeader
            }
            ForEach(cardOrder) { card in
                localCard(card)
            }
        }
    }

    @ViewBuilder
    private func localCard(_ card: CodexPanelCardID) -> some View {
        switch card {
        case .localSummary:
            summaryCard
        case .localHourlyActivity:
            hourlyActivityCard
        case .localComposition:
            tokenCompositionCard
        case .localTopModels:
            topModelsCard
        case .localPricingSource:
            pricingFooter
        default:
            EmptyView()
        }
    }

    private var periodHeader: some View {
        HStack(spacing: 10) {
            Label(
                CodexLocalization.text("本机用量洞察", "Local usage insights"),
                systemImage: "internaldrive"
            )
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Picker("", selection: $period) {
                ForEach(Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 180)
            .help(
                CodexLocalization.text(
                    "切换本机日志统计周期",
                    "Change the local log aggregation period"
                )
            )
        }
        .animation(.easeOut(duration: 0.16), value: period)
    }

    private var summaryCard: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            summaryMetric(
                id: "tokens",
                icon: "sum",
                title: CodexLocalization.text("总 Token", "Total tokens"),
                value: compactNumber(summary.totalTokens),
                help: CodexLocalization.text(
                    "当前周期的输入与输出 Token 总量",
                    "Total input and output tokens in this period"
                )
            )
            summaryMetric(
                id: "cost",
                icon: "dollarsign.circle",
                title: CodexLocalization.text("等价费用", "API equivalent"),
                value: estimatedCostText(summary.estimatedCostUSD, coverage: summary.costCoverage),
                help: CodexLocalization.text(
                    "依据 API 价格目录计算的等价费用，不是订阅账单",
                    "API-equivalent estimate from the pricing catalog, not a subscription bill"
                )
            )
            summaryMetric(
                id: "requests",
                icon: "arrow.up.arrow.down",
                title: CodexLocalization.text("请求", "Requests"),
                value: compactCount(summary.requestCount),
                help: CodexLocalization.text(
                    "从本机会话日志识别到的模型请求数",
                    "Model requests identified in local session logs"
                )
            )
            summaryMetric(
                id: "activeDays",
                icon: "calendar.badge.checkmark",
                title: CodexLocalization.text("活跃日", "Active days"),
                value: "\(summary.activeDays) / \(max(summary.dayCount, periodDayCount))",
                help: CodexLocalization.text(
                    "统计周期内至少产生过 Token 的天数",
                    "Days with at least one recorded token in this period"
                )
            )
            summaryMetric(
                id: "peak",
                icon: "chart.bar.fill",
                title: CodexLocalization.text("单日峰值", "Peak day"),
                value: compactNumber(summary.peakDayTokens),
                detail: formattedDay(summary.peakDayKey),
                help: CodexLocalization.text(
                    "当前周期内 Token 使用最多的一天",
                    "Highest-token day in the selected period"
                )
            )
            summaryMetric(
                id: "comparison",
                icon: comparisonIcon,
                title: CodexLocalization.text("环比", "Change"),
                value: comparisonText,
                detail: comparisonDetail,
                valueColor: comparisonColor,
                help: comparisonHelp
            )
        }
        .padding(10)
        .background(cardBackground)
    }

    private var hourlyActivityCard: some View {
        hourlyHeatmap
            .padding(10)
            .background(cardBackground)
    }

    private var hourlyHeatmap: some View {
        let hourlyUsage = hourlyActivityRange == .currentWeek
            ? snapshot.hourly
            : snapshot.hourlyLastYear
        let buckets = Dictionary(uniqueKeysWithValues: hourlyUsage.map { ($0.id, $0) })
        let nonzeroValues = hourlyUsage.map(\.tokens).filter { $0 > 0 }.sorted()
        let referenceIndex = max(0, Int(Double(max(0, nonzeroValues.count - 1)) * 0.90))
        let referenceValue = max(
            1,
            nonzeroValues.isEmpty ? 1 : nonzeroValues[referenceIndex]
        )
        let weekdayLabels = CodexLocalization.isChinese
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["M", "T", "W", "T", "F", "S", "S"]

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    CodexLocalization.text("小时活跃度", "Hourly activity"),
                    systemImage: "clock.badge"
                )
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(
                    Color.secondary.opacity(colorScheme == .dark ? 0.94 : 0.84)
                )
                Spacer()
                Label(
                    CodexLocalization.text("本地", "Local") + " · " + hourlyActivityRange.title,
                    systemImage: "internaldrive"
                )
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(
                        Color.secondary.opacity(colorScheme == .dark ? 0.70 : 0.56)
                    )
                    .help(CodexLocalization.text(
                        "来自本机 Codex 会话日志，统计范围：\(hourlyActivityRange.title)",
                        "From local Codex session logs · Range: \(hourlyActivityRange.title)"
                    ))
            }

            GeometryReader { proxy in
                #if CODEX_USAGE_TESTING
                let activeHourID = hoveredHourID
                    ?? UserDefaults.standard.string(forKey: "codexUsage.testing.hoveredHourID")
                #else
                let activeHourID = hoveredHourID
                #endif
                let hasHoveredHour = activeHourID != nil

                ZStack(alignment: .topLeading) {
                    VStack(spacing: Self.hourlyRowSpacing) {
                        ForEach(0..<7, id: \.self) { weekdayIndex in
                            HStack(spacing: 2) {
                                Text(weekdayLabels[weekdayIndex])
                                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(
                                        Color.secondary.opacity(colorScheme == .dark ? 0.74 : 0.60)
                                    )
                                    .frame(width: 9)
                                ForEach(0..<24, id: \.self) { hour in
                                    let rawWeekday = weekdayIndex == 6 ? 1 : weekdayIndex + 2
                                    let id = "\(rawWeekday)-\(hour)"
                                    let bucket = buckets[id]
                                    let tokens = bucket?.tokens ?? 0
                                    let intensity = min(
                                        1,
                                        sqrt(Double(tokens) / Double(referenceValue))
                                    )
                                    let isHovered = activeHourID == id
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(
                                            hourlyCellColor(
                                                tokens: tokens,
                                                intensity: intensity,
                                                isHovered: isHovered,
                                                isDimmed: hasHoveredHour && !isHovered
                                            )
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                                .strokeBorder(
                                                    isHovered ? Color.white.opacity(0.82) : .clear,
                                                    lineWidth: 0.7
                                                )
                                        }
                                        .scaleEffect(isHovered ? 1.14 : 1)
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: Self.hourlyCellHeight,
                                            maxHeight: Self.hourlyCellHeight
                                        )
                                        .zIndex(isHovered ? 2 : 0)
                                }
                            }
                        }
                    }

                    if let activeHourID,
                       let hovered = hourlyBucket(
                           id: activeHourID,
                           buckets: buckets
                       )
                    {
                        let pointer = hoveredHourLocation
                            ?? CGPoint(x: proxy.size.width * 0.68, y: proxy.size.height * 0.48)
                        let origin = hourlyTooltipOrigin(
                            pointer: pointer,
                            tooltipSize: hourlyTooltipSize,
                            chartSize: proxy.size
                        )
                        hourlyTooltip(
                            weekday: hovered.weekday,
                            hour: hovered.hour,
                            bucket: hovered.bucket
                        )
                        .background {
                            GeometryReader { tooltipProxy in
                                Color.clear.preference(
                                    key: CodexHourlyTooltipSizePreferenceKey.self,
                                    value: tooltipProxy.size
                                )
                            }
                        }
                        .offset(x: origin.x, y: origin.y)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(false)
                        .zIndex(5)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        updateHourlyHover(at: location, chartSize: proxy.size)
                    case .ended:
                        hoveredHourID = nil
                        hoveredHourLocation = nil
                    }
                }
                .onPreferenceChange(CodexHourlyTooltipSizePreferenceKey.self) { size in
                    guard size.width > 0, size.height > 0 else { return }
                    hourlyTooltipSize = size
                }
                .animation(.easeOut(duration: 0.13), value: activeHourID)
            }
            .frame(height: Self.hourlyGridHeight)

            HStack {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("23")
            }
            .font(.system(size: 6.5, weight: .medium, design: .monospaced))
            .foregroundStyle(
                Color.secondary.opacity(colorScheme == .dark ? 0.66 : 0.52)
            )
            .padding(.leading, 11)
            .frame(height: 11, alignment: .top)

            HStack(spacing: 8) {
                Text(hourlyDateRange)
                Spacer(minLength: 8)
                Text(CodexLocalization.text(
                    "悬停查看每小时 Token",
                    "Hover for hourly tokens"
                ))
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
    }

    private var hourlyDateRange: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = CodexLocalization.locale
        calendar.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current

        let referenceDate = snapshot.historyEnd ?? snapshot.updatedAt
        let end = calendar.startOfDay(for: referenceDate)
        switch hourlyActivityRange {
        case .currentWeek:
            let weekday = calendar.component(.weekday, from: end)
            let mondayOffset = (weekday + 5) % 7
            let start = calendar.date(byAdding: .day, value: -mondayOffset, to: end) ?? end
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: start) ?? end
            return "\(hourlyDayLabel(start)) – \(hourlyDayLabel(weekEnd))"
        case .lastYear:
            let start = snapshot.historyStart
                ?? calendar.date(byAdding: .day, value: -364, to: end)
                ?? end
            return "\(hourlyMonthLabel(start)) – \(hourlyMonthLabel(end))"
        }
    }

    private func hourlyDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = CodexLocalization.locale
        formatter.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        formatter.dateFormat = CodexLocalization.isChinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private func hourlyMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = CodexLocalization.locale
        formatter.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        formatter.dateFormat = CodexLocalization.isChinese ? "yy年M月" : "MMM yy"
        return formatter.string(from: date)
    }

    private func hourlyCellColor(
        tokens: Int,
        intensity: Double,
        isHovered: Bool,
        isDimmed: Bool
    ) -> Color {
        if isHovered {
            return primary.opacity(colorScheme == .dark ? 0.98 : 0.92)
        }

        if tokens == 0 {
            if isDimmed {
                return Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.022)
            }
            return Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.045)
        }

        let baseOpacity = colorScheme == .dark
            ? 0.26 + intensity * 0.64
            : 0.18 + intensity * 0.58
        return primary.opacity(isDimmed ? baseOpacity * 0.28 : baseOpacity)
    }

    private func hourlyBucket(
        id: String,
        buckets: [String: CodexHourlyUsageBucket]
    ) -> (weekday: Int, hour: Int, bucket: CodexHourlyUsageBucket?)? {
        let parts = id.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let weekday = Int(parts[0]),
              let hour = Int(parts[1]),
              (1...7).contains(weekday),
              (0...23).contains(hour)
        else {
            return nil
        }
        return (weekday, hour, buckets[id])
    }

    private func updateHourlyHover(at location: CGPoint, chartSize: CGSize) {
        let labelWidth: CGFloat = 9
        let spacing: CGFloat = 2
        let gridStartX = labelWidth + spacing
        let rowHeight = Self.hourlyCellHeight
        let rowSpacing = Self.hourlyRowSpacing
        let rowStride = rowHeight + rowSpacing
        let gridWidth = chartSize.width - gridStartX
        let cellWidth = (gridWidth - spacing * 23) / 24
        let cellStride = cellWidth + spacing

        guard chartSize.width > gridStartX,
              cellWidth > 0,
              location.x >= gridStartX,
              location.x <= chartSize.width,
              location.y >= 0,
              location.y <= chartSize.height
        else {
            hoveredHourID = nil
            hoveredHourLocation = nil
            return
        }

        let weekdayIndex = min(6, max(0, Int(location.y / rowStride)))
        let relativeX = location.x - gridStartX
        let hour = min(23, max(0, Int(relativeX / cellStride)))
        let rawWeekday = weekdayIndex == 6 ? 1 : weekdayIndex + 2
        hoveredHourID = "\(rawWeekday)-\(hour)"
        hoveredHourLocation = location
    }

    private func hourlyTooltip(
        weekday: Int,
        hour: Int,
        bucket: CodexHourlyUsageBucket?
    ) -> some View {
        let tokens = bucket?.tokens ?? 0
        let requests = bucket?.requestCount ?? 0
        let tokenText = tokens.formatted(.number.locale(CodexLocalization.locale))
        let requestText = requests.formatted(.number.locale(CodexLocalization.locale))
        let timeRange = String(format: "%02d:00–%02d:00", hour, hour + 1)

        return VStack(alignment: .leading, spacing: 3) {
            Text("\(hourlyWeekdayTitle(weekday)) · \(timeRange)")
                .font(.system(size: 8.5, weight: .semibold))
                .lineLimit(1)

            Text("\(tokenText) API tokens")
                .font(CodexTypography.tokenNumber(size: 8, weight: .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)

            Text(
                CodexLocalization.text(
                    "\(requestText) 次请求",
                    "\(requestText) requests"
                )
            )
            .font(CodexTypography.tokenNumber(size: 7.5, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(hourlyTooltipBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(primary.opacity(0.32), lineWidth: 0.65)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.34 : 0.16),
            radius: 5,
            y: 2
        )
    }

    private var hourlyTooltipBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.17, blue: 0.21)
            : Color(red: 0.87, green: 0.93, blue: 0.97)
    }

    private func hourlyWeekdayTitle(_ weekday: Int) -> String {
        if CodexLocalization.isChinese {
            return ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][
                min(7, max(1, weekday))
            ]
        }
        return ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][
            min(7, max(1, weekday))
        ]
    }

    private func hourlyTooltipOrigin(
        pointer: CGPoint,
        tooltipSize: CGSize,
        chartSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 2
        let gap: CGFloat = 8
        let width = max(tooltipSize.width, 1)
        let height = max(tooltipSize.height, 1)

        let preferredRightX = pointer.x + gap
        let x = preferredRightX + width <= chartSize.width - margin
            ? preferredRightX
            : max(margin, pointer.x - gap - width)

        let preferredAboveY = pointer.y - gap - height
        let maxY = max(margin, chartSize.height - height - margin)
        let y = preferredAboveY >= margin
            ? min(preferredAboveY, maxY)
            : min(maxY, pointer.y + gap)

        return CGPoint(x: x, y: max(margin, y))
    }

    private func summaryMetric(
        id: String,
        icon: String,
        title: String,
        value: String,
        detail: String? = nil,
        valueColor: Color? = nil,
        help: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(primary)
                .frame(width: 23, height: 23)
                .background(primary.opacity(colorScheme == .dark ? 0.15 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(CodexTypography.tokenNumber(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(valueColor ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if let detail {
                        Text(detail)
                            .font(CodexTypography.tokenNumber(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    hoveredMetric == id
                        ? primary.opacity(colorScheme == .dark ? 0.10 : 0.065)
                        : Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.018)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .scaleEffect(hoveredMetric == id ? 1.012 : 1)
        .animation(.easeOut(duration: 0.13), value: hoveredMetric == id)
        .onHover { hovering in
            hoveredMetric = hovering ? id : (hoveredMetric == id ? nil : hoveredMetric)
        }
        .help(help)
    }

    private var tokenCompositionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    CodexLocalization.text("Token 构成", "Token composition"),
                    systemImage: "chart.bar.doc.horizontal"
                )
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(compactNumber(summary.totalTokens))
                    .font(CodexTypography.tokenNumber(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            compositionBar
                .frame(height: 10)
                .help(compositionHelp)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(compositionItems) { item in
                    compositionMetric(item)
                }
                compositionMetric(
                    CompositionItem(
                        id: "priority",
                        title: "Fast/Priority",
                        value: summary.priorityTokens,
                        color: fastColor
                    )
                )
            }

            HStack(spacing: 8) {
                ratioPill(
                    icon: "bolt.horizontal.circle",
                    title: CodexLocalization.text("Cache 命中", "Cache hit"),
                    value: percent(summary.cacheHitPercent)
                )
                ratioPill(
                    icon: "hare",
                    title: CodexLocalization.text("Fast 占比", "Fast share"),
                    value: percent(fastShare)
                )
            }
        }
        .padding(11)
        .background(cardBackground)
    }

    @ViewBuilder
    private var compositionBar: some View {
        let items = compositionItems.filter { $0.value > 0 }
        let total = max(1, items.reduce(0) { $0 + $1.value })

        GeometryReader { proxy in
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.075))
            } else {
                let spacing = CGFloat(max(0, items.count - 1)) * 2
                let usableWidth = max(0, proxy.size.width - spacing)

                HStack(spacing: 2) {
                    ForEach(items) { item in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.color)
                            .frame(
                                width: max(
                                    2,
                                    usableWidth * CGFloat(item.value) / CGFloat(total)
                                )
                            )
                            .help(
                                "\(item.title): \(compactNumber(item.value)) · "
                                    + percent(Double(item.value) / Double(total) * 100)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.20), value: period)
    }

    private func compositionMetric(_ item: CompositionItem) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.color)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(compactNumber(item.value))
                    .font(CodexTypography.tokenNumber(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(item.title): \(tokenFormat.format(item.value))")
    }

    private func ratioPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(primary)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(CodexTypography.tokenNumber(size: 9.5, weight: .bold))
                .monospacedDigit()
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03))
        )
    }

    private var topModelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(
                    CodexLocalization.text("常用模型", "Top models"),
                    systemImage: "cpu"
                )
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(CodexLocalization.text("近 30 日", "Last 30 days"))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)

            if snapshot.topModels.isEmpty {
                Text(CodexLocalization.text("暂无模型用量", "No model usage yet"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(snapshot.topModels.prefix(3).enumerated()), id: \.element.id) {
                    index,
                    model in
                    if index > 0 {
                        Divider()
                            .opacity(colorScheme == .dark ? 0.22 : 0.32)
                            .padding(.leading, 17)
                    }
                    modelRow(model, rank: index)
                }
            }
        }
        .padding(11)
        .background(cardBackground)
    }

    private func modelRow(_ model: CodexModelUsageSummary, rank: Int) -> some View {
        let share = modelShare(model)
        let isHovered = hoveredModel == model.id

        return HStack(spacing: 8) {
            Circle()
                .fill(rank == 0 ? primary : (rank == 1 ? secondary : tertiaryAccent))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.model)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.065))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [primary, secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(2, proxy.size.width * CGFloat(share / 100)))
                    }
                }
                .frame(height: 3)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(compactNumber(model.tokens))
                    .font(CodexTypography.tokenNumber(size: 10, weight: .bold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text(estimatedCostText(
                        model.estimatedCostUSD,
                        coverage: model.costCoverage ?? .empty
                    ))
                    Text(percent(share))
                }
                .font(CodexTypography.tokenNumber(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? primary.opacity(colorScheme == .dark ? 0.09 : 0.055) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .scaleEffect(isHovered ? 1.008 : 1)
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .onHover { hovering in
            hoveredModel = hovering ? model.id : (hoveredModel == model.id ? nil : hoveredModel)
        }
        .help(
            "\(model.model)\n"
                + CodexLocalization.text("Token：", "Tokens: ")
                + tokenFormat.format(model.tokens)
                + "\n"
                + CodexLocalization.text("API 等价费用：", "API-equivalent cost: ")
                + currency(model.estimatedCostUSD)
        )
    }

    private var pricingFooter: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(primary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    CodexLocalization.text(
                        "API 等价估算，不是订阅账单",
                        "API-equivalent estimate, not a subscription bill"
                    )
                )
                .fontWeight(.semibold)

                Text(
                    CodexLocalization.text("价格来源：", "Pricing source: ")
                        + summary.costProvenance.title
                )
                .foregroundStyle(.tertiary)

                Text(costCoverageText(summary.costCoverage))
                    .foregroundStyle(
                        summary.costCoverage.isComplete
                            ? Color.secondary.opacity(0.68)
                            : primary
                    )
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
        .help(
            CodexLocalization.text(
                "费用根据本地 Token 记录和价格目录估算，可能与实际产品权益不同。",
                "Cost is estimated from local token records and the pricing catalog; product entitlements may differ."
            )
        )
    }

    private var summary: CodexUsagePeriodSummary {
        switch period {
        case .sevenDays: snapshot.last7DaysSummary
        case .thirtyDays: snapshot.last30DaysSummary
        case .allTime: snapshot.allTimeSummary
        }
    }

    private var periodDayCount: Int {
        period == .allTime ? max(1, snapshot.daily.count) : period.dayCount
    }

    private var compositionItems: [CompositionItem] {
        [
            CompositionItem(
                id: "input",
                title: CodexLocalization.text("输入", "Input"),
                value: summary.uncachedInputTokens,
                color: primary
            ),
            CompositionItem(
                id: "cacheRead",
                title: "Cache Read",
                value: summary.cachedInputTokens,
                color: secondary
            ),
            CompositionItem(
                id: "cacheWrite",
                title: "Cache Write",
                value: summary.cacheWriteInputTokens,
                color: cacheWriteColor
            ),
            CompositionItem(
                id: "visibleOutput",
                title: CodexLocalization.text("可见输出", "Visible output"),
                value: summary.visibleOutputTokens,
                color: outputColor
            ),
            CompositionItem(
                id: "reasoning",
                title: CodexLocalization.text("推理", "Reasoning"),
                value: summary.reasoningOutputTokens,
                color: reasoningColor
            ),
        ]
    }

    private var fastShare: Double? {
        guard summary.totalTokens > 0 else { return nil }
        return min(
            100,
            max(0, Double(summary.priorityTokens) / Double(summary.totalTokens) * 100)
        )
    }

    private var comparisonValue: Double? {
        period == .sevenDays ? snapshot.comparison.sevenDayChangePercent : nil
    }

    private var comparisonText: String {
        guard let comparisonValue else {
            return CodexLocalization.text("—", "—")
        }
        return String(format: "%@%.0f%%", comparisonValue >= 0 ? "+" : "", comparisonValue)
    }

    private var comparisonDetail: String? {
        period == .sevenDays
            ? CodexLocalization.text("较前 7 日", "vs prior 7d")
            : CodexLocalization.text("暂无基准", "No baseline")
    }

    private var comparisonIcon: String {
        guard let comparisonValue else { return "minus" }
        if comparisonValue > 0 { return "arrow.up.right" }
        if comparisonValue < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var comparisonColor: Color? {
        guard let comparisonValue else { return nil }
        if comparisonValue > 0 { return CodexPalette.orange(for: colorScheme) }
        if comparisonValue < 0 { return CodexPalette.green(for: colorScheme) }
        return nil
    }

    private var comparisonHelp: String {
        if period == .sevenDays {
            return CodexLocalization.text(
                "最近 7 日 Token 总量相对之前 7 日的变化",
                "Change in total tokens versus the preceding seven days"
            )
        }
        return period == .allTime
            ? CodexLocalization.text("全部历史没有可比较的前置周期", "All-time history has no preceding comparison period")
            : CodexLocalization.text(
                "当前本机扫描范围为 30 日，尚无前一个 30 日周期作为基准",
                "The current local scan covers 30 days, so a prior 30-day baseline is unavailable"
            )
    }

    private var compositionHelp: String {
        CodexLocalization.text(
            "输入、Cache Read、Cache Write、可见输出和推理 Token 的构成；Fast 为独立服务层标签。",
            "Composition of input, cache read, cache write, visible output, and reasoning tokens. Fast is a separate service-tier label."
        )
    }

    private func modelShare(_ model: CodexModelUsageSummary) -> Double {
        let total = snapshot.last30DaysSummary.totalTokens
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(model.tokens) / Double(total) * 100))
    }

    private var cardBackground: some View {
        CodexGlassCard(cornerRadius: 13)
    }

    private var cacheWriteColor: Color {
        colorScheme == .dark
            ? Color(red: 0.74, green: 0.53, blue: 0.29)
            : Color(red: 0.91, green: 0.57, blue: 0.14)
    }

    private var outputColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.68, blue: 0.47)
            : Color(red: 0.18, green: 0.70, blue: 0.38)
    }

    private var reasoningColor: Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.47, blue: 0.73)
            : Color(red: 0.62, green: 0.31, blue: 0.77)
    }

    private var fastColor: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.38, blue: 0.55)
            : Color(red: 0.88, green: 0.21, blue: 0.54)
    }

    private var tertiaryAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.46, green: 0.63, blue: 0.74)
            : Color(red: 0.32, green: 0.58, blue: 0.75)
    }

    private func compactNumber(_ value: Int) -> String {
        tokenFormat.format(value)
    }

    private func compactCount(_ value: Int) -> String {
        let number = Double(max(0, value))
        if number >= 1_000_000_000 {
            return compact(number / 1_000_000_000, suffix: "B")
        }
        if number >= 1_000_000 {
            return compact(number / 1_000_000, suffix: "M")
        }
        if number >= 1_000 {
            return compact(number / 1_000, suffix: "K")
        }
        return value.formatted(.number.locale(CodexLocalization.locale))
    }

    private func compact(_ value: Double, suffix: String) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(digits)f%@", value, suffix)
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        if value >= 10 {
            return String(format: "$%.1f", value)
        }
        return String(format: "$%.2f", value)
    }

    private func estimatedCostText(
        _ value: Double?,
        coverage: CodexCostCoverage
    ) -> String {
        let formatted = currency(value)
        guard value != nil, !coverage.isComplete else { return formatted }
        return "~\(formatted)"
    }

    private func costCoverageText(_ coverage: CodexCostCoverage) -> String {
        guard let percent = coverage.tokenPercent else {
            return CodexLocalization.text("暂无可计价 Token", "No priceable tokens")
        }
        return CodexLocalization.text(
            "费用覆盖：\(Int(percent.rounded()))% · \(coverage.pricedRequests)/\(coverage.totalRequests) 次请求",
            "Cost coverage: \(Int(percent.rounded()))% · \(coverage.pricedRequests)/\(coverage.totalRequests) requests"
        )
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    private func formattedDay(_ dayKey: String?) -> String? {
        guard let dayKey else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.dateFormat = CodexLocalization.isChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }

    private enum Period: String, CaseIterable, Identifiable {
        case sevenDays
        case thirtyDays
        case allTime

        var id: String { rawValue }
        var dayCount: Int {
            switch self {
            case .sevenDays: 7
            case .thirtyDays: 30
            case .allTime: 365
            }
        }
        var title: String {
            switch self {
            case .sevenDays:
                return CodexLocalization.text("7 日", "7 days")
            case .thirtyDays:
                return CodexLocalization.text("30 日", "30 days")
            case .allTime:
                return CodexLocalization.text("全部", "All")
            }
        }
    }

private struct CompositionItem: Identifiable {
        let id: String
        let title: String
        let value: Int
        let color: Color
    }
}

private struct CodexHourlyTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
