import SwiftUI

struct AdminPerformanceView: View {
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model = AdminPerformanceViewModel()
    @State private var month = PerformancePeriod.start(.now)

    var body: some View {
        Group {
            if isAdministrator {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        PerformanceMonthPicker(month: $month)
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Buscar por nombre o cargo…", text: $model.search).autocorrectionDisabled()
                            if !model.search.isEmpty {
                                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                    .accessibilityLabel("Borrar búsqueda")
                            }
                        }.padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                filter("Todos (\(model.employees.count))", role: nil)
                                ForEach(model.roles, id: \.self) { filter($0, role: $0) }
                            }.padding(.vertical, 2)
                        }
                        if model.loading { ProgressView("Cargando rendimiento…").padding() }
                        if let error = model.error {
                            ContentUnavailableView {
                                Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
                            } description: { Text(error) } actions: {
                                Button("Reintentar") { Task { await model.load(month: month) } }
                            }
                        } else if !model.loading && model.filtered.isEmpty {
                            ContentUnavailableView("Sin resultados", systemImage: "person.2", description: Text("No hay empleados que coincidan con la búsqueda."))
                        }
                        ForEach(model.filtered) { employee in
                            NavigationLink {
                                EmployeePerformanceDetailView(employee: employee, month: month)
                            } label: {
                                HStack(alignment: .center, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PerformanceIdentity(name: employee.nombre, role: employee.cargo)
                                        Text("\(employee.asignaciones) asignaciones")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    VStack(spacing: 8) {
                                        PerformanceRing(value: employee.compliance, compact: true)
                                        Text("Cumplimiento").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 24)
                        .frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .refreshable { await model.load(month: month) }
                .task(id: month) { await model.load(month: month) }
            } else {
                ContentUnavailableView("Acceso restringido", systemImage: "lock")
            }
        }
        .navigationTitle("Rendimiento").navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar(.hidden, for: .tabBar).tint(Brand.red)
    }

    private func filter(_ label: String, role: String?) -> some View {
        Button { model.selectedRole = role } label: {
            Text(label).font(.subheadline)
                .foregroundStyle(model.selectedRole == role ? Color(uiColor: .systemBackground) : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(model.selectedRole == role ? Color.primary : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }.buttonStyle(.plain)
        .accessibilityAddTraits(model.selectedRole == role ? .isSelected : [])
    }
}
