import Foundation
import SwiftData

/// Employee classification on the *profile* (their job at the studio overall).
/// "Both" employees may work either kind of shift; the specific role they
/// worked for any given punch is captured on the `PunchLog` itself.
enum EmployeeRole: String, CaseIterable, Identifiable, Codable {
    case instructor
    case coordinator
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instructor:  "Instructor"
        case .coordinator: "Coordinator"
        case .both:        "Both"
        }
    }
}

@Model
final class Employee {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var rfidTag: String
    var firstName: String
    var lastName: String
    var email: String
    var photoFileName: String
    var isCurrentlyClockedIn: Bool
    var createdAt: Date

    // New fields — all have stored-property defaults so SwiftData performs
    // a lightweight migration on existing stores without data loss.
    var pin: String = ""
    var role: String = ""
    var isActive: Bool = true

    /// Raw-string backing for `profileRole`. Stored as a primitive so
    /// SwiftData performs a lightweight migration on existing stores —
    /// every pre-existing employee will read back the default of
    /// `instructor`, which matches how the studio operated before this
    /// feature shipped.
    var profileRoleRaw: String = EmployeeRole.instructor.rawValue

    // MARK: - Cloud sync bookkeeping

    /// Last time this row was changed *on this device*. Compared against
    /// the server's `updated_at` to settle conflicts (last write wins).
    /// The two clocks are independent — an iPad whose time is badly wrong
    /// can lose an edit it should have won — which is an acceptable trade
    /// for a single-kiosk studio and avoids a vector-clock scheme nobody
    /// here would ever debug.
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// True while local edits are waiting to be pushed to Supabase.
    ///
    /// The default is deliberately `true`: when this column is added by a
    /// lightweight migration every pre-existing employee reads back dirty,
    /// so the first successful sync bootstraps the studio's entire
    /// historical roster into the cloud without a bespoke backfill step.
    var needsSync: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \PunchLog.employee)
    var punchLogs: [PunchLog] = []

    /// Type-safe accessor for the employee's profile classification. The
    /// backing column is a raw String (see `profileRoleRaw`) so an
    /// unrecognized value from a future build degrades gracefully back to
    /// `.instructor` rather than crashing.
    var profileRole: EmployeeRole {
        get { EmployeeRole(rawValue: profileRoleRaw) ?? .instructor }
        set { profileRoleRaw = newValue.rawValue }
    }

    init(
        rfidTag: String,
        firstName: String,
        lastName: String,
        email: String,
        photoFileName: String,
        pin: String = "",
        role: String = "",
        isActive: Bool = true,
        profileRole: EmployeeRole = .instructor
    ) {
        self.id = UUID()
        self.rfidTag = rfidTag
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.photoFileName = photoFileName
        self.isCurrentlyClockedIn = false
        self.createdAt = Date()
        self.pin = pin
        self.role = role
        self.isActive = isActive
        self.profileRoleRaw = profileRole.rawValue
        // Freshly created employees are dirty by construction — they only
        // exist on this iPad until the next successful push.
        self.updatedAt = Date()
        self.needsSync = true
    }

    /// Stamp the row as locally modified so the next sync pushes it.
    /// Call this at *every* mutation site immediately before
    /// `modelContext.save()` — a missed call silently strands the edit on
    /// the iPad forever, since nothing else ever re-flags a record.
    func markDirty() {
        updatedAt = Date()
        needsSync = true
    }

    var fullName: String { "\(firstName) \(lastName)" }

    /// Display string for the roster — falls back to email when the name
    /// hasn't been filled in yet (e.g., for placeholder bulk-import rows).
    var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? email : trimmed
    }

    // MARK: - Bulk-onboarding sentinel

    /// Prefix applied to a per-employee unique placeholder used while a
    /// bulk-imported employee is awaiting their RFID card. Real card scans
    /// are sanitized down to alphanumerics + hyphens, so they can never
    /// collide with this prefix (which contains a `:`).
    static let pendingTagPrefix = "PENDING:"

    static func makePendingTag() -> String {
        "\(pendingTagPrefix)\(UUID().uuidString)"
    }

    var hasAssignedCard: Bool {
        !rfidTag.isEmpty && !rfidTag.hasPrefix(Self.pendingTagPrefix)
    }

    var hasAssignedPhoto: Bool {
        !photoFileName.isEmpty
    }

    /// True while the employee is part of the bulk-onboarding queue. The
    /// card is the only blocker — without it the kiosk has no way to punch
    /// the employee in. The photo is optional and can be added later via
    /// the Edit flow on the dashboard.
    var isPendingOnboarding: Bool {
        !hasAssignedCard
    }
}
