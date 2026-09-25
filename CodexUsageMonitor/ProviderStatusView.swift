import SwiftUI
import AppKit

/// Every service uses the same card shell, status rows and action footer.
struct ProviderStatusView: View {
    let provider: UsageProvider
    let status: ProviderServiceStatus?
    let error: String?
    var showSummary = true
    var showActions = true
    let refresh: () -> Void
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var accent: Color {
        switch provider {
        case .codex: return .blue
        case .claude: return ClaudeUsagePanelView.accent(for: appearance)
        case .cursor: return .teal
        }
    }
    private var title: String { provider == .codex ? "OpenAI" : provider.title }
    private var indicator: OpenAIServiceIndicator { error == nil ? status?.indicator ?? .unknown : .unknown }
    private var statusLabel: String {
        if error != nil { return CodexLocalization.text("更新失败", "Update failed") }
        return status?.indicator.label ?? CodexLocalization.text("读取中", "Loading")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CodexGlassDivider()
            if let status {
                let preview = status.previewComponents
                let components = expanded ? status.components : preview
                VStack(spacing: 0) {
                    ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                        componentRow(component)
                        if index < components.count - 1 { CodexGlassDivider().padding(.leading, 26) }
                    }
                }
                if !status.components.isEmpty {
                    CodexGlassDivider()
                    HStack {
                        Text(CodexLocalization.text("\(status.components.count) 项服务", "\(status.components.count) services"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if status.components.count > preview.count {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { expanded.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(expanded ? CodexLocalization.text("收起", "Show less") : CodexLocalization.text("展开全部", "Show all"))
                                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                }
                            }.buttonStyle(.plain).foregroundStyle(accent)
                        }
                    }.font(.system(size: 9, weight: .medium)).padding(.horizontal, 12).frame(height: 32)
                }
                ForEach(status.incidents) { incident in
                    Label(incident.name, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true).padding(12)
                }
            } else if error == nil {
                HStack { ProgressView().controlSize(.small); Text(CodexLocalization.text("正在获取官方状态…", "Fetching official status…")) }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(16)
            }
            if let error {
                VStack(alignment: .leading, spacing: 4) {
                    if status != nil { Text(CodexLocalization.text("当前显示上次获取的数据", "Showing the last received status")) }
                    Text(error).lineLimit(3)
                }.font(.system(size: 9)).foregroundStyle(.orange).padding(12)
            }
            if showActions {
                CodexGlassDivider()
                HStack {
                    Button(action: refresh) { Label(CodexLocalization.text("刷新", "Refresh"), systemImage: "arrow.clockwise") }
                    Spacer()
                    Button { NSWorkspace.shared.open(provider.statusURL) } label: {
                        Label(CodexLocalization.text("官方状态页", "Official status page"), systemImage: "arrow.up.right.square")
                    }
                }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).frame(height: 38)
            }
        }.background(CodexGlassCard(cornerRadius: 11))
    }

    private var header: some View {
        HStack(spacing: 9) {
            CodexProviderIcon(brand: provider.brand, size: 17, color: accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(status.map { CodexLocalization.text("更新于 \($0.fetchedAt.formatted(date: .omitted, time: .shortened))", "Updated \($0.fetchedAt.formatted(date: .omitted, time: .shortened))") }
                    ?? CodexLocalization.text("官方服务状态", "Official service status"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if showSummary {
                HStack(spacing: 5) {
                    Circle().fill(indicator.color(for: appearance)).frame(width: 6, height: 6)
                    Text(statusLabel).foregroundStyle(.secondary)
                }.font(.system(size: 9, weight: .medium))
            }
        }.padding(12)
    }

    private func componentRow(_ component: OpenAIStatusComponent) -> some View {
        HStack(spacing: 8) {
            Circle().fill(component.indicator.color(for: appearance)).frame(width: 6, height: 6)
            Text(component.name).font(.system(size: 10, weight: .medium)).lineLimit(1).help(component.name)
            Spacer(minLength: 4)
            Text(component.indicator.label).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
        }.padding(.horizontal, 12).frame(height: 29)
    }
}
