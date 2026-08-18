import DockDoorWidgetSDK
import SwiftUI

final class CodexUsageMonitorPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "codex-usage-monitor" }
    var name: String { "Codex Usage" }
    var iconSymbol: String { "terminal.fill" }
    var widgetDescription: String {
        CodexLocalization.text(
            "Codex 额度、最近 Token 用量、最近任务及 ChatGPT/Codex 服务状态。",
            "Codex quota, recent token usage, recent tasks, and ChatGPT/Codex service status."
        )
    }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private var storedMonitor: CodexUsageMonitor?

    func settingsSchema() -> [WidgetSetting] {
        normalizeStoredPickerSettings()
        return [
            .picker(
                key: "displayLimit",
                label: CodexLocalization.text("Dock 额度", "Dock Quota"),
                options: CodexDisplayLimit.allCases.map(\.title),
                defaultValue: CodexDisplayLimit.weekly.title
            ),
            .picker(
                key: "displayMetric",
                label: CodexLocalization.text("Dock 数值", "Dock Value"),
                options: CodexDisplayMetric.allCases.map(\.title),
                defaultValue: CodexDisplayMetric.remaining.title
            ),
            .picker(
                key: "ringStyle",
                label: CodexLocalization.text("圆环样式", "Ring Style"),
                options: CodexRingStyle.allCases.map(\.title),
                defaultValue: CodexRingStyle.concentric.title
            ),
            .picker(
                key: "colorTheme",
                label: CodexLocalization.text("主题颜色", "Color Theme"),
                options: CodexColorTheme.allCases.map(\.title),
                defaultValue: CodexColorTheme.codex.title
            ),
            .picker(
                key: "quotaUsageSource",
                label: CodexLocalization.text("额度来源", "Quota Usage Source"),
                options: CodexQuotaUsageSource.allCases.map(\.title),
                defaultValue: CodexQuotaUsageSource.automatic.title
            ),
            .picker(
                key: "refreshInterval",
                label: CodexLocalization.text("刷新频率", "Refresh Interval"),
                options: CodexRefreshInterval.allCases.map(\.title),
                defaultValue: CodexRefreshInterval.fiveMinutes.title
            ),
            .picker(
                key: "tokenFormat",
                label: CodexLocalization.text("Panel Token 格式", "Panel Token Format"),
                options: CodexTokenFormat.allCases.map(\.title),
                defaultValue: CodexTokenFormat.automatic.title
            ),
            .picker(
                key: "hourlyActivityRange",
                label: CodexLocalization.text(
                    "小时活跃度范围",
                    "Hourly Activity Range"
                ),
                options: CodexHourlyActivityRange.allCases.map(\.title),
                defaultValue: CodexHourlyActivityRange.currentWeek.title
            ),
            .toggle(
                key: "showQuickLaunchBar",
                label: CodexLocalization.text("Panel 显示快捷启动栏", "Show Quick Launch Bar in Panel"),
                defaultValue: true
            ),
            .toggle(
                key: "showCodexLaunch",
                label: CodexLocalization.text("快捷栏显示 Codex Desktop", "Show Codex Desktop Shortcut"),
                defaultValue: true
            ),
            .toggle(
                key: "showGPTClassicLaunch",
                label: CodexLocalization.text(
                    "快捷栏显示 ChatGPT Classic",
                    "Show ChatGPT Classic Shortcut"
                ),
                defaultValue: true
            ),
            .toggle(
                key: "showCLILaunch",
                label: CodexLocalization.text("快捷栏显示 Codex CLI", "Show Codex CLI Shortcut"),
                defaultValue: true
            ),
            .picker(
                key: "preferredTerminal",
                label: CodexLocalization.text("Codex CLI 终端", "Codex CLI Terminal"),
                options: CodexTerminalApplication.allCases.map(\.title),
                defaultValue: CodexTerminalApplication.automatic.title
            ),
            .toggle(
                key: "showStatus",
                label: CodexLocalization.text("Dock 显示服务状态", "Show Service Status in Dock"),
                defaultValue: true
            ),
            .toggle(
                key: "checkReleaseUpdates",
                label: CodexLocalization.text(
                    "检查 GitHub Release 更新",
                    "Check GitHub release updates"
                ),
                defaultValue: true
            ),
        ]
    }

    private func normalizeStoredPickerSettings() {
        let prefix = "widget.\(id)."
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: prefix + "displayLimit") {
            let normalized = CodexDisplayLimit.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "displayLimit") }
        }
        if let value = defaults.string(forKey: prefix + "displayMetric") {
            let normalized = CodexDisplayMetric.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "displayMetric") }
        }
        if let value = defaults.string(forKey: prefix + "ringStyle") {
            let normalized = CodexRingStyle.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "ringStyle") }
        }
        if let value = defaults.string(forKey: prefix + "colorTheme") {
            let normalized = CodexColorTheme.resolve(widgetId: id).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "colorTheme") }
        }
        if let value = defaults.string(forKey: prefix + "quotaUsageSource") {
            let normalized = CodexQuotaUsageSource.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "quotaUsageSource") }
        }
        if let value = defaults.string(forKey: prefix + "refreshInterval") {
            let normalized = CodexRefreshInterval.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "refreshInterval") }
        }
        if let value = defaults.string(forKey: prefix + "tokenFormat") {
            let normalized = CodexTokenFormat.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "tokenFormat") }
        }
        if let value = defaults.string(forKey: prefix + "hourlyActivityRange") {
            let normalized = CodexHourlyActivityRange.resolve(title: value).title
            if value != normalized {
                defaults.set(normalized, forKey: prefix + "hourlyActivityRange")
            }
        }
        if let value = defaults.string(forKey: prefix + "preferredTerminal") {
            let normalized = CodexTerminalApplication.resolve(title: value).title
            if value != normalized { defaults.set(normalized, forKey: prefix + "preferredTerminal") }
        }
    }

    @MainActor
    private func monitor() -> CodexUsageMonitor {
        if let storedMonitor { return storedMonitor }
        let value = CodexUsageMonitor(widgetId: id)
        storedMonitor = value
        return value
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(CodexUsageMonitorView(
            size: size,
            isVertical: isVertical,
            widgetId: id,
            monitor: monitor()
        ))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(CodexUsageMonitorPanel(
            widgetId: id,
            monitor: monitor()
        ))
    }
}
