import AppKit
import SwiftUI

struct CodexProviderQuotaRow: View {
    let window: CodexQuotaWindow
    let accent: Color
    var compact = false
    @Environment(\.colorScheme) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(window.title)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                Text(CodexLocalization.text("\(Int(window.remainingPercent.rounded()))% 剩余", "\(Int(window.remainingPercent.rounded()))% remaining"))
                    .font(CodexTypography.tokenNumber(size: compact ? 9.5 : 10.5, weight: .bold))
                    .foregroundStyle(accent)
                    .fixedSize()
                Spacer(minLength: 4)
                if window.resetAt != nil {
                    Text(window.resetDescription())
                        .font(.system(size: compact ? 8 : 8.5, weight: .medium))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(appearance == .dark ? 0.10 : 0.075))
                    Capsule().fill(accent).frame(width: proxy.size.width * window.remainingRatio)
                    if !compact {
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                Spacer()
                                Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.88)).frame(width: 1.5)
                            }
                            Spacer()
                        }
                    }
                }
            }.frame(height: compact ? 6 : 7)
            if !compact || window.resetAt != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(compact
                        ? CodexLocalization.text("重置时间", "Resets at")
                        : CodexLocalization.text("已用 \(Int(window.usedPercent.rounded()))%", "\(Int(window.usedPercent.rounded()))% used"))
                    Spacer(minLength: 4)
                    if let resetAt = window.resetAt {
                        Text(resetAt.codexShortTime)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: compact ? 8 : 8.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }
}
