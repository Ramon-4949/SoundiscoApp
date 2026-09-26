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
    @State private var confirmDiscard = false
    @FocusState private var focusedField: Field?
    private let initialUsername: String
    private enum Field: Hashable { case username, phone }
    private var captionColor: Color { Color(uiColor: .secondaryLabel) }
    private let positions = RegistrationViewModel().positions

    init(profile: EmployeeProfile, username: String) {
        self.profile = profile
        initialUsername = profile.nombre_usuario ?? username
        _username = State(initialValue: profile.nombre_usuario ?? username)
        _phone = State(initialValue: profile.telefono ?? "")
        _job = State(initialValue: profile.cargo ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 92, weight: .ultraLight))
                        .foregroundStyle(Color(uiColor: .systemGray3))
                        .frame(width: 112, height: 112)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                        .accessibilityHidden(true)
                        .padding(.top, 12).padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            heading("Nombre completo")
                            Spacer()
                            Label("Bloqueado", systemImage: "lock").font(.caption)
                        }.foregroundStyle(captionColor)
                        HStack(spacing: 12) {
                            Image(systemName: "person.text.rectangle")
                            Text(profile.nombre_completo ?? "No registrado")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark.shield")
                        }
                        .foregroundStyle(captionColor).padding(16)
                        .frame(minHeight: 56)
                        .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 16))
                        Label {
                            Text("El nombre completo está bloqueado por políticas de la empresa. Contacta a Recursos Humanos o IT para solicitar cambios.")
                        } icon: { Image(systemName: "info.circle") }
                        .font(.subheadline).foregroundStyle(captionColor)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    field("Nombre de usuario", error: attempted ? FormValidation.username(username) : nil) {
                        Image(systemName: "at").foregroundStyle(Brand.red)
                        TextField("Nombre de usuario", text: $username)
                            .textContentType(.username).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().focused($focusedField, equals: .username)
                            .submitLabel(.next).onSubmit { focusedField = .phone }
                        Button { username = "" } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(captionColor)
                        }.accessibilityLabel("Borrar nombre de usuario")
                    }
                    field("Teléfono", error: attempted ? FormValidation.phone(phone) : nil) {
                        Image(systemName: "phone").foregroundStyle(Brand.red)
                        TextField("Teléfono", text: $phone)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                            .focused($focusedField, equals: .phone)
                        Image(systemName: "asterisk").foregroundStyle(captionColor)
                            .accessibilityLabel("Obligatorio")
                    }
                    field("Cargo", error: attempted && !positions.contains(job) ? "Selecciona un cargo válido." : nil) {
                        Menu {
                            Picker("Cargo", selection: $job) {
                                Text("Selecciona un cargo").tag("")
                                ForEach(positions, id: \.self) { Text($0).tag($0) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "slider.horizontal.3").foregroundStyle(Brand.red)
                                Text(job.isEmpty ? "Selecciona un cargo" : job)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "chevron.down").foregroundStyle(captionColor)
                            }
                        }.accessibilityLabel("Cargo")
                    }
                    VStack(spacing: 18) {
                        Button { Task { await save() } } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Label(busy ? "Guardando…" : "Guardar Cambios", systemImage: "square.and.arrow.down")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .foregroundStyle(.white)
                            .background(Brand.red, in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Brand.red.opacity(0.18), radius: 10, y: 6)
                        }
                        Button("Descartar Cambios", action: requestClose)
                            .frame(minHeight: 44)
                    }.padding(.top, 40)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestClose) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Volver")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { focusedField = nil }
                }
            }
            .disabled(busy).interactiveDismissDisabled(busy || hasUnsavedChanges)
            .confirmationDialog("¿Descartar los cambios?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Descartar cambios", role: .destructive) { dismiss() }
                Button("Seguir editando", role: .cancel) {}
            } message: { Text("Los cambios sin guardar se perderán.") }
            .alert(item: $notice) {
                Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("Entendido")))
            }
        }.tint(Brand.red)
    }

    private var hasUnsavedChanges: Bool {
        username != initialUsername || phone != (profile.telefono ?? "") || job != (profile.cargo ?? "")
    }

    private func requestClose() {
        focusedField = nil
        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
    }

    private func heading(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(captionColor)
    }

    private func field<Content: View>(_ title: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
            HStack(spacing: 12, content: content)
                .padding(16).frame(minHeight: 56)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).stroke(error == nil ? Color.clear : Brand.red, lineWidth: 1)
                }
            FieldValidationMessage(message: error)
        }
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
