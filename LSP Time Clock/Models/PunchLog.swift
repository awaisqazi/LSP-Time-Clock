import Foundation
import SwiftData

/// The role an employee was actually working for a single punch. Differs
/// from `EmployeeRole` because a "both"-classified employee picks a side
/// at clock-in time — payroll is computed off this field, not the profile.
enum ShiftRole: String, CaseIterable, Identifiable, Codable {
    case instructor
    case coordinator

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instructor:  "Instructor"
        case .coordinator: "Coordinator"
        }
    }
}

@Model
final class PunchLog {
    @Attribute(.unique) var id: UUID
    var employee: Employee?
    var clockInTime: Date
    var clockOutTime: Date?
    var wasForcedOut: Bool

    /// Raw-string backing for `shiftRole`. Stored as a primitive so
    /// existing punch records lightweight-migrate cleanly: any historical
    /// log reads back as `.instructor`, which matches the only kind of
    /// shift that existed before this feature shipped.
    var shiftRoleRaw: String = ShiftRole.instructor.rawValue

    /// How many classes the instructor *intended* to teach for this shift,
    /// captured at clock-in. Coordinator shifts leave this at 0. Older
    /// records lightweight-migrate to 0.
    var scheduledClasses: Int = 0

    /// How many classes the instructor *actually* taught, confirmed at
    /// clock-out (a class with no students counts as not taught). Used
    /// directly to compute billable hours for instructor shifts.
    var actualClassesTaught: Int = 0

    // MARK: - Cloud sync bookkeeping

    /// Last time this punch was changed *on this device*. Compared against
    /// the server's `updated_at` to settle conflicts (last write wins).
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// True while local edits are waiting to be pushed to Supabase. The
    /// `true` default makes every pre-existing punch migrate in dirty, so
    /// the first successful sync uploads the studio's whole punch history.
    var needsSync: Bool = true

    /// Which system originally created this punch — `kiosk` for anything
    /// this iPad recorded, `portal` / `import` for rows that were born on
    /// the web side. Preserved verbatim across syncs so a punch typed into
    /// the portal doesn't get relabelled as a kiosk punch the first time
    /// the iPad touches it.
    var originSource: String = "kiosk"

    /// Free-text note maintained in the web portal (payroll annotations,
    /// "covered for X", etc.). The kiosk never authors these — it only
    /// displays them read-only in the punch editor — but it round-trips
    /// the value so an unrelated kiosk edit can't blank it out.
    var note: String = ""

    /// Type-safe accessor for the shift role. Backing column is a raw
    /// String so an unrecognized value (e.g. from a newer build) falls
    /// back to `.instructor` rather than crashing.
    var shiftRole: ShiftRole {
        get { ShiftRole(rawValue: shiftRoleRaw) ?? .instructor }
        set { shiftRoleRaw = newValue.rawValue }
    }

    init(
        employee: Employee?,
        clockInTime: Date,
        clockOutTime: Date? = nil,
        wasForcedOut: Bool = false,
        shiftRole: ShiftRole = .instructor,
        scheduledClasses: Int = 0,
        actualClassesTaught: Int = 0
    ) {
        self.id = UUID()
        self.employee = employee
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.wasForcedOut = wasForcedOut
        self.shiftRoleRaw = shiftRole.rawValue
        self.scheduledClasses = scheduledClasses
        self.actualClassesTaught = actualClassesTaught
        // Freshly created punches are dirty by construction.
        self.updatedAt = Date()
        self.needsSync = true
    }

    /// Stamp the row as locally modified so the next sync pushes it. Must
    /// be called at every mutation site before `modelContext.save()`.
    func markDirty() {
        updatedAt = Date()
        needsSync = true
    }

    var isOpen: Bool { clockOutTime == nil }

    /// Wall-clock hours between clock-in and clock-out (decimal hours).
    /// Used for the historical "Hours Logged" column on payroll exports.
    var totalHours: Double? {
        guard let out = clockOutTime else { return nil }
        return out.timeIntervalSince(clockInTime) / 3600
    }

    /// Hours that should be paid for this shift.
    ///
    /// - Coordinator shifts: paid for every minute they were on the clock,
    ///   so this matches `totalHours`.
    /// - Instructor shifts: paid a flat 1.5h per class actually taught,
    ///   regardless of how long they were on the clock (no-show classes
    ///   are *not* billable).
    ///
    /// Returns `nil` for an open coordinator shift (no clock-out yet means
    /// no elapsed time to bill); instructor shifts can still report a
    /// billable amount the moment `actualClassesTaught` is set.
    var billableHours: Double? {
        switch shiftRole {
        case .instructor:
            return 1.5 * Double(actualClassesTaught)
        case .coordinator:
            return totalHours
        }
    }
}
