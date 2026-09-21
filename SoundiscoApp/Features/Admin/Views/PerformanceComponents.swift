import SwiftUI

struct PerformanceRing: View {
    let value: Double?
    var compact = false
    var body: some View {
        ZStack {
            Circle().stroke(Brand.red.opacity(0.12), lineWidth: compact ? 4 : 12)
            Circle().trim(from: 0, to: min(1, max(0, value ?? 0)))
                .stroke(Brand.red, style: StrokeStyle(lineWidth: compact ? 4 : 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value.map { "\(Int(($0 * 100).rounded()))\(compact ? "" : "%")" } ?? "—")
                    .font(compact ? .headline : .largeTitle.bold()).monospacedDigit()
                if !compact {
                    Text(value == nil ? "SIN DATOS" : "CUMPLIMIENTO")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: compact ? 44 : 132, height: compact ? 44 : 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cumplimiento")
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) por ciento" } ?? "Sin datos")
    }
}

struct PerformanceIdentity: View {
    let name: String
    let role: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 48)).foregroundStyle(.tertiary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(role).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct PerformanceMonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .accessibilityLabel("Mes anterior")
            Spacer()
            Text(PerformancePeriod.label(month)).font(.subheadline.weight(.medium))
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .accessibilityLabel("Mes siguiente")
                .disabled(month >= PerformancePeriod.start(.now))
        }.tint(Brand.red)
    }
    private func shift(_ amount: Int) {
        if let next = PerformancePeriod.calendar.date(byAdding: .month, value: amount, to: month) { month = next }
    }
}

struct PerformanceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) {
                Capsule().fill(Brand.red).frame(width: 5, height: 16)
                Text(title).font(.headline)
            }
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
