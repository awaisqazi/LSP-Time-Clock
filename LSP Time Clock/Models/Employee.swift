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
}
