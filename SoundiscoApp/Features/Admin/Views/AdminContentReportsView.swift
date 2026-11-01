import SwiftUI
import Supabase

private struct ContentReport: Decodable, Identifiable {
    let id: UUID
    let note_id: UUID
    let reason: String
    let created_at: Date
    let contenido: String
    let asignacion: String

    var reasonLabel: String {
        switch reason {
        case "acoso": "Acoso"
        case "contenido_inapropiado": "Contenido inapropiado"
        case "datos_personales": "Datos personales"
        default: "Otro motivo"
        }
    }
}

struct AdminContentReportsView: View {
    @State private var reports: [ContentReport] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var notice: AuthNotice?
    @State private var removing: ContentReport?

    var body: some View {
        List {
            if loading && reports.isEmpty { ProgressView("Cargando reportes…") }
            if !loading && reports.isEmpty {
                ContentUnavailableView("Sin reportes pendientes", systemImage: "checkmark.shield")
            }
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.asignacion).font(.headline)
                    Label(report.reasonLabel, systemImage: "flag").font(.caption).foregroundStyle(.secondary)
                    Text(report.contenido).textSelection(.enabled)
                    Text(report.created_at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Retirar nota", systemImage: "trash", role: .destructive) { removing = report }
                        Spacer()
                        Button("Marcar revisado", systemImage: "checkmark") {
                            Task { await resolve(report, remove: false) }
                        }
                    }.buttonStyle(.borderless).disabled(loading)
                }.padding(.vertical, 8)
            }
            if hasMore {
                Button("Cargar más", systemImage: "arrow.down") { Task { await load(reset: false) } }
                    .disabled(loading)
            }
        }
        .navigationTitle("Reportes de contenido")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .task { await load() }
        .refreshable { await load() }
        .alert(item: $notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Aceptar")))
        }
        .confirmationDialog("¿Retirar la nota reportada?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let report = removing {
                Button("Retirar nota", role: .destructive) { Task { await resolve(report, remove: true) } }
            }
            Button("Cancelar", role: .cancel) { removing = nil }
        }
    }

    private func load(reset: Bool = true) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page: [ContentReport] = try await SupabaseService.client.rpc("admin_note_reports",
                params: ["p_offset": reset ? 0 : reports.count]).execute().value
            reports = reset ? page : reports + page
            hasMore = page.count == 50
        } catch { notice = .failure(error) }
    }

    private func resolve(_ report: ContentReport, remove: Bool) async {
        guard !loading else { return }
        loading = true
        do {
            if remove {
                try await SupabaseService.client.rpc("admin_remove_assignment_note",
                    params: ["p_note_id": report.note_id.uuidString]).execute()
            } else {
                try await SupabaseService.client.rpc("admin_resolve_note_report",
                    params: ["p_report_id": report.id.uuidString]).execute()
            }
        } catch { notice = .failure(error) }
        loading = false
        await load()
    }
}
