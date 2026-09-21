import Foundation
import Combine
import Supabase

struct EmployeeAvailability: Decodable, Identifiable {
    let id: UUID
    let nombre: String?
    let cargo: String?
    let rol: String?
    let disponible: Bool
    let ocupadoDesde: Date?
    let ocupadoHasta: Date?

    var displayName: String { nombre?.isEmpty == false ? nombre! : "Empleado sin nombre" }
    var jobTitle: String { cargo?.isEmpty == false ? cargo! : rol == "admin" ? "Administración" : "Empleado sin cargo" }
    var initials: String { displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }

    enum CodingKeys: String, CodingKey {
        case id, nombre, cargo, rol, disponible
        case ocupadoDesde = "ocupado_desde"
        case ocupadoHasta = "ocupado_hasta"
    }
}

struct AssignmentBookingWindow: Hashable {
    let start: Date
    let end: Date
}

@MainActor
final class EmployeeSelectionViewModel: ObservableObject {
    @Published private(set) var employees: [EmployeeAvailability] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var search = ""
    @Published var category = "Todos"
    private let client: SupabaseClient
    private var requestID = UUID()

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    var categories: [String] {
        ["Todos"] + Set(employees.map(\.jobTitle)).sorted()
    }

    var filtered: [EmployeeAvailability] {
        employees.filter {
            (category == "Todos" || $0.jobTitle == category) &&
            (search.isEmpty || "\($0.displayName) \($0.jobTitle)".localizedStandardContains(search))
        }.sorted {
            if $0.disponible != $1.disponible { return $0.disponible }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func load(window: AssignmentBookingWindow, excluding: UUID?) async {
        let request = UUID()
        requestID = request
        isLoading = true
        errorMessage = nil
        defer { if requestID == request { isLoading = false } }
        do {
            var result: [EmployeeAvailability] = []
            while true {
                let page: [EmployeeAvailability] = try await client.rpc(
                    "admin_employee_availability",
                    params: AvailabilityParameters(pInicio: window.start, pFin: window.end,
                        pExcluir: excluding, pOffset: result.count)
                ).execute().value
                guard !Task.isCancelled, requestID == request else { return }
                result += page
                if page.count < 200 { break }
            }
            employees = result
            if !categories.contains(category) { category = "Todos" }
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            errorMessage = "No se pudo consultar la disponibilidad. \(error.localizedDescription)"
        }
    }

    func canConfirm(_ selected: Set<UUID>) -> Bool {
        !isLoading && errorMessage == nil && !selected.isEmpty &&
        selected.isSubset(of: Set(employees.filter(\.disponible).map(\.id)))
    }
}

private struct AvailabilityParameters: Encodable {
    let pInicio: Date
    let pFin: Date
    let pExcluir: UUID?
    let pOffset: Int
    enum CodingKeys: String, CodingKey {
        case pInicio = "p_inicio", pFin = "p_fin", pExcluir = "p_excluir", pOffset = "p_offset"
    }
}
