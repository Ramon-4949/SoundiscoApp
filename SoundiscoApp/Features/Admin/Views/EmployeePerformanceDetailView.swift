import SwiftUI
import Charts

struct EmployeePerformanceDetailView: View {
    let employee: EmployeePerformance
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model = AdminPerformanceViewModel()
    @State private var month: Date

    init(employee: EmployeePerformance, month: Date) {
        self.employee = employee
        _month = State(initialValue: month)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isAdministrator {
                    PerformanceMonthPicker(month: $month)
                    PerformanceIdentity(name: employee.nombre, role: employee.cargo)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    if model.loading { ProgressView("Actualizando métricas…") }
                    if let error = model.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await reload() } }
                    } else if let current = model.employees.first {
                        PerformanceDetailContent(employee: current)
                    } else if !model.loading {
                        ContentUnavailableView("Sin datos", systemImage: "chart.bar", description: Text("El empleado ya no está disponible para consulta."))
                    }
                } else { ContentUnavailableView("Acceso restringido", systemImage: "lock") }
            }.padding(.horizontal, 18).padding(.bottom, 28)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Detalle de rendimiento").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar).tint(Brand.red)
        .task(id: month) { if isAdministrator { await reload() } }
        .refreshable { if isAdministrator { await reload() } }
    }

    private func reload() async { await model.load(month: month, employeeID: employee.id) }
}

struct PerformanceDetailContent: View {
    let employee: EmployeePerformance
    var body: some View {
        VStack(spacing: 20) {
            PerformanceSection(title: "Puntualidad de Hitos") {
                PerformanceRing(value: employee.compliance)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                VStack(spacing: 12) {
                    metric("Temprano", value: employee.temprano, color: .blue)
                    metric("A tiempo", value: employee.a_tiempo, color: Brand.red)
                    metric("Tardío", value: employee.tardio, color: .orange)
                    metric("Sin confirmar · plazo cerrado", value: employee.sin_confirmar, color: .secondary)
                    Divider()
                    HStack {
                        Label("Retraso medio tras tolerancia", systemImage: "clock")
                        Spacer()
                        Text(employee.retraso_medio_minutos.map { String(format: "%.1f min", $0) } ?? "—")
                            .fontWeight(.semibold).foregroundStyle(Brand.red)
                    }.font(.caption)
                }
            }
            PerformanceSection(title: "Proactividad y Reportes") {
                Text("\(employee.noteCount) notas e incidencias en el mes")
                    .font(.subheadline).foregroundStyle(.secondary)
                Chart(employee.notas_semanales) { week in
                    BarMark(x: .value("Semana", "S\(week.semana)"), y: .value("Notas", week.cantidad), width: .ratio(0.55))
                        .foregroundStyle(week.semana == employee.notas_semanales.last(where: { $0.cantidad > 0 })?.semana ? Brand.red : Brand.red.opacity(0.22))
                        .cornerRadius(5)
                        .annotation(position: .top) {
                            Text("\(week.cantidad)").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Semana \(week.semana)")
                        .accessibilityValue("\(week.cantidad) notas")
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...max(1, (employee.notas_semanales.map(\.cantidad).max() ?? 0) + 1))
                .frame(height: 145)
            }
            PerformanceSection(title: "Carga de Trabajo Mensual") {
                Text("\(employee.asignaciones) asignaciones en el período")
                    .font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(Brand.red).frame(width: segment(employee.completadas, width: geometry.size.width))
                        Rectangle().fill(.orange).frame(width: segment(employee.activas, width: geometry.size.width))
                        Rectangle().fill(.gray).frame(width: segment(employee.vencidas, width: geometry.size.width))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemFill)).clipShape(Capsule())
                }.frame(height: 10).accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { workloadLegend }
                    VStack(alignment: .leading, spacing: 12) { workloadLegend }
                }
            }
        }
    }

    private func segment(_ count: Int, width: CGFloat) -> CGFloat {
        employee.asignaciones == 0 ? 0 : width * CGFloat(count) / CGFloat(employee.asignaciones)
    }

    @ViewBuilder private var workloadLegend: some View {
        legend("Completadas", value: employee.completadas, color: Brand.red)
        legend("Activas", value: employee.activas, color: .orange)
        legend("Vencidas", value: employee.vencidas, color: .gray)
    }

    private func legend(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(value)").font(.headline).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text("\(value) hitos").fontWeight(.semibold).monospacedDigit()
        }.font(.subheadline)
    }
}

#Preview("Métricas") {
    ScrollView {
        PerformanceDetailContent(employee: EmployeePerformance(id: UUID(), nombre: "José Carlos Santana", cargo: "Técnico de pantalla",
            temprano: 12, a_tiempo: 34, tardio: 3, sin_confirmar: 1, retraso_medio_minutos: 4.5,
            notas_semanales: [PerformanceWeek(semana: 1, cantidad: 3), PerformanceWeek(semana: 2, cantidad: 5),
                PerformanceWeek(semana: 3, cantidad: 4), PerformanceWeek(semana: 4, cantidad: 6)],
            asignaciones: 18, completadas: 16, activas: 1, vencidas: 1)).padding(18)
    }.background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Sin actividad · Oscuro") {
    ScrollView {
        PerformanceDetailContent(employee: EmployeePerformance(id: UUID(), nombre: "Sin actividad", cargo: "Técnico",
            temprano: 0, a_tiempo: 0, tardio: 0, sin_confirmar: 0, retraso_medio_minutos: nil,
            notas_semanales: [PerformanceWeek(semana: 1, cantidad: 0)], asignaciones: 0, completadas: 0, activas: 0, vencidas: 0)).padding(18)
    }.background(Color(uiColor: .systemGroupedBackground)).preferredColorScheme(.dark)
}
