import SwiftUI

struct StatusDot: View {
    let status: ReadinessStatus
    var size: CGFloat = 12
    
    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

struct StatusBadge: View {
    let status: ReadinessStatus
    var label: String?
    
    var body: some View {
        HStack(spacing: 4) {
            StatusDot(status: status, size: 8)
            Text(label ?? status.label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.backgroundColor)
        .foregroundColor(status.textColor)
        .clipShape(Capsule())
    }
}

struct TrendBadge: View {
    let trend: TrendDirection
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.caption2)
            Text(trend.label)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(trend.color)
    }
}
