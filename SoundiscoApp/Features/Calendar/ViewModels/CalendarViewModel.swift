import Foundation
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var selected = Date()
}
