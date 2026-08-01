import Foundation
import SwiftData

// MARK: - Pending deletion

/// The kind of row a `PendingDeletion` refers to. Raw strings match the
/// entity names the server's tombstone columns live on.
enum SyncEntityKind: String, Codable, CaseIterable {
    case employee
    case punch
}

/// A tombstone the kiosk still owes the server.
///
/// Hard deletes are destructive locally *and* invisible to the cloud: once
/// the row is gone there is nothing left to mark dirty, so a naive sync
/// would happily re-pull the record it just deleted. Enqueuing one of these
/// *before* the `modelContext.delete(...)` gives the push phase something
/// durable to act on — it PATCHes `deleted_at` on the server row, then
/// drops the queue entry.
@Model
final class PendingDeletion {
    @Attribute(.unique) var id: UUID
    var entityKind: String = SyncEntityKind.punch.rawValue
    var entityID: UUID = UUID()
    var queuedAt: Date = Date()

    /// Consecutive route-level 404s this tombstone has collected. PostgREST
    /// answers 404 for a few seconds after a deploy while its schema cache
    /// is cold, so a single one is not proof the table is missing — giving
    /// up immediately would leave a shift the admin deleted alive on the
    /// server forever. Literal default keeps the migration lightweight.
    var failedAttempts: Int = 0

    var kind: SyncEntityKind {
        SyncEntityKind(rawValue: entityKind) ?? .punch
    }

    init(kind: SyncEntityKind, entityID: UUID) {
        self.id = UUID()
        self.entityKind = kind.rawValue
        self.entityID = entityID
        self.queuedAt = Date()
        self.failedAttempts = 0
    }
}

/// Convenience for the two hard-delete call sites. Keeping the enqueue
/// logic here means a future delete path can't forget that deleting an
/// employee has to tombstone their punches too — the server's FK cascade
/// only fires on a *hard* delete, and we only ever soft-delete.
enum SyncDeletionQueue {
    static func enqueueEmployee(_ employee: Employee, in context: ModelContext) {
        context.insert(PendingDeletion(kind: .employee, entityID: employee.id))
        for log in employee.punchLogs {
            context.insert(PendingDeletion(kind: .punch, entityID: log.id))
        }
    }

    static func enqueuePunch(_ log: PunchLog, in context: ModelContext) {
        context.insert(PendingDeletion(kind: .punch, entityID: log.id))
    }
}

// MARK: - Kiosk messages

/// Who a studio message is meant for. Mirrors the `audience` check
/// constraint on `timeclock_messages`.
enum MessageAudience: String, Codable, CaseIterable {
    case all
    case instructor
    case coordinator
}

/// Local read-only mirror of a `timeclock_messages` row.
///
/// The kiosk never authors messages; the cache exists purely so the
/// check-in screen still shows today's announcements when the studio Wi-Fi
/// is down. It is replaced wholesale on every successful message fetch —
/// there is no merge logic and no dirty flag, because there is nothing the
/// iPad could ever have to say back about a message.
@Model
final class KioskMessage {
    @Attribute(.unique) var id: UUID
    var title: String = ""
    var body: String = ""
    var audienceRaw: String = MessageAudience.all.rawValue
    /// Non-nil when the message is aimed at one specific person. A
    /// personally-targeted message is shown *only* to that employee,
    /// regardless of `audience`.
    var targetEmployeeID: UUID?
    var startsOn: Date?
    var endsOn: Date?
    var isActive: Bool = true
    var sortOrder: Int = 0

    var audience: MessageAudience {
        MessageAudience(rawValue: audienceRaw) ?? .all
    }

    init(
        id: UUID,
        title: String,
        body: String,
        audience: MessageAudience,
        targetEmployeeID: UUID?,
        startsOn: Date?,
        endsOn: Date?,
        isActive: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.audienceRaw = audience.rawValue
        self.targetEmployeeID = targetEmployeeID
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    /// True when today falls inside the message's `[startsOn, endsOn]`
    /// window. Both bounds are optional and inclusive, and the comparison
    /// is done on *calendar days in the device's local time zone* — the
    /// server stores plain `date` columns, so "runs through Friday" has to
    /// mean Friday in the studio, not Friday in UTC.
    func isLive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        let today = calendar.startOfDay(for: date)
        if let startsOn, today < calendar.startOfDay(for: startsOn) { return false }
        if let endsOn, today > calendar.startOfDay(for: endsOn) { return false }
        return true
    }

    /// Audience match for a specific person about to punch.
    ///
    /// `shiftRole` is the role they are working *right now* — nil while a
    /// "both" profile hasn't picked a side yet, in which case only
    /// everyone-messages and their own personal messages apply.
    func applies(to employee: Employee, shiftRole: ShiftRole?, on date: Date) -> Bool {
        guard isLive(on: date) else { return false }
        if let targetEmployeeID {
            return targetEmployeeID == employee.id
        }
        switch audience {
        case .all:
            return true
        case .instructor:
            return shiftRole == .instructor
        case .coordinator:
            return shiftRole == .coordinator
        }
    }

    /// Studio-wide announcements: no personal target, everyone audience.
    /// These are the only messages the Idle screen is allowed to show,
    /// since nobody has identified themselves yet.
    func isStudioWide(on date: Date) -> Bool {
        targetEmployeeID == nil && audience == .all && isLive(on: date)
    }
}

// MARK: - Message receipts

/// Proof that a given employee actually saw a given message while punching.
///
/// Written locally at confirm time and pushed on the next sync; the portal
/// uses these to answer "did everyone read the schedule change?" without
/// the kiosk needing to be online at the moment of the punch.
@Model
final class MessageReceipt {
    @Attribute(.unique) var id: UUID
    var messageID: UUID = UUID()
    var employeeID: UUID = UUID()
    var punchID: UUID?
    var seenAt: Date = Date()
    var needsSync: Bool = true

    init(messageID: UUID, employeeID: UUID, punchID: UUID?, seenAt: Date = Date()) {
        self.id = UUID()
        self.messageID = messageID
        self.employeeID = employeeID
        self.punchID = punchID
        self.seenAt = seenAt
        self.needsSync = true
    }
}
