import SwiftUI
import Charts

struct AdminDashboardView: View {
    @StateObject private var model: AdminDashboardViewModel
    @State private var searching = false
    @State private var showingCreation = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let nombre: String
    private let onCreateAssignment: (() -> Void)?

    init(nombre: String, model: AdminDashboardViewModel? = nil, onCreateAssignment: (() -> Void)? = nil) {
        self.nombre = nombre
        self.onCreateAssignment = onCreateAssignment
        _model = StateObject(wrappedValue: model ?? AdminDashboardViewModel())
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AgendaHomeHeader(name: nombre, searching: $searching)
                    if searching { AgendaSearchField(text: $model.busqueda) }
                    metrics
                    Button {
                        if let onCreateAssignment { onCreateAssignment() }
                        else { showingCreation = true }
                    } label: {
                        Label("Crear Nueva Asignación", systemImage: "plus.circle")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Brand.red, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Brand.red.opacity(0.18), radius: 8, y: 5)
                    ViewThatFits(in: .horizontal) {
                        HStack { sectionTitle; Spacer(); showAll }
                        VStack(alignment: .leading, spacing: 8) { sectionTitle; showAll }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FiltroAsignacionAdmin.allCases, id: \.self) { filter in
                                AgendaFilterPill(title: filter.title, selected: model.filtro == filter) { model.filtro = filter }
                            }
                        }
                    }
                    if model.isLoading && model.asignaciones.isEmpty {
                        ProgressView("Cargando asignaciones…").frame(maxWidth: .infinity).padding(30)
                    }
                    if let error = model.errorMessage {
                        ContentUnavailableView {
                            Label("No se pudo actualizar el panel", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) } actions: {
                            Button("Reintentar") { Task { await model.cargarMetricas() } }
                        }
                    } else if !model.isLoading && model.asignacionesFiltradas.isEmpty {
                        ContentUnavailableView("Sin asignaciones", systemImage: "tray",
                            description: Text("No hay asignaciones que coincidan con los filtros actuales."))
                    }
                    LazyVStack(spacing: 14) {
                        ForEach(model.asignacionesFiltradas) { assignment in
                            NavigationLink {
                                AssignmentDetailView(assignment: Assignment(assignment), allowsChecklistUpdates: false)
                                    .toolbar(.visible, for: .navigationBar)
                            } label: {
                                AssignmentCard(assignment: Assignment(assignment), now: context.date)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await model.cargarMetricas() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Brand.red)
        .onChange(of: searching) { _, visible in if !visible { model.busqueda = "" } }
        .task { await model.cargarMetricas() }
        .sheet(isPresented: $showingCreation) {
            NavigationStack {
                AdminCreationTypeView {
                    showingCreation = false
                    Task { await model.cargarMetricas() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { showingCreation = false }
                    }
                }
            }
        }
    }

    private var sectionTitle: some View { Text("Asignaciones Actuales").font(.title3.bold()) }
    private var showAll: some View {
        Button("Ver todas (\(model.asignaciones.count))") {
            model.filtro = .todas
            model.busqueda = ""
        }.font(.subheadline.weight(.medium))
    }

    private var metrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout { metric(highlighted: false); metric(highlighted: true) }
    }

    private func metric(highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: highlighted ? "bolt.fill" : "checklist")
                    .font(.title3).frame(width: 38, height: 38)
                    .background(highlighted ? Color.white.opacity(0.15) : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 4)
                Text(highlighted ? "Activo" : "+\(count(daysAgo: 0)) Hoy").font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(highlighted ? Color.white.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(highlighted ? model.metricas.unidadesActivas : model.metricas.unidadesAsignadas, format: .number)
                    .font(.largeTitle.bold()).monospacedDigit()
                Text(highlighted ? "en curso" : "unidades").font(.caption)
            }
            Text(highlighted ? "En Progreso" : "Asignadas").font(.subheadline)
            if highlighted {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Tasa de entrega"); Spacer(minLength: 4); deliveryRate }
                    VStack(alignment: .leading) { Text("Tasa de entrega"); deliveryRate }
                }.font(.caption).frame(minHeight: 28)
            } else {
                Chart(0..<7, id: \.self) { day in
                    LineMark(x: .value("Día", day), y: .value("Asignaciones", count(daysAgo: 6 - day)))
                        .foregroundStyle(Brand.red.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 28)
                .accessibilityLabel("Asignaciones creadas durante los últimos siete días")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(highlighted ? Brand.red : Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var deliveryRate: some View {
        Text((model.metricas.tasaEntrega / 100).formatted(.percent.precision(.fractionLength(1)))).fontWeight(.semibold)
    }

    private func count(daysAgo: Int) -> Int {
        guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) else { return 0 }
        return model.asignaciones.filter { Calendar.current.isDate($0.fechaCreacion, inSameDayAs: date) }.count
    }
}

private extension FiltroAsignacionAdmin {
    var title: String {
        switch self {
        case .todas: "Todas"
        case .pendientes: "Pendientes"
        case .vencidas: "Vencidas"
        case .completadas: "Completadas"
        }
    }
}
