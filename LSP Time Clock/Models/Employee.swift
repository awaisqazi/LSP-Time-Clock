import Foundation
import SwiftData

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

    @Relationship(deleteRule: .cascade, inverse: \PunchLog.employee)
    var punchLogs: [PunchLog] = []

    init(
        rfidTag: String,
        firstName: String,
        lastName: String,
        email: String,
        photoFileName: String,
        pin: String = "",
        role: String = "",
        isActive: Bool = true
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
