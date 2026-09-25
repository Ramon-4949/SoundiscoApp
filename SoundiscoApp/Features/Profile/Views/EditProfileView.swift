import SwiftUI
import Supabase

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: SessionViewModel
    let profile: EmployeeProfile
    @State private var username: String
    @State private var phone: String
    @State private var job: String
    @State private var busy = false
    @State private var attempted = false
    @State private var notice: AuthNotice?
    private let positions = RegistrationViewModel().positions

    init(profile: EmployeeProfile, username: String) {
        self.profile = profile
        _username = State(initialValue: profile.nombre_usuario ?? username)
        _phone = State(initialValue: profile.telefono ?? "")
        _job = State(initialValue: profile.cargo ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AuthField(title: "Nombre completo", icon: "person", placeholder: "",
                              text: .constant(profile.nombre_completo ?? ""), capitalization: .words)
                        .disabled(true)
                    AuthField(title: "Nombre de usuario", icon: "at", placeholder: "usuario",
                              text: $username, error: attempted ? FormValidation.username(username) : nil)
                    AuthField(title: "Teléfono", icon: "phone", placeholder: "809-555-0100",
                              text: $phone, keyboard: .phonePad,
                              error: attempted ? FormValidation.phone(phone) : nil)
                    Picker("Cargo", selection: $job) {
                        Text("Selecciona un cargo").tag("")
                        ForEach(positions, id: \.self) { Text($0).tag($0) }
                    }
                    .validationBorder(attempted && !positions.contains(job) ? "Selecciona un cargo válido." : nil)
                    FieldValidationMessage(message: attempted && !positions.contains(job) ? "Selecciona un cargo válido." : nil)
                }
                if busy { ProgressView("Guardando…") }
            }
            .navigationTitle("Editar perfil").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await save() } }.disabled(busy) }
            }
            .disabled(busy).interactiveDismissDisabled(busy)
            .alert(item: $notice) {
                Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("Entendido")))
            }
        }.tint(Brand.red)
    }

    private func save() async {
        guard !busy else { return }
        attempted = true
        guard FormValidation.username(username) == nil, FormValidation.phone(phone) == nil,
              positions.contains(job) else { return }
        busy = true
        defer { busy = false }
        do {
            try await SupabaseService.client.rpc("update_my_profile", params: [
                "p_username": username.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_job": job
            ]).execute()
            await auth.refreshProfileIdentity()
            dismiss()
        } catch { notice = .failure(error) }
    }
}

