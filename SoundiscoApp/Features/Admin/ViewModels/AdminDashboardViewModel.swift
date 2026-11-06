import Foundation
import Combine
import Supabase

@MainActor
final class AdminDashboardViewModel: ObservableObject {
    @Published private(set) var asignaciones: [Asignacion] = []
    @Published private(set) var metricas = AdminDashboardMetrics.empty
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var pageIndex = 0
    @Published private(set) var errorMessage: String?
    @Published var filtro: FiltroAsignacionAdmin = .pendientes
    @Published var busqueda = ""

    private let client: SupabaseClient
    private let pageSize = 10
    private var nextOffset: Int?
    private var generation = 0
    private var searchTask: Task<Void, Never>?
    private var failedOffset: Int?

    var asignacionesFiltradas: [Asignacion] { asignaciones }

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    func cargarMetricas() async {
        failedOffset = nil
        generation += 1
        let run = generation
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer { if generation == run { isLoading = false } }

        do {
            async let summaryRequest: DashboardSummaryResponse = client
                .rpc("admin_dashboard_summary")
                .execute().value
            async let pageRequest = fetchPage(offset: pageIndex * pageSize)
            let (summary, page) = try await (summaryRequest, pageRequest)
            guard !Task.isCancelled, generation == run else { return }
            metricas = summary.metrics
            apply(page)
        } catch {
            guard !Task.isCancelled, generation == run else { return }
            errorMessage = AuthNotice.failure(error).message
        }
    }

    func aplicarFiltro(_ nuevoFiltro: FiltroAsignacionAdmin) async {
        searchTask?.cancel()
        filtro = nuevoFiltro
        await reloadAssignments()
    }

    func actualizarBusqueda() async {
        await reloadAssignments()
    }

    func programarBusqueda() {
        searchTask?.cancel()
        generation += 1
        asignaciones = []
        pageIndex = 0
        hasMore = false
        failedOffset = nil
        errorMessage = nil
        isLoading = true
        isLoadingMore = false
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.actualizarBusqueda()
        }
    }

    func cargarSiguientePagina() async {
        guard hasMore, let offset = nextOffset else { return }
        await cargarPagina(offset: offset)
    }

    func cargarPaginaAnterior() async {
        guard pageIndex > 0 else { return }
        await cargarPagina(offset: (pageIndex - 1) * pageSize)
    }

    func reintentar() async {
        if let failedOffset { await cargarPagina(offset: failedOffset) }
        else { await cargarMetricas() }
    }

    private func cargarPagina(offset: Int) async {
        guard !isLoading, !isLoadingMore else { return }
        let run = generation
        isLoadingMore = true
        errorMessage = nil
        defer { if generation == run { isLoadingMore = false } }
        do {
            let page = try await fetchPage(offset: offset)
            guard !Task.isCancelled, generation == run else { return }
            apply(page)
            pageIndex = offset / pageSize
            failedOffset = nil
        } catch {
            guard !Task.isCancelled, generation == run else { return }
            failedOffset = offset
            errorMessage = AuthNotice.failure(error).message
        }
    }

    private func reloadAssignments() async {
        generation += 1
        let run = generation
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        asignaciones = []
        pageIndex = 0
        hasMore = false
        failedOffset = nil
        defer { if generation == run { isLoading = false } }
        do {
            let page = try await fetchPage(offset: 0)
            guard !Task.isCancelled, generation == run else { return }
            apply(page)
        } catch {
            guard !Task.isCancelled, generation == run else { return }
            errorMessage = AuthNotice.failure(error).message
        }
    }

    private func fetchPage(offset: Int) async throws -> DashboardAssignmentsPage {
        try await client.rpc("admin_assignments_page", params: DashboardPageRequest(
            pOffset: offset,
            pLimit: pageSize,
            pEstado: filtro.rawValue,
            pBusqueda: busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        )).execute().value
    }

    private func apply(_ page: DashboardAssignmentsPage) {
        asignaciones = page.items
        hasMore = page.hasMore
        nextOffset = page.nextOffset
    }
}

nonisolated private struct DashboardSummaryResponse: Decodable {
    let total: Int
    let unidadesAsignadas: Int
    let unidadesActivas: Int
    let tasaEntrega: Double
    let creadasUltimos7Dias: [Int]

    enum CodingKeys: String, CodingKey {
        case total
        case unidadesAsignadas = "unidades_asignadas"
        case unidadesActivas = "unidades_activas"
        case tasaEntrega = "tasa_entrega"
        case creadasUltimos7Dias = "creadas_ultimos_7_dias"
    }

    var metrics: AdminDashboardMetrics {
        AdminDashboardMetrics(
            total: total,
            unidadesAsignadas: unidadesAsignadas,
            unidadesActivas: unidadesActivas,
            tasaEntrega: tasaEntrega,
            creadasUltimos7Dias: creadasUltimos7Dias
        )
    }
}

nonisolated private struct DashboardAssignmentsPage: Decodable {
    let items: [Asignacion]
    let hasMore: Bool
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }
}

nonisolated private struct DashboardPageRequest: Encodable {
    let pOffset: Int
    let pLimit: Int
    let pEstado: String
    let pBusqueda: String

    enum CodingKeys: String, CodingKey {
        case pOffset = "p_offset"
        case pLimit = "p_limit"
        case pEstado = "p_estado"
        case pBusqueda = "p_busqueda"
    }
}
