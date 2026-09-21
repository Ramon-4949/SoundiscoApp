import Foundation

struct EmployeePerformance: Decodable, Identifiable, Sendable {
    let id: UUID
    let nombre: String
    let cargo: String
    let temprano: Int
    let a_tiempo: Int
    let tardio: Int
    let sin_confirmar: Int
    let retraso_medio_minutos: Double?
    let notas_semanales: [PerformanceWeek]
    let asignaciones: Int
    let completadas: Int
    let activas: Int
    let vencidas: Int

    var evaluated: Int { temprano + a_tiempo + tardio + sin_confirmar }
    var compliance: Double? {
        evaluated == 0 ? nil : Double(temprano + a_tiempo) / Double(evaluated)
    }
    var percentage: String { compliance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var noteCount: Int { notas_semanales.reduce(0) { $0 + $1.cantidad } }
}

struct PerformanceWeek: Decodable, Identifiable, Sendable {
    let semana: Int
    let cantidad: Int
    var id: Int { semana }
}

enum PerformancePeriod {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santo_Domingo")!
        calendar.locale = Locale(identifier: "es_DO")
        return calendar
    }
    static func start(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }
    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d-01", parts.year!, parts.month!)
    }
    static func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_DO")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
}
