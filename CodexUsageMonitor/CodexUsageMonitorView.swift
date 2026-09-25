import DockDoorWidgetSDK
import SwiftUI

/// A fixed row per provider keeps unavailable data visible without hiding healthy accounts.
struct CodexUsageMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    @ObservedObject var monitor: CodexUsageMonitor
    @Environment(\.colorScheme) private var appearance

    private var dim: CGFloat { min(size.width, size.height) }
    private var span: WidgetSlotSpan { WidgetSlotSpan.detect(size: size, isVertical: isVertical) }
    private var limit: CodexDisplayLimit {
        .resolve(title: WidgetDefaults.string(key: "displayLimit", widgetId: widgetId, default: CodexDisplayLimit.weekly.title))
    }
    private var metric: CodexDisplayMetric {
        .resolve(title: WidgetDefaults.string(key: "displayMetric", widgetId: widgetId, default: CodexDisplayMetric.remaining.title))
    }
    private var providers: [CodexDockProvider] {
        let cursor = WidgetDefaults.bool(key: "cursorUsageEnabled", widgetId: widgetId, default: true)
        let claude = WidgetDefaults.bool(key: "claudeUsageEnabled", widgetId: widgetId, default: true)
        let selected = CodexDockProvider.resolve(title: WidgetDefaults.string(
            key: "dockProvider", widgetId: widgetId, default: CodexDockProvider.all.title))
        let requested: [CodexDockProvider]
        switch selected {
        case .all: requested = [.codex, .claude, .cursor]
        case .both: requested = [.codex, .cursor]
        default: requested = [selected]
        }
        let enabled = requested.filter { ($0 != .cursor || cursor) && ($0 != .claude || claude) }
        return enabled.isEmpty ? [.codex] : enabled
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Group {
                if span == .triple && !isVertical {
                    HStack(spacing: dim * 0.11) {
                        ForEach(providers) { provider in card(provider, detailed: true) }
                    }
                } else if isVertical && span != .compact {
                    VStack(spacing: dim * 0.12) {
                        ForEach(providers) { provider in card(provider, detailed: span == .triple) }
                    }
                } else if providers.count == 1 {
                    card(providers[0], detailed: span != .compact)
                } else {
                    VStack(spacing: max(4, dim * 0.075)) {
                        ForEach(providers) { provider in row(provider, compact: span == .compact) }
                    }
                }
            }
            .padding(.horizontal, dim * (span == .compact ? 0.06 : 0.09))
            .padding(.vertical, dim * 0.07)
            .frame(width: size.width, height: size.height)
        }
        .onAppear { monitor.start() }
    }

    private func row(_ provider: CodexDockProvider, compact: Bool) -> some View {
        let window = monitor.window(for: limit, provider: provider)
        let stale = isStale(provider)
        return HStack(spacing: max(1.5, dim * 0.04)) {
            mark(provider, size: max(7, dim * 0.14))
            if !compact {
                Text(provider.title)
                    .font(.system(size: max(8, dim * 0.13), weight: .semibold))
                    .frame(width: dim * 0.57, alignment: .leading)
            }
            quotaBar(window, provider: provider)
                .frame(height: max(3, dim * 0.07))
                .opacity(stale ? 0.45 : 1)
            Text(value(window, compact: compact))
                .font(.system(size: max(7, dim * 0.15), weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(stale ? Color.secondary : Color.primary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: max(7, dim * 0.15) * (compact ? 2.3 : 3.2), alignment: .trailing)
            if stale && !compact {
                Image(systemName: "clock.badge.exclamationmark").font(.system(size: 8)).foregroundStyle(.orange)
            }
        }
        .help(help(provider, window: window))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help(provider, window: window))
    }

    private func card(_ provider: CodexDockProvider, detailed: Bool) -> some View {
        let window = monitor.window(for: limit, provider: provider)
        return VStack(alignment: .leading, spacing: max(2, dim * 0.045)) {
            HStack(spacing: 3) {
                mark(provider, size: max(8, dim * 0.13))
                Text(provider.title).font(.system(size: max(8, dim * 0.125), weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if isStale(provider) {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 8)).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value(window, compact: false))
                    .font(.system(size: max(11, dim * 0.21), weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isStale(provider) ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: true, vertical: false)

            }.lineLimit(1)
            quotaBar(window, provider: provider).frame(height: max(3, dim * 0.065))
                .opacity(isStale(provider) ? 0.45 : 1)
            if detailed {
                Text(window.map { shortReset($0) } ?? CodexLocalization.text("未连接", "Unavailable"))
                    .font(.system(size: max(7, dim * 0.095), weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .help(help(provider, window: window))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help(provider, window: window))
    }

    @ViewBuilder
    private func mark(_ provider: CodexDockProvider, size: CGFloat) -> some View {
        if provider == .claude {
            Image(systemName: "asterisk").font(.system(size: size, weight: .heavy))
                .foregroundStyle(accent(provider)).frame(width: size, height: size)
        } else {
            CodexProviderIcon(brand: provider == .cursor ? .cursor : .codex, size: size, color: accent(provider))
                .overlay(alignment: .bottomTrailing) {
                    if provider == .codex,
                       WidgetDefaults.bool(key: "showStatus", widgetId: widgetId, default: true),
                       let status = monitor.serviceStatus {
                        Circle().fill((status.codex?.indicator ?? status.overallIndicator).color(for: appearance))
                            .frame(width: 3, height: 3)
                    }
                }
        }
    }

    private func quotaBar(_ window: CodexQuotaWindow?, provider: CodexDockProvider) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.11))
                if let window {
                    Capsule().fill(window.remainingPercent < 10 ? Color.red : window.remainingPercent < 25 ? Color.orange : accent(provider))
                        .frame(width: proxy.size.width * (metric == .remaining ? window.remainingRatio : window.usedRatio))
                } else {
                    Text("···").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func accent(_ provider: CodexDockProvider) -> Color {
        switch provider {
        case .claude: return Color(red: 0.82, green: 0.49, blue: 0.35)
        case .cursor: return Color(red: 0.24, green: 0.65, blue: 0.48)
        default: return CodexColorTheme.resolve(widgetId: widgetId).colors(for: appearance).primary
        }
    }

    private func isStale(_ provider: CodexDockProvider) -> Bool {
        let date: Date?
        let error: String?
        switch provider {
        case .claude: date = monitor.claudeUsage?.fetchedAt; error = monitor.claudeUsageError
        case .cursor: date = monitor.cursorUsage?.fetchedAt; error = monitor.cursorUsageError
        default: date = monitor.usage?.fetchedAt; error = monitor.usageError
        }
        return error != nil || date.map { Date().timeIntervalSince($0) > 3600 } == true
    }

    private func value(_ window: CodexQuotaWindow?, compact: Bool) -> String {
        guard let window else { return "—" }
        let percent = metric == .remaining ? window.remainingPercent : min(100, max(0, window.usedPercent))
        return "\(Int(percent.rounded()))" + (compact ? "" : "%")
    }

    private func shortReset(_ window: CodexQuotaWindow) -> String {
        guard let reset = window.resetAt else { return window.title }
        let seconds = max(0, reset.timeIntervalSinceNow)
        if seconds < 60 { return CodexLocalization.text("即将重置", "Resetting") }
        let hours = Int(seconds / 3600)
        let time = hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : hours > 0 ? "\(hours)h \(Int(seconds / 60) % 60)m" : "\(Int(seconds / 60))m"
        return "↻ " + time
    }

    private func help(_ provider: CodexDockProvider, window: CodexQuotaWindow?) -> String {
        let status = isStale(provider) ? CodexLocalization.text(" · 数据未更新", " · Not up to date") : ""
        guard let window else { return provider.title + CodexLocalization.text(" · 额度不可用，打开详情查看", " · Quota unavailable; open details") }
        return "\(provider.title) · \(window.title) · \(metric.title) \(value(window, compact: false)) · \(window.resetDescription())\(status)"
    }
}
