import AppKit
import SwiftUI

struct ClaudeUsagePanelView: View {
    let snapshot: ClaudeUsageSnapshot?
    let error: String?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    var localUsage: ClaudeLocalUsageSnapshot? = nil
    var localError: String? = nil
    var isRefreshingLocal = false
    @Environment(\.colorScheme) private var appearance
    private var accent: Color { Self.accent(for: appearance) }

    static func accent(for appearance: ColorScheme) -> Color {
        appearance == .dark
            ? Color(red: 0.78, green: 0.53, blue: 0.41)
            : Color(red: 0.78, green: 0.43, blue: 0.30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                accountCard(snapshot)
                if let error {
                    Label(CodexLocalization.text("当前显示上次成功更新的数据：", "Showing the last successful reading: ") + error,
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .padding(9).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
                quotaCard(snapshot)
            } else if let error {
                VStack(spacing: 10) {
                    CodexProviderIcon(brand: .claude, size: 30, color: accent)
                    Text(CodexLocalization.text("无法读取 Claude 额度", "Unable to load Claude quota"))
                        .font(.system(size: 13, weight: .bold))
                    Text(error).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button(CodexLocalization.text("重试", "Retry"), action: onRefresh).disabled(isRefreshing)
                }.frame(maxWidth: .infinity).padding(16).background(CodexGlassCard(cornerRadius: 13))
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(CodexLocalization.text("正在读取 Claude 额度…", "Loading Claude quota…"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(16).background(CodexGlassCard(cornerRadius: 13))
            }
            ClaudeLocalUsageView(snapshot: localUsage, error: localError, isRefreshing: isRefreshingLocal)
            if let snapshot { sourceFooter(snapshot) }
        }
    }

    private func accountCard(_ snapshot: ClaudeUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.14))
                .overlay { CodexProviderIcon(brand: .claude, size: 18, color: accent) }
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.accountEmail ?? CodexLocalization.text("Claude 账户", "Claude account"))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(snapshot.plan?.capitalized ?? "Claude") · " + CodexLocalization.text("\(snapshot.fetchedAt.codexRelativeText)更新", "updated \(snapshot.fetchedAt.codexRelativeText)"))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { open("https://claude.ai/settings/usage") } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).foregroundStyle(accent)
                .help(CodexLocalization.text("打开 Claude 用量页面", "Open Claude usage dashboard"))
        }.padding(10).background(CodexGlassCard())
    }

    private func quotaCard(_ snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(CodexLocalization.text("Claude 额度", "Claude quotas"), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.plan?.capitalized ?? "—").font(.system(size: 8.5, weight: .medium)).foregroundStyle(.tertiary)
            }.padding(.bottom, 6)
            ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    Divider().opacity(appearance == .dark ? 0.22 : 0.32).padding(.vertical, 8)
                }
                CodexProviderQuotaRow(window: window, accent: accent)
            }
        }.padding(11).background(CodexGlassCard(cornerRadius: 13))
    }

    private func sourceFooter(_ snapshot: ClaudeUsageSnapshot) -> some View {
        HStack(spacing: 12) {
            Label(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened) + " · Claude Code " + CodexLocalization.text("只读", "read-only"), systemImage: "checkmark.circle")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                .help(CodexLocalization.text("订阅额度来自账户接口；Token 与费用估算来自本机日志", "Subscription quota from account API; tokens and estimated cost from local logs"))
            Spacer()
            Button { open("https://status.claude.com") } label: { Image(systemName: "waveform.path.ecg") }
                .buttonStyle(.plain)
                .modifier(CodexFooterActionHover(testingID: "claude-status",
                    help: CodexLocalization.text("打开 Claude 官方状态页", "Open official Claude status page"), accent: accent, restingColor: .secondary, tipAlignment: .top))
            Button(action: onRefresh) {
                if isRefreshing { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise") }
            }.buttonStyle(.plain).disabled(isRefreshing)
                .modifier(CodexFooterActionHover(testingID: "claude-refresh",
                    help: CodexLocalization.text("立即刷新 Claude 额度", "Refresh Claude quota now"), accent: accent, restingColor: .secondary, tipAlignment: .topTrailing))
        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
