import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy = "PrivacyPolicy"
    case terms = "TermsOfService"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .privacy: "Política de privacidad"
        case .terms: "Términos de servicio"
        }
    }

    var content: String? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            if let content = document.content {
                Text(content)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ContentUnavailableView("No se pudo abrir el documento", systemImage: "doc.text")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
    }
}

struct LegalDocumentSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalDocumentView(document: document)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
        }
    }
}
