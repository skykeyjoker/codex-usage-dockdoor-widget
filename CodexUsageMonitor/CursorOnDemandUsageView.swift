import SwiftUI

/// Shared by the overview and Cursor quota detail so supplementary usage stays in sync.
struct CursorOnDemandUsageView: View {
    let snapshot: CursorUsageSnapshot
    let accent: Color
    var compact = false
    @Environment(\.codexCurrencyContext) private var currencyContext

    var body: some View {
        let limit = snapshot.onDemandLimitUSD ?? 0
        let ratio = limit > 0 ? min(1, max(0, snapshot.onDemandUsedUSD / limit)) : 0
        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Label(CodexLocalization.text("额外用量", "On-demand usage"), systemImage: "creditcard.fill")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .bold))
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule().fill(accent).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: compact ? 6 : 7)
            HStack {
                Text(limit > 0
                    ? "\(currencyContext.formatUSD(snapshot.onDemandUsedUSD)) / \(currencyContext.formatUSD(limit))"
                    : currencyContext.formatUSD(snapshot.onDemandUsedUSD))
                Spacer()
                if limit > 0 {
                    Text(CodexLocalization.text(
                        "已使用 \(Int((ratio * 100).rounded()))%",
                        "\(Int((ratio * 100).rounded()))% used"
                    ))
                }
            }
            .font(CodexTypography.tokenNumber(size: compact ? 9 : 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            if let personal = snapshot.personalOnDemandUsedUSD {
                Text(CodexLocalization.text(
                    "当前账户个人用量：\(currencyContext.formatUSD(personal))",
                    "Personal usage for this account: \(currencyContext.formatUSD(personal))"
                ))
                    .font(.system(size: compact ? 8 : 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
