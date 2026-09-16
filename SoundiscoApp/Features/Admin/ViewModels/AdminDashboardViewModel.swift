import Foundation
import Combine
import Supabase

@MainActor
final class AdminDashboardViewModel: ObservableObject {
    @Published private(set) var asignaciones: [Asignacion] = []
    @Published private(set) var metricas = AdminDashboardMetrics.empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var filtro: FiltroAsignacionAdmin = .todas
    @Published var busqueda = ""

    private let client: SupabaseClient

    var asignacionesFiltradas: [Asignacion] {
        let resultado = asignacionesPorEstado
        let consulta = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else { return resultado }
        return resultado.filter {
            $0.titulo.localizedStandardContains(consulta) ||
            ($0.ubicacion?.localizedStandardContains(consulta) ?? false) ||
            $0.asignadoA.contains { $0.nombre?.localizedStandardContains(consulta) ?? false }
        }
    }

    private var asignacionesPorEstado: [Asignacion] {
        switch filtro {
        case .todas:
            return asignaciones
        case .pendientes:
            return asignaciones.filter {
                let estado = $0.estadoEfectivo()
                return estado == .pendiente || estado == .enCurso
            }
        case .vencidas:
            return asignaciones.filter { $0.estadoEfectivo() == .vencida }
        case .completadas:
            return asignaciones.filter { $0.estado == .completada }
        }
    }

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    func cargarMetricas() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resultado: [Asignacion] = try await client
                .from("asignaciones")
                .select(
                    "id,tipo_flujo,titulo,ubicacion,nivel_prioridad,instrucciones,estado,fecha_creacion,fecha_limite," +
                    "hitos_itinerario(*),asignacion_equipo(perfiles(id,nombre_completo,rol))"
                )
                .order("fecha_creacion", ascending: false)
                .execute()
                .value

            guard !Task.isCancelled else { return }
            asignaciones = resultado
            metricas = Self.calcularMetricas(resultado)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func aplicarFiltro(_ nuevoFiltro: FiltroAsignacionAdmin) {
        filtro = nuevoFiltro
    }

    private static func calcularMetricas(_ asignaciones: [Asignacion]) -> AdminDashboardMetrics {
        let asignadas = asignaciones.filter { !$0.asignadoA.isEmpty }.count
        let activas = asignaciones.filter { $0.estado == .enCurso }.count
        let completadas = asignaciones.filter { $0.estado == .completada }.count
        let tasa = asignaciones.isEmpty
            ? 0
            : Double(completadas) / Double(asignaciones.count) * 100

        return AdminDashboardMetrics(
            unidadesAsignadas: asignadas,
            unidadesActivas: activas,
            tasaEntrega: tasa
        )
    }
}
