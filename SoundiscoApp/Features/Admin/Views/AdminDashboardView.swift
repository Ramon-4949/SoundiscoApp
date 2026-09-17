import SwiftUI

struct AdminDashboardView: View {
    @StateObject private var model: AdminDashboardViewModel
    @State private var searching = false
    @State private var creationSheet: CreationSheet?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let nombre: String
    private let onCreateAssignment: (() -> Void)?

    init(
        nombre: String,
        model: AdminDashboardViewModel? = nil,
        onCreateAssignment: (() -> Void)? = nil
    ) {
        self.nombre = nombre
        self.onCreateAssignment = onCreateAssignment
        _model = StateObject(wrappedValue: model ?? AdminDashboardViewModel())
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    Text("CENTRO DE ASIGNACIONES")
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                    Text("Hola, \(nombre)").font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    metrics
                    Button {
                        if let onCreateAssignment {
                            onCreateAssignment()
                        } else {
                            creationSheet = .newItem
                        }
                    } label: {
                        Label("Crear nueva asignación", systemImage: "plus.circle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.76, green: 0, blue: 0.09))
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Estado de asignación", selection: $model.filtro) {
                    ForEach(FiltroAsignacionAdmin.allCases, id: \.self) { filtro in
                        Text(filtro.titulo).tag(filtro)
                    }
                }
                .pickerStyle(.menu)

                if model.isLoading && model.asignaciones.isEmpty {
                    ProgressView("Cargando asignaciones…")
                        .frame(maxWidth: .infinity).padding()
                } else if model.asignacionesFiltradas.isEmpty && model.errorMessage == nil {
                    ContentUnavailableView(
                        model.busqueda.isEmpty ? "Sin asignaciones" : "Sin resultados",
                        systemImage: "tray",
                        description: Text("No hay asignaciones que coincidan con los filtros actuales.")
                    )
                }

                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No se pudo actualizar el panel", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await model.cargarMetricas() } }
                    }.padding(.vertical, 8)
                }

                ForEach(model.asignacionesFiltradas) { asignacion in
                    NavigationLink {
                        AssignmentDetailView(assignment: Assignment(asignacion), allowsChecklistUpdates: false)
                    } label: {
                        AdminAssignmentRow(asignacion: asignacion)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Asignaciones actuales")
                    Spacer()
                    Text(model.asignacionesFiltradas.count, format: .number)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Panel del administrador")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .searchable(text: $model.busqueda, isPresented: $searching, prompt: "Título, ubicación o responsable")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { NotificationsView() } label: {
                    NotificationBell()
                }
                Button { searching = true } label: {
                    Label("Buscar", systemImage: "magnifyingglass")
                }
            }
        }
        .task { await model.cargarMetricas() }
        .refreshable { await model.cargarMetricas() }
        .sheet(item: $creationSheet) { _ in
            NavigationStack {
                AdminCreationTypeView {
                    creationSheet = nil
                    Task { await model.cargarMetricas() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { creationSheet = nil }
                    }
                }
            }
        }
    }

    private var metrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            metric(
                title: "Asignadas", value: model.metricas.unidadesAsignadas,
                symbol: "checklist", highlighted: false
            )
            metric(
                title: "En curso", value: model.metricas.unidadesActivas,
                symbol: "bolt.fill", highlighted: true
            )
        }
    }

    private func metric(title: String, value: Int, symbol: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title3).accessibilityHidden(true)
            Text(value, format: .number).font(.largeTitle.bold()).monospacedDigit()
            Text(title).font(.subheadline.weight(.medium))
            if highlighted {
                Text("Tasa de entrega: \((model.metricas.tasaEntrega / 100).formatted(.percent.precision(.fractionLength(1))))")
                    .font(.caption)
            } else {
                Text("Con responsables").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(highlighted ? Color(red: 0.76, green: 0, blue: 0.09) : Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private enum CreationSheet: String, Identifiable {
    case newItem
    var id: String { rawValue }
}

private struct AdminAssignmentRow: View {
    let asignacion: Asignacion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(asignacion.tipoFlujo == .operacionesCampo ? "Campo" : "Administración",
                  systemImage: asignacion.tipoFlujo == .operacionesCampo ? "truck.box" : "doc.text")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(asignacion.titulo).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { priority; Spacer(); status }
                VStack(alignment: .leading, spacing: 8) { priority; status }
            }
            if asignacion.tipoFlujo == .operacionesCampo {
                if let hito = siguienteHito {
                    Label("\(hito.scheduleLabel) · \(hito.titulo)", systemImage: "clock")
                }
                if let ubicacion = asignacion.ubicacion, !ubicacion.isEmpty {
                    Label(ubicacion, systemImage: "mappin.and.ellipse")
                }
            } else if let fecha = asignacion.fechaLimite {
                Label("Vence: \(fecha.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
            } else {
                Label("Sin fecha límite", systemImage: "calendar.badge.exclamationmark")
            }
            HStack {
                Text("Ver detalle")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(Brand.red)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    private var siguienteHito: Hito? {
        let ordenados = asignacion.hitos.sorted { $0.orden < $1.orden }
        return ordenados.first { $0.estado != .completado } ?? ordenados.last
    }

    private var priority: some View {
        Label(asignacion.prioridad.rawValue.capitalized, systemImage: "flag.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
    }

    private var status: some View {
        Text(asignacion.estadoEfectivo().titulo)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension Hito {
    var scheduleLabel: String {
        fechaProgramada?.formatted(date: .abbreviated, time: .shortened)
            ?? AgendaDate.label(horaEstimada)
    }
}

private extension FiltroAsignacionAdmin {
    var titulo: String {
        switch self {
        case .todas: "Todas"
        case .pendientes: "Pendientes"
        case .vencidas: "Vencidas"
        case .completadas: "Completadas"
        }
    }
}

private extension EstadoAsignacion {
    var titulo: String {
        switch self {
        case .pendiente: "Pendiente"
        case .enCurso: "En curso"
        case .vencida: "Vencida"
        case .completada: "Completada"
        }
    }
}
