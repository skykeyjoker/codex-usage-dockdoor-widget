import AppKit
import DockDoorWidgetSDK
import SwiftUI

struct CodexUsageMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    @ObservedObject var monitor: CodexUsageMonitor
    @Environment(\.colorScheme) private var appearance
    @State private var carouselStartedAt = Date()

    private static let carouselInterval: TimeInterval = 8
    private var dim: CGFloat { min(size.width, size.height) }
    private var horizontalRingMetricSpacing: CGFloat { dim * 0.14 }
    private var slotSpan: WidgetSlotSpan { WidgetSlotSpan.detect(size: size, isVertical: isVertical) }
    private var theme: CodexThemeColors {
        CodexColorTheme.resolve(widgetId: widgetId).colors(for: appearance)
    }
    private var displayLimit: CodexDisplayLimit {
        CodexDisplayLimit.resolve(title: WidgetDefaults.string(
            key: "displayLimit",
            widgetId: widgetId,
            default: CodexDisplayLimit.weekly.title
        ))
    }
    private var displayMetric: CodexDisplayMetric {
        CodexDisplayMetric.resolve(title: WidgetDefaults.string(
            key: "displayMetric",
            widgetId: widgetId,
            default: CodexDisplayMetric.remaining.title
        ))
    }
    private var ringStyle: CodexRingStyle {
        CodexRingStyle.resolve(title: WidgetDefaults.string(
            key: "ringStyle",
            widgetId: widgetId,
            default: CodexRingStyle.concentric.title
        ))
    }
    private var showStatus: Bool {
        WidgetDefaults.bool(key: "showStatus", widgetId: widgetId, default: true)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.carouselInterval)) { context in
            Group {
                switch slotSpan {
                case .compact: compactLayout(at: context.date)
                case .extended: extendedLayout(at: context.date)
                case .triple: tripleLayout(at: context.date)
                }
            }
            .onChange(of: context.date) { _, _ in monitor.syncConfiguration() }
        }
        .onAppear { monitor.start() }
        .onChange(of: ringStyle) { _, value in
            if value == .carousel {
                carouselStartedAt = Date()
            }
        }
    }

    private func compactLayout(at date: Date) -> some View {
        let activeStyle = activeRingStyle(at: date)
        return Group {
            if let window = monitor.window(for: displayLimit) {
                ZStack {
                    compactRing(window, style: activeStyle)
                        .padding(dim * 0.09)
                        .id(activeStyle)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))

                    if activeStyle != .concentric {
                        Text("\(Int(percent(window).rounded()))%")
                            .font(.system(
                                size: dim * 0.23,
                                weight: .bold,
                                design: .rounded
                            ).monospacedDigit())
                            .foregroundStyle(valueTint(window))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .padding(dim * 0.18)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: activeStyle)
                .overlay(alignment: .topTrailing) {
                    if showStatus {
                        compactStatusDot
                            .padding(dim * 0.10)
                    }
                }
            } else {
                emptyState(compact: true)
            }
        }
        .padding(dim * 0.06)
    }

    @ViewBuilder
    private func compactRing(
        _ window: CodexQuotaWindow,
        style: CodexRingStyle
    ) -> some View {
        switch style {
        case .classic, .carousel:
            CodexQuotaRing(
                progress: progress(window),
                gradient: ringGradient(window),
                lineWidth: max(3, dim * 0.10)
            )
        case .concentric:
            CodexQuarterRings(
                progress: progress(window),
                colors: ringColors(window)
            )
        case .segmented:
            CodexSegmentedRing(
                progress: progress(window),
                gradient: ringGradient(window),
                lineWidth: max(3, dim * 0.10)
            )
        }
    }

    private func activeRingStyle(at date: Date) -> CodexRingStyle {
        guard ringStyle == .carousel else { return ringStyle }
        let elapsed = max(0, date.timeIntervalSince(carouselStartedAt))
        let index = Int(elapsed / Self.carouselInterval)
            % CodexRingStyle.carouselStyles.count
        return CodexRingStyle.carouselStyles[index]
    }

    private func extendedLayout(at date: Date) -> some View {
        let style = activeRingStyle(at: date)
        return Group {
            if let window = monitor.window(for: displayLimit) {
                if isVertical {
                    VStack(spacing: dim * 0.08) {
                        multiSlotRing(
                            window,
                            style: style,
                            size: dim * 0.82,
                            showsValue: false
                        )
                        metric(window, centered: true)
                    }
                } else {
                    HStack(spacing: horizontalRingMetricSpacing) {
                        multiSlotRing(
                            window,
                            style: style,
                            size: dim * 0.82,
                            showsValue: false
                        )
                        metric(window, centered: false)
                    }
                }
            } else {
                emptyState(compact: false)
            }
        }
        .padding(dim * 0.08)
    }

    private func tripleLayout(at date: Date) -> some View {
        let style = activeRingStyle(at: date)
        return Group {
            if let usage = monitor.usage {
                if isVertical {
                    VStack(spacing: dim * 0.10) {
                        if let weekly = usage.weeklyWindow {
                            multiSlotRing(
                                weekly,
                                style: style,
                                size: dim * 0.82,
                                showsValue: true
                            )
                        }
                        limitsStack(usage)
                        if showStatus { serviceBadge }
                    }
                } else {
                    HStack(spacing: horizontalRingMetricSpacing) {
                        if let weekly = usage.weeklyWindow {
                            multiSlotRing(
                                weekly,
                                style: style,
                                size: dim * 0.82,
                                showsValue: true
                            )
                        }
                        limitsStack(usage)
                        if showStatus {
                            Rectangle()
                                .fill(Color.primary.opacity(0.10))
                                .frame(width: 0.5)
                            serviceBadge
                        }
                    }
                }
            } else {
                emptyState(compact: false)
            }
        }
        .padding(isVertical ? dim * 0.04 : dim * 0.08)
    }

    private func multiSlotRing(
        _ window: CodexQuotaWindow,
        style: CodexRingStyle,
        size: CGFloat,
        showsValue: Bool
    ) -> some View {
        ZStack {
            switch style {
            case .classic, .carousel:
                CodexQuotaRing(
                    progress: progress(window),
                    gradient: ringGradient(window),
                    lineWidth: max(size * 0.10, 3)
                )
            case .concentric:
                CodexQuarterRings(
                    progress: progress(window),
                    colors: ringColors(window)
                )
            case .segmented:
                CodexSegmentedRing(
                    progress: progress(window),
                    gradient: ringGradient(window),
                    lineWidth: max(size * 0.10, 3)
                )
            }

            if showsValue && style != .concentric {
                Text("\(Int(percent(window).rounded()))%")
                    .font(.system(
                        size: max(12, size * 0.18),
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(valueTint(window))
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .id(style)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: 0.35), value: style)
    }

    private func metric(_ window: CodexQuotaWindow, centered: Bool) -> some View {
        let metricLabel = displayMetric == .remaining
            ? CodexLocalization.text("剩余", "remaining")
            : CodexLocalization.text("已用", "used")

        return VStack(alignment: centered ? .center : .leading, spacing: dim * 0.03) {
            HStack(spacing: dim * 0.045) {
                Text(displayLimit == .weekly
                    ? CodexLocalization.text("每周", "WEEKLY")
                    : CodexLocalization.text("短周期", "SESSION"))
                    .font(.system(size: max(9, dim * 0.125), weight: .semibold))
                if showStatus { compactStatusDot }
            }
            HStack(alignment: .firstTextBaseline, spacing: dim * 0.025) {
                Text("\(Int(percent(window).rounded()))%")
                    .font(.system(
                        size: max(13, dim * 0.18),
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(valueTint(window))
                Text(metricLabel)
                    .font(.system(
                        size: max(9, dim * 0.115),
                        weight: .medium,
                        design: .rounded
                    ))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            remainingBar(window, width: dim * 0.82)
            if monitor.isRefreshing {
                Text(CodexLocalization.text("更新中…", "Updating…"))
                    .font(.system(size: max(7, dim * 0.09), weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
        }
    }

    private func limitsStack(_ usage: CodexUsageSnapshot) -> some View {
        VStack(alignment: isVertical ? .center : .leading, spacing: dim * 0.055) {
            if let weekly = usage.weeklyWindow {
                miniLimit(title: CodexLocalization.text("每周", "Weekly"), window: weekly)
            }
            if let session = usage.sessionWindow {
                miniLimit(title: CodexLocalization.text("短周期", "Session"), window: session)
            }
            if usage.sessionWindow == nil, let reset = usage.resetCreditsAvailable {
                Text(CodexLocalization.text("重置额度 \(reset) 次", "\(reset) quota resets"))
                    .font(.system(size: max(8, dim * 0.10), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func miniLimit(title: String, window: CodexQuotaWindow) -> some View {
        VStack(alignment: isVertical ? .center : .leading, spacing: dim * 0.025) {
            HStack(spacing: dim * 0.04) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .fontWeight(.bold)
            }
            .font(.system(
                size: max(9, dim * 0.125),
                weight: .medium,
                design: .rounded
            ).monospacedDigit())
            remainingBar(window, width: dim * 0.82)
        }
    }

    private func remainingBar(
        _ window: CodexQuotaWindow,
        width: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint(window))
                    .frame(width: proxy.size.width * window.remainingRatio)
            }
        }
        .frame(width: width, height: max(3, dim * 0.045))
    }

    private var serviceBadge: some View {
        let status = monitor.serviceStatus?.overallIndicator ?? .unknown
        let statusColor = status.color(for: appearance)
        return VStack(spacing: dim * 0.045) {
            Circle()
                .fill(statusColor)
                .frame(width: dim * 0.15, height: dim * 0.15)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: statusColor.opacity(0.28), radius: 4)
            Text(CodexLocalization.text("状态", "STATUS"))
                .font(.system(size: max(7, dim * 0.085), weight: .bold))
                .foregroundStyle(.secondary)
            Text(status.label)
                .font(.system(size: max(8, dim * 0.10), weight: .semibold))
                .lineLimit(1)
        }
        .frame(minWidth: dim * 0.65)
    }

    private var compactStatusDot: some View {
        let indicator = monitor.serviceStatus?.overallIndicator ?? .unknown
        return Circle()
            .fill(indicator.color(for: appearance))
            .frame(width: max(5, dim * 0.07), height: max(5, dim * 0.07))
            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .shadow(
                color: indicator.color(for: appearance).opacity(0.28),
                radius: 2
            )
    }

    private func emptyState(compact: Bool) -> some View {
        VStack(spacing: dim * 0.055) {
            Image(systemName: monitor.usageError == nil ? "terminal.fill" : "person.badge.key.fill")
                .font(.system(size: dim * (compact ? 0.34 : 0.30), weight: .semibold))
                .foregroundStyle(theme.gradient)
            if !compact {
                Text(monitor.usageError == nil
                    ? CodexLocalization.text("正在读取 Codex", "Loading Codex")
                    : CodexLocalization.text("请打开详情", "Open details"))
                    .font(.system(size: dim * 0.10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func percent(_ window: CodexQuotaWindow) -> Double {
        displayMetric == .remaining ? window.remainingPercent : window.usedPercent
    }

    private func progress(_ window: CodexQuotaWindow) -> Double {
        displayMetric == .remaining ? window.remainingRatio : window.usedRatio
    }

    private func tint(_ window: CodexQuotaWindow) -> Color {
        switch window.remainingPercent {
        case ..<10: return CodexPalette.softCritical(for: appearance)
        case ..<25: return CodexPalette.yellow(for: appearance)
        default: return theme.primary
        }
    }

    private func valueTint(_ window: CodexQuotaWindow) -> Color {
        window.remainingPercent < 10 ? CodexPalette.softCritical(for: appearance) : .primary
    }

    private func ringGradient(_ window: CodexQuotaWindow) -> LinearGradient {
        LinearGradient(
            colors: ringColors(window),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func ringColors(_ window: CodexQuotaWindow) -> [Color] {
        let baseColors: [Color]
        switch window.remainingPercent {
        case ..<10:
            baseColors = [
                CodexPalette.softCritical(for: appearance),
                CodexPalette.orange(for: appearance).opacity(0.88),
            ]
        case ..<25:
            baseColors = [
                CodexPalette.yellow(for: appearance),
                CodexPalette.orange(for: appearance),
            ]
        default:
            baseColors = [theme.primary, theme.secondary]
        }

        guard let primary = baseColors.first,
              let secondary = baseColors.last
        else {
            return baseColors
        }
        return [
            blendedRingColor(primary, secondary, fraction: 0.15),
            blendedRingColor(primary, secondary, fraction: 0.85),
        ]
    }

    private func blendedRingColor(
        _ primary: Color,
        _ secondary: Color,
        fraction: CGFloat
    ) -> Color {
        guard let start = NSColor(primary).usingColorSpace(.deviceRGB),
              let end = NSColor(secondary).usingColorSpace(.deviceRGB)
        else {
            return fraction < 0.5 ? primary : secondary
        }
        return Color(nsColor: start.blended(
            withFraction: min(max(fraction, 0), 1),
            of: end
        ) ?? start)
    }
}

private struct CodexQuarterRings: View {
    let progress: Double
    let colors: [Color]

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private func ringColor(at index: Int) -> Color {
        guard let outerColor = colors.first else { return .accentColor }
        guard let innerColor = colors.last, colors.count > 1 else {
            return outerColor
        }
        let fraction = CGFloat(index) / 3
        guard let outer = NSColor(outerColor).usingColorSpace(.deviceRGB),
              let inner = NSColor(innerColor).usingColorSpace(.deviceRGB)
        else {
            return index < 2 ? outerColor : innerColor
        }
        return Color(nsColor: outer.blended(
            withFraction: fraction,
            of: inner
        ) ?? outer)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(2.4, diameter * 0.082)
            let gap = max(0.75, diameter * 0.014)
            let step = lineWidth + gap

            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    let ringProgress = min(
                        max(clampedProgress * 4 - Double(index), 0),
                        1
                    )
                    let inset = CGFloat(index) * step

                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
                        .padding(inset)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            ringColor(at: index),
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.30), value: clampedProgress)
    }
}

private struct CodexSegmentedRing: View {
    let progress: Double
    let gradient: LinearGradient
    let lineWidth: CGFloat

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let segmentProgress = min(
                    max(clampedProgress * 4 - Double(index), 0),
                    1
                )
                let segmentStart = Double(index) * 0.25 + 0.006
                let segmentEnd = Double(index + 1) * 0.25 - 0.006
                let progressEnd = segmentStart
                    + (segmentEnd - segmentStart) * segmentProgress

                Circle()
                    .trim(from: segmentStart, to: segmentEnd)
                    .stroke(
                        Color.primary.opacity(0.10),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )

                if segmentProgress > 0 {
                    Circle()
                        .trim(from: segmentStart, to: progressEnd)
                        .stroke(
                            gradient,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .animation(.easeInOut(duration: 0.30), value: clampedProgress)
    }
}

private struct CodexQuotaRing: View {
    let progress: Double
    let gradient: LinearGradient
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct CodexSolidPie: View {
    let progress: Double
    let colors: CodexThemeColors

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.12))
            CodexPieSlice(progress: progress)
                .fill(colors.gradient)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct CodexPieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }
        if clamped >= 0.9999 { return Path(ellipseIn: rect) }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
