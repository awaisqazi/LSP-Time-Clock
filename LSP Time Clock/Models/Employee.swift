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

    @Relationship(deleteRule: .cascade, inverse: \PunchLog.employee)
    var punchLogs: [PunchLog] = []

    init(
        rfidTag: String,
        firstName: String,
        lastName: String,
        email: String,
        photoFileName: String
    ) {
        self.id = UUID()
        self.rfidTag = rfidTag
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.photoFileName = photoFileName
        self.isCurrentlyClockedIn = false
        self.createdAt = Date()
    }

    var fullName: String { "\(firstName) \(lastName)" }

    // MARK: - Bulk-onboarding sentinel

    /// Prefix applied to a per-employee unique placeholder used while a
    /// bulk-imported employee is awaiting their RFID card. Real card scans
    /// are sanitized down to alphanumerics + hyphens, so they can never
    /// collide with this prefix (which contains a `:`).
    static let pendingTagPrefix = "PENDING:"

    /// Generates a unique placeholder tag that satisfies the `@Attribute(.unique)`
    /// constraint while the employee waits for an RFID assignment.
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
