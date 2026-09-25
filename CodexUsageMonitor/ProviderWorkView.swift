import AppKit
import SwiftUI

struct ProviderWorkView: View {
    let provider: UsageProvider
    let snapshot: ProviderWorkSnapshot?
    let projects: Bool
    let configuration: CodexPanelCardConfiguration
    let refreshing: Bool
    let refresh: () -> Void
    @Environment(\.colorScheme) private var appearance
    @State private var selectedProject: String?
    @State private var copiedID: String?
    @State private var visibleLimit = 16
    private var accent: Color { provider == .claude ? ClaudeUsagePanelView.accent(for: appearance) : .teal }
    private var section: CodexPanelCustomizationSection { projects ? .projects : .conversations }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                if configuration.isVisible(projects ? .projectsSummary : .conversationSummary, in: section) {
                    HStack(spacing: 10) {
                        metric(CodexLocalization.text("本地对话", "Local conversations"), "\(snapshot.conversations.count)", "bubble.left.and.bubble.right")
                        metric(CodexLocalization.text("项目", "Projects"), "\(snapshot.projectPaths.count)", "folder")
                        metric(CodexLocalization.text("近 24 小时更新", "Updated in 24h"), "\(snapshot.conversations.filter { Date().timeIntervalSince($0.modifiedAt) < 86400 }.count)", "clock")
                    }
                }
                if configuration.isVisible(projects ? .projectsList : .conversationList, in: section) {
                    if snapshot.conversations.isEmpty {
                        Text(CodexLocalization.text("本机暂无可读取的 \(provider.title) 对话记录", "No readable local \(provider.title) conversations"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(18)
                    } else if projects, selectedProject == nil {
                        projectList(snapshot)
                    } else {
                        if let selectedProject, projects {
                            HStack {
                                Button { self.selectedProject = nil; visibleLimit = 16 } label: { Label(CodexLocalization.text("所有项目", "All projects"), systemImage: "chevron.left") }
                                Spacer()
                                Text(selectedProject.isEmpty ? CodexLocalization.text("未关联项目", "No project") : URL(fileURLWithPath: selectedProject).lastPathComponent).fontWeight(.semibold)
                            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                        }
                        conversationList(snapshot)
                    }
                }
                if configuration.isVisible(projects ? .projectsScope : .conversationFooter, in: section) {
                    HStack {
                        Text(CodexLocalization.text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))", "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"))
                        Spacer()
                        Button(action: refresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(refreshing)
                            .help(CodexLocalization.text("刷新本地记录", "Refresh local history"))
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(scopeText(snapshot)).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    if snapshot.unavailableSources > 0 {
                        Label(CodexLocalization.text("\(snapshot.unavailableSources) 个来源暂时无法读取，已显示可用记录", "\(snapshot.unavailableSources) sources unavailable; showing readable records"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text(CodexLocalization.text("正在读取本地记录…", "Reading local history…")) }
                    .font(.system(size: 11)).padding(20)
            }
        }
        .onChange(of: projects) { _, _ in selectedProject = nil; visibleLimit = 16 }
    }

    private func scopeText(_ snapshot: ProviderWorkSnapshot) -> String {
        provider == .claude
            ? CodexLocalization.text("本机 Claude Code 记录 · 最近最多 200 个会话文件；仅显示标题、项目与活动时间。恢复命令可复制到终端执行。", "Local Claude Code history · up to 200 recent session files; titles, projects and activity times. Copy a resume command to run in your terminal.")
            : CodexLocalization.text("本机 Cursor 对话索引 · 最多 500 条；上下文和代码变更为 Cursor 最近保存的值。可打开项目，并复制对话 ID 定位；不包含未同步到本机的云端对话。", "Local Cursor index · up to 500 entries; context and code changes are last saved values. Open the project or copy a conversation ID; unsynced cloud conversations are excluded.")
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(accent)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(CodexGlassCard(cornerRadius: 11))
    }

    private func projectList(_ snapshot: ProviderWorkSnapshot) -> some View {
        let groups = Dictionary(grouping: snapshot.conversations) { $0.projectPath ?? "" }
        let paths = groups.keys.sorted { (groups[$0]?.first?.modifiedAt ?? .distantPast) > (groups[$1]?.first?.modifiedAt ?? .distantPast) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(paths, id: \.self) { path in
                let conversations = groups[path] ?? []
                Button { selectedProject = path; visibleLimit = 16 } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(accent)
                            Text(conversations.first?.projectName ?? "—").fontWeight(.semibold).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.font(.system(size: 12))
                        Text(path.isEmpty ? CodexLocalization.text("独立对话", "Standalone conversations") : path)
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        HStack {
                            Text(CodexLocalization.text("\(conversations.count) 个对话", "\(conversations.count) conversations"))
                            Spacer()
                            Text(conversations.first?.modifiedAt.formatted(date: .abbreviated, time: .shortened) ?? "—")
                        }.font(.system(size: 9)).foregroundStyle(.secondary)
                    }.padding(12).background(CodexGlassCard(cornerRadius: 11)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func conversationList(_ snapshot: ProviderWorkSnapshot) -> some View {
        let records = snapshot.conversations.filter { !projects || ($0.projectPath ?? "") == selectedProject }
        return VStack(spacing: 0) {
            ForEach(Array(records.prefix(visibleLimit).enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        CodexProviderIcon(brand: provider.brand, size: 13, color: accent).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).font(.system(size: 12, weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(record.projectName + " · " + record.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        if record.isArchived { Text(CodexLocalization.text("已归档", "Archived")).font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 12) {
                        if let context = record.contextPercent { Text(CodexLocalization.text("上下文 \(Int(context.rounded()))%", "Context \(Int(context.rounded()))%")) }
                        if let added = record.linesAdded, let removed = record.linesRemoved, added > 0 || removed > 0 {
                            Text("+\(added) / −\(removed)").monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        if let path = record.projectPath {
                            Button { openProject(path) } label: { Label(CodexLocalization.text("打开项目", "Open project"), systemImage: "folder") }
                        }
                        Button { copyAction(record) } label: {
                            Label(copiedID == record.id ? CodexLocalization.text("已复制", "Copied") : provider == .claude ? CodexLocalization.text("恢复命令", "Resume command") : CodexLocalization.text("对话 ID", "Conversation ID"), systemImage: copiedID == record.id ? "checkmark" : "doc.on.doc")
                        }
                    }.font(.system(size: 9, weight: .medium)).foregroundStyle(accent).buttonStyle(.plain)
                }.padding(12)
                if index < min(records.count, visibleLimit) - 1 { CodexGlassDivider() }
            }
            if records.count > visibleLimit {
                Button(CodexLocalization.text("显示更多（还有 \(records.count - visibleLimit) 条）", "Show more (\(records.count - visibleLimit) remaining)")) { visibleLimit += 16 }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).padding(12)
            }
        }.background(CodexGlassCard(cornerRadius: 11))
    }

    private func copyAction(_ record: ProviderConversation) {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = provider == .claude ? (record.projectPath.map { "cd \(quote($0)) && " } ?? "") + "claude --resume \(quote(record.id))" : record.id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedID = record.id
    }
    private func openProject(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if provider == .cursor, let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
        } else { NSWorkspace.shared.open(url) }
    }
}
