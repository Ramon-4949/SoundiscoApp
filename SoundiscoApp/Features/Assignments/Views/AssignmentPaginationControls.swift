import SwiftUI

struct AssignmentPaginationControls: View {
    let pageIndex: Int
    let hasMore: Bool
    let loading: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: previous) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(pageIndex == 0 || loading)
                .accessibilityLabel("Página anterior").help("Página anterior")
            Spacer(minLength: 0)
            Text("Página \(pageIndex + 1)").font(.subheadline).monospacedDigit()
                .accessibilityAddTraits(.updatesFrequently)
            if loading { ProgressView().controlSize(.small).frame(width: 18) }
            Spacer(minLength: 0)
            Button(action: next) { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(!hasMore || loading)
                .accessibilityLabel("Página siguiente").help("Página siguiente")
        }
        .buttonStyle(.bordered)
        .tint(Brand.red)
        .accessibilityElement(children: .contain)
    }
}
