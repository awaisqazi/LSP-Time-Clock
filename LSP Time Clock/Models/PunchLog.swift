import Foundation
import SwiftData

@Model
final class PunchLog {
    @Attribute(.unique) var id: UUID
    var employee: Employee?
    var clockInTime: Date
    var clockOutTime: Date?
    var wasForcedOut: Bool

    init(
        employee: Employee?,
        clockInTime: Date,
        clockOutTime: Date? = nil,
        wasForcedOut: Bool = false
    ) {
        self.id = UUID()
        self.employee = employee
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.wasForcedOut = wasForcedOut
    }

    var isOpen: Bool { clockOutTime == nil }

    var totalHours: Double? {
        guard let out = clockOutTime else { return nil }
        return out.timeIntervalSince(clockInTime) / 3600
    }
}
