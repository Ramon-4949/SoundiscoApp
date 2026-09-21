import Foundation
import Combine
import Supabase

@MainActor
final class AdminPerformanceViewModel: ObservableObject {
    @Published private(set) var employees: [EmployeePerformance] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published var search = ""
    @Published var selectedRole: String?
    private let client: SupabaseClient
    private var generation = 0

    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    var roles: [String] { Array(Set(employees.map(\.cargo))).sorted() }
    var filtered: [EmployeePerformance] {
        employees.filter {
            (selectedRole == nil || $0.cargo == selectedRole)
            && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.nombre.localizedStandardContains(search)
                || $0.cargo.localizedStandardContains(search))
        }
    }

    func load(month: Date, employeeID: UUID? = nil) async {
        generation += 1
        let run = generation
        loading = true
        error = nil
        employees = []
        defer { if generation == run { loading = false } }
        do {
            var result: [EmployeePerformance] = []
            while true {
                let page: [EmployeePerformance] = try await client.rpc("admin_employee_performance", params:
                    PerformanceRequest(p_month: PerformancePeriod.key(month), p_offset: result.count, p_employee: employeeID))
                    .execute().value
                guard !Task.isCancelled, generation == run else { return }
                result.append(contentsOf: page)
                if page.count < 100 { break }
            }
            employees = result
            if let selectedRole, !roles.contains(selectedRole) { self.selectedRole = nil }
        } catch {
            guard !Task.isCancelled, generation == run else { return }
            self.error = AuthNotice.failure(error).message
        }
    }
}

private struct PerformanceRequest: Encodable {
    let p_month: String
    let p_offset: Int
    let p_employee: UUID?
}
