import SwiftUI

struct AdminMessageComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminMessageViewModel()
    @State private var asunto = ""
    @State private var cuerpo = ""
    @State private var alertMessage: String?
    @FocusState private var focused: Field?
    let onComplete: () -> Void

    private enum Field { case asunto, cuerpo }

    var body: some View {
        Form {
            Section("Asunto del comunicado") {
                TextField("Asunto", text: $asunto)
                    .focused($focused, equals: .asunto)
            }

            Section {
                TextEditor(text: $cuerpo)
                    .frame(minHeight: 180)
                    .focused($focused, equals: .cuerpo)
                Text("\(cuerpo.count) caracteres")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } header: {
                Text("Mensaje")
            } footer: {
                Text("El comunicado será visible para toda la plantilla y no admite respuestas.")
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading { ProgressView().tint(.white) }
                        Label(model.isLoading ? "Publicando…" : "Publicar comunicado", systemImage: "paperplane.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canPublish || model.isLoading)
                .listRowBackground(canPublish ? Color(red: 0.76, green: 0, blue: 0.09) : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(canPublish ? Color.white : Color.secondary)
            }
        }
        .navigationTitle("Crear comunicado")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .alert("No se pudo publicar", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
    }

    private var canPublish: Bool {
        !asunto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cuerpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func publish() async {
        focused = nil
        do {
            _ = try await model.publishMessage(MensajeDraft(asunto: asunto, cuerpoMensaje: cuerpo))
            onComplete()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
