import Foundation
import Observation
import SwiftData

// MARK: - Table names

nonisolated enum SupabaseTable {
    static let employees = "timeclock_employees"
    static let punches = "timeclock_punches"
    static let messages = "timeclock_messages"
    static let receipts = "timeclock_message_receipts"
    static let kioskStatus = "timeclock_kiosk_status"
}

// MARK: - Inbound rows
//
// Every field except the primary key is optional. PostgREST will happily
// hand back a null a check constraint was supposed to prevent, and a single
// unexpected null must degrade to "skip this field" rather than "abort the
// whole sync".

nonisolated struct RemoteEmployee: Decodable, Sendable {
    let id: UUID
    let rfidTag: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let pin: String?
    let jobTitle: String?
    let profileRole: String?
    let isActive: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case rfidTag = "rfid_tag"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case pin
        case jobTitle = "job_title"
        case profileRole = "profile_role"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

nonisolated struct RemotePunch: Decodable, Sendable {
    let id: UUID
    let employeeID: UUID?
    let clockInAt: Date?
    let clockOutAt: Date?
    let wasForcedOut: Bool?
    let shiftRole: String?
    let scheduledClasses: Int?
    let actualClassesTaught: Int?
    let source: String?
    let note: String?
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case employeeID = "employee_id"
        case clockInAt = "clock_in_at"
        case clockOutAt = "clock_out_at"
        case wasForcedOut = "was_forced_out"
        case shiftRole = "shift_role"
        case scheduledClasses = "scheduled_classes"
        case actualClassesTaught = "actual_classes_taught"
        case source
        case note
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

nonisolated struct RemoteMessage: Decodable, Sendable {
    let id: UUID
    let title: String?
    let body: String?
    let audience: String?
    let employeeID: UUID?
    let startsOn: Date?
    let endsOn: Date?
    let isActive: Bool?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case audience
        case employeeID = "employee_id"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }
}

// MARK: - Outbound rows

nonisolated struct EmployeePush: Encodable, Sendable {
    let id: UUID
    let rfidTag: String
    let firstName: String
    let lastName: String
    let email: String
    let pin: String
    let jobTitle: String
    let profileRole: String
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case rfidTag = "rfid_tag"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case pin
        case jobTitle = "job_title"
        case profileRole = "profile_role"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

nonisolated struct PunchPush: Encodable, Sendable {
    let id: UUID
    let employeeID: UUID
    let clockInAt: Date
    let clockOutAt: Date?
    let wasForcedOut: Bool
    let shiftRole: String
    let scheduledClasses: Int
    let actualClassesTaught: Int
    let source: String
    let note: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case employeeID = "employee_id"
        case clockInAt = "clock_in_at"
        case clockOutAt = "clock_out_at"
        case wasForcedOut = "was_forced_out"
        case shiftRole = "shift_role"
        case scheduledClasses = "scheduled_classes"
        case actualClassesTaught = "actual_classes_taught"
        case source
        case note
        case createdAt = "created_at"
    }

    /// Hand-written so `clock_out_at` is emitted as an explicit `null`
    /// rather than omitted. A merge-duplicates upsert only writes the
    /// columns present in the payload, so relying on the synthesized
    /// `encodeIfPresent` would make "admin re-opened this shift" silently
    /// un-pushable.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(employeeID, forKey: .employeeID)
        try container.encode(clockInAt, forKey: .clockInAt)
        try container.encode(clockOutAt, forKey: .clockOutAt)
        try container.encode(wasForcedOut, forKey: .wasForcedOut)
        try container.encode(shiftRole, forKey: .shiftRole)
        try container.encode(scheduledClasses, forKey: .scheduledClasses)
        try container.encode(actualClassesTaught, forKey: .actualClassesTaught)
        try container.encode(source, forKey: .source)
        try container.encode(note, forKey: .note)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

nonisolated struct ReceiptPush: Encodable, Sendable {
    let id: UUID
    let messageID: UUID
    let employeeID: UUID
    let punchID: UUID?
    let seenAt: Date
    let acknowledgedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case messageID = "message_id"
        case employeeID = "employee_id"
        case punchID = "punch_id"
        case seenAt = "seen_at"
        case acknowledgedAt = "acknowledged_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(employeeID, forKey: .employeeID)
        try container.encode(punchID, forKey: .punchID)
        try container.encode(seenAt, forKey: .seenAt)
        // Written unconditionally (null included) rather than
        // `encodeIfPresent`: the push is a whole-row upsert, so omitting the
        // key on a not-yet-acknowledged receipt would leave whatever the
        // server already had in that column.
        try container.encode(acknowledgedAt, forKey: .acknowledgedAt)
    }
}

nonisolated struct TombstonePush: Encodable, Sendable {
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

nonisolated struct KioskStatusPush: Encodable, Sendable {
    let id: String
    let lastSeenAt: Date
    let appVersion: String
    let pendingPush: Int
    let detail: Detail

    enum CodingKeys: String, CodingKey {
        case id
        case lastSeenAt = "last_seen_at"
        case appVersion = "app_version"
        case pendingPush = "pending_push"
        case detail
    }

    nonisolated struct Detail: Encodable, Sendable {
        let employees: Int
        let punches: Int
        let receipts: Int
        let deletions: Int
        let lastError: String?

        enum CodingKeys: String, CodingKey {
            case employees
            case punches
            case receipts
            case deletions
            case lastError = "last_error"
        }
    }
}

// MARK: - Engine

/// Opportunistic two-way replication between the kiosk's SwiftData store
/// and Supabase.
///
/// Design rule that everything else follows from: **the kiosk must work
/// perfectly with no network at all.** Sync is therefore never on the
/// critical path of a punch — it is fired and forgotten after the punch has
/// already been committed locally, any thrown error aborts the run without
/// touching a dirty flag, and the next trigger simply tries again.
@Observable
@MainActor
final class SyncEngine {

    // MARK: Published state (admin Cloud Sync screen)

    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var isSignedIn = false
    private(set) var lastPulledCount = 0
    private(set) var lastPushedCount = 0

    private(set) var pendingEmployees = 0
    private(set) var pendingPunches = 0
    private(set) var pendingReceipts = 0
    private(set) var pendingDeletions = 0

    var pendingTotal: Int {
        pendingEmployees + pendingPunches + pendingReceipts + pendingDeletions
    }

    var isConfigured: Bool { SupabaseConfig.isConfigured }
    var accountEmail: String { SupabaseConfig.deviceEmail }

    // MARK: Internals

    /// Rows per PostgREST request. Large enough that a season of history
    /// uploads in a handful of round trips, small enough that a dropped
    /// connection only costs one batch.
    private static let batchSize = 200

    /// Minimum spacing between the automatic triggers (returning to Idle,
    /// finishing a punch). Prevents an admin bouncing around the dashboard
    /// from firing a request per tap. `nonisolated` so it can be used as a
    /// default argument, which is evaluated at the call site.
    nonisolated static let debounceInterval: TimeInterval = 10

    /// Background cadence while the kiosk sits on the Idle screen.
    nonisolated static let idlePollInterval: TimeInterval = 180

    /// First back-off after a rejected sign-in, and the ceiling it doubles
    /// up to. A wrong stored password would otherwise hit GoTrue on every
    /// single punch, every return to Idle, and every idle poll — which is
    /// both useless and a good way to get the project rate-limited.
    private static let authBackoffBase: TimeInterval = 60
    private static let authBackoffCap: TimeInterval = 1800

    /// How many consecutive route-level 404s a tombstone survives before it
    /// is written off as un-deliverable.
    private static let maxDeletionAttempts = 3

    /// Rows merged between cooperative yields during a pull. The very first
    /// sync merges the studio's entire history on the main actor; without a
    /// breather the kiosk would appear frozen for the duration.
    private static let mergeYieldStride = 200

    private let context: ModelContext
    private let api = SupabaseAPI()
    private var isRunning = false
    private var lastAttemptAt: Date?
    private var idleTask: Task<Void, Never>?

    private var authFailureCount = 0
    private var authRetryAfter: Date?

    init(container: ModelContainer) {
        // The main context is deliberate: views observe it through @Query,
        // so a pull lands on screen without any extra plumbing.
        self.context = container.mainContext
        refreshPendingCounts()
    }

    // MARK: - Triggers

    /// Fire-and-forget entry point for the automatic triggers. Silently
    /// no-ops when a sync ran recently or none is configured.
    func requestSync(minInterval: TimeInterval = SyncEngine.debounceInterval) {
        guard isConfigured, !isAuthCoolingDown else { return }
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < minInterval { return }
        Task { await syncNow() }
    }

    /// Immediate, un-debounced trigger used right after a punch is
    /// committed — a punch is exactly the event the office cares about
    /// seeing promptly.
    func syncAfterPunch() {
        guard isConfigured, !isAuthCoolingDown else { return }
        Task { await syncNow() }
    }

    /// Starts the slow background poll. Called when the Idle screen appears
    /// so a kiosk nobody touches all afternoon still picks up portal edits.
    func startIdlePolling() {
        guard idleTask == nil else { return }
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SyncEngine.idlePollInterval))
                if Task.isCancelled { return }
                guard let self else { return }
                if self.isAuthCoolingDown { continue }
                await self.syncNow()
            }
        }
    }

    func stopIdlePolling() {
        idleTask?.cancel()
        idleTask = nil
    }

    /// Saves the credentials typed on the admin screen and immediately
    /// proves them, so a typo surfaces on the spot.
    ///
    /// Verify first, persist second: a mistyped password must not overwrite
    /// the working one that is currently keeping the kiosk in sync. On
    /// failure both the stored credentials and the live session are left
    /// exactly as they were and the error goes to the admin screen.
    func signIn(email: String, password: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)

        // A different credential pair is a fresh start: the back-off exists
        // to stop a *known-bad* stored password from hammering GoTrue, not
        // to punish an admin who is actively fixing it.
        if trimmed != SupabaseConfig.deviceEmail || password != SupabaseConfig.devicePassword {
            clearAuthBackoff()
        }

        do {
            try await api.signIn(email: trimmed, password: password)
            SupabaseConfig.deviceEmail = trimmed
            SupabaseConfig.devicePassword = password
            isSignedIn = true
            lastError = nil
            // New credentials deserve a clean slate — the admin is standing
            // right there and shouldn't wait out a back-off from the old
            // password.
            clearAuthBackoff()
            await syncNow()
        } catch {
            isSignedIn = false
            lastError = describe(error)
            if case SupabaseError.unauthorized = error { noteAuthFailure() }
        }
    }

    // MARK: - Auth back-off

    /// True while a recently rejected credential set is serving its
    /// penalty. Only the automatic triggers consult this — an admin tapping
    /// "Sync Now" always gets a real attempt.
    private var isAuthCoolingDown: Bool {
        guard let authRetryAfter else { return false }
        return Date() < authRetryAfter
    }

    private func noteAuthFailure() {
        authFailureCount += 1
        let delay = min(
            Self.authBackoffCap,
            Self.authBackoffBase * pow(2, Double(authFailureCount - 1))
        )
        authRetryAfter = Date().addingTimeInterval(delay)
    }

    private func clearAuthBackoff() {
        authFailureCount = 0
        authRetryAfter = nil
    }

    // MARK: - The sync run

    /// One complete push → pull → heartbeat cycle. Re-entrant calls are
    /// dropped rather than queued: whatever the second caller wanted to
    /// sync is already covered by the run in flight, or will be by the next
    /// trigger.
    ///
    /// Push runs *before* pull so the server has already seen this device's
    /// work when the delta comes back — otherwise a pull can hand a local
    /// row a server timestamp the push then re-sends, and a portal
    /// tombstone can land on punches that were never uploaded.
    func syncNow() async {
        guard !isRunning else { return }
        guard isConfigured else {
            refreshPendingCounts()
            return
        }

        isRunning = true
        isSyncing = true
        lastAttemptAt = Date()

        do {
            do {
                try await api.ensureSignedIn()
            } catch {
                if case SupabaseError.unauthorized = error { noteAuthFailure() }
                throw error
            }
            isSignedIn = true
            clearAuthBackoff()

            let pushed = try await push()
            let highWaterMark = try await pull()

            advanceWatermark(to: highWaterMark)
            lastPushedCount = pushed
            lastSyncAt = Date()
            lastError = nil

            // Last, and deliberately non-fatal. The heartbeat is a status
            // row the office dashboard reads; a failure to write it says
            // nothing about whether payroll data made it up, and must not
            // roll back the watermark or paint the screen red.
            refreshPendingCounts()
            try? await sendHeartbeat()
        } catch {
            // Dirty flags are intentionally untouched — everything that
            // failed to reach the server is still queued for the next run.
            lastError = describe(error)
            if case SupabaseError.unauthorized = error { isSignedIn = false }
        }

        refreshPendingCounts()
        isSyncing = false
        isRunning = false
    }

    // MARK: - Pull

    /// Returns the highest server `updated_at` observed, which becomes the
    /// next watermark.
    private func pull() async throws -> Date? {
        let since = SupabaseConfig.pullWatermark
            .addingTimeInterval(-SupabaseConfig.watermarkSlack)
        let sinceValue = "gt.\(SupabaseDate.string(from: since))"

        let employees = try await api.fetch(
            RemoteEmployee.self,
            table: SupabaseTable.employees,
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "updated_at", value: sinceValue),
                URLQueryItem(name: "order", value: "updated_at.asc")
            ]
        )

        let punches = try await api.fetch(
            RemotePunch.self,
            table: SupabaseTable.punches,
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "updated_at", value: sinceValue),
                URLQueryItem(name: "order", value: "updated_at.asc")
            ]
        )

        // Messages are a full snapshot rather than a delta: the set is tiny,
        // and a wholesale replace is the only way a *deactivated* message
        // reliably disappears from the check-in screen.
        let messages = try await api.fetch(
            RemoteMessage.self,
            table: SupabaseTable.messages,
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )

        let touchedEmployees = await merge(employees: employees, punches: punches)
        replaceMessages(messages)
        try context.save()

        // Deleted punches only leave the relationship arrays after the save,
        // so the clocked-in recompute has to run on the far side of it.
        recomputeClockedIn(for: touchedEmployees)
        try context.save()

        lastPulledCount = employees.count + punches.count

        let watermarks = employees.compactMap(\.updatedAt) + punches.compactMap(\.updatedAt)
        return watermarks.max()
    }

    /// Merges both row sets against one pair of in-memory indexes.
    ///
    /// The first sync of an established studio is thousands of rows, and the
    /// obvious implementation — a `FetchDescriptor` round trip per row —
    /// turns that bootstrap into a minute-long freeze on the main actor,
    /// which on a kiosk means a locked-up screen with someone standing in
    /// front of it. Two bulk fetches plus periodic yields instead.
    private func merge(employees: [RemoteEmployee], punches: [RemotePunch]) async -> Set<UUID> {
        guard !employees.isEmpty || !punches.isEmpty else { return [] }

        var employeesByID = employeeIndex()
        var punchesByID: [UUID: PunchLog] = punches.isEmpty ? [:] : punchIndex()
        var mergedRows = 0

        await mergeEmployees(
            employees,
            employeesByID: &employeesByID,
            punchesByID: &punchesByID,
            mergedRows: &mergedRows
        )
        return await mergePunches(
            punches,
            employeesByID: employeesByID,
            punchesByID: &punchesByID,
            mergedRows: &mergedRows
        )
    }

    private func employeeIndex() -> [UUID: Employee] {
        let rows = (try? context.fetch(FetchDescriptor<Employee>())) ?? []
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func punchIndex() -> [UUID: PunchLog] {
        let rows = (try? context.fetch(FetchDescriptor<PunchLog>())) ?? []
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func mergeEmployees(
        _ rows: [RemoteEmployee],
        employeesByID: inout [UUID: Employee],
        punchesByID: inout [UUID: PunchLog],
        mergedRows: inout Int
    ) async {
        for row in rows {
            mergedRows += 1
            if mergedRows % Self.mergeYieldStride == 0 { await Task.yield() }

            let local = employeesByID[row.id]

            if row.deletedAt != nil {
                if let local {
                    // Deleting the employee cascades to every punch they own.
                    // If the employee or any of those punches still owes the
                    // server a push, the tombstone waits for the next run —
                    // destroying a shift that was never uploaded is
                    // unrecoverable, and deferring costs one cycle.
                    if local.needsSync || local.punchLogs.contains(where: { $0.needsSync }) { continue }
                    let photo = local.photoFileName
                    for log in local.punchLogs { punchesByID.removeValue(forKey: log.id) }
                    employeesByID.removeValue(forKey: row.id)
                    context.delete(local)
                    // No PendingDeletion here: the server already knows.
                    if !photo.isEmpty { PhotoStorage.delete(fileName: photo) }
                }
                continue
            }

            guard let remoteUpdatedAt = row.updatedAt else { continue }

            if let local {
                // A locally dirty row only yields to a strictly newer server
                // write; otherwise we keep ours and it wins on the push.
                if local.needsSync, remoteUpdatedAt <= local.updatedAt { continue }
                apply(row, to: local, updatedAt: remoteUpdatedAt)
            } else {
                let employee = Employee(
                    rfidTag: newTag(from: row.rfidTag),
                    firstName: row.firstName ?? "",
                    lastName: row.lastName ?? "",
                    email: row.email ?? "",
                    photoFileName: "",
                    pin: row.pin ?? "",
                    role: row.jobTitle ?? "",
                    isActive: row.isActive ?? true,
                    profileRole: EmployeeRole(rawValue: row.profileRole ?? "") ?? .instructor
                )
                employee.id = row.id
                employee.createdAt = row.createdAt ?? Date()
                employee.updatedAt = remoteUpdatedAt
                employee.needsSync = false
                context.insert(employee)
                employeesByID[row.id] = employee
            }
        }
    }

    private func apply(_ row: RemoteEmployee, to employee: Employee, updatedAt: Date) {
        var rejectedRemoteTag = false
        if let tag = row.rfidTag {
            let resolution = resolvedTag(tag, for: employee)
            employee.rfidTag = resolution.tag
            rejectedRemoteTag = resolution.rejectedRemote
        }
        if let value = row.firstName { employee.firstName = value }
        if let value = row.lastName { employee.lastName = value }
        if let value = row.email { employee.email = value }
        if let value = row.pin { employee.pin = value }
        if let value = row.jobTitle { employee.role = value }
        if let raw = row.profileRole, let role = EmployeeRole(rawValue: raw) {
            employee.profileRoleRaw = role.rawValue
        }
        if let value = row.isActive { employee.isActive = value }
        if let value = row.createdAt { employee.createdAt = value }
        employee.updatedAt = updatedAt
        // Normally the row is now a faithful copy of the server's and can be
        // marked clean. The exception is a rejected card number: the kiosk
        // kept its own tag, so the row is genuinely divergent and has to stay
        // queued or the two sides never reconcile.
        employee.needsSync = rejectedRemoteTag
    }

    /// The local schema requires a unique, non-empty RFID tag; the server's
    /// does not. An employee the portal created but hasn't handed a card to
    /// gets a `PENDING:` placeholder, which drops them straight into the
    /// existing bulk-onboarding queue with no special-casing anywhere else.
    private func newTag(from remote: String?) -> String {
        let trimmed = (remote ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Employee.makePendingTag() }
        // Two rows claiming one card would trip the unique constraint and
        // fail the entire save, taking the rest of the pull with it.
        if EmployeeLookup.byRFID(trimmed, in: context) != nil {
            return Employee.makePendingTag()
        }
        return trimmed
    }

    /// `rejectedRemote` is true only when a *usable* remote tag was thrown
    /// away because another local employee already holds it — the one case
    /// where the local row is knowingly out of step with the server.
    private func resolvedTag(
        _ remote: String,
        for employee: Employee
    ) -> (tag: String, rejectedRemote: Bool) {
        let trimmed = remote.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (employee.rfidTag, false) }
        guard trimmed != employee.rfidTag else { return (trimmed, false) }
        if let conflict = EmployeeLookup.byRFID(trimmed, in: context), conflict.id != employee.id {
            // Keep what the kiosk has and let a human untangle it — losing
            // the whole pull over a duplicated card is far worse.
            return (employee.rfidTag, true)
        }
        return (trimmed, false)
    }

    /// Returns the IDs of every employee whose punch set changed, so their
    /// `isCurrentlyClockedIn` flag can be recomputed afterwards.
    private func mergePunches(
        _ rows: [RemotePunch],
        employeesByID: [UUID: Employee],
        punchesByID: inout [UUID: PunchLog],
        mergedRows: inout Int
    ) async -> Set<UUID> {
        var touched: Set<UUID> = []

        for row in rows {
            mergedRows += 1
            if mergedRows % Self.mergeYieldStride == 0 { await Task.yield() }

            let local = punchesByID[row.id]

            if row.deletedAt != nil {
                if let local {
                    if let id = local.employee?.id { touched.insert(id) }
                    punchesByID.removeValue(forKey: row.id)
                    context.delete(local)
                }
                continue
            }

            guard let remoteUpdatedAt = row.updatedAt, let clockIn = row.clockInAt else { continue }

            if let local {
                if local.needsSync, remoteUpdatedAt <= local.updatedAt { continue }
                if let employeeID = row.employeeID, local.employee?.id != employeeID {
                    if let owner = employeesByID[employeeID] {
                        if let previous = local.employee?.id { touched.insert(previous) }
                        local.employee = owner
                    }
                }
                apply(row, to: local, clockIn: clockIn, updatedAt: remoteUpdatedAt)
                if let id = local.employee?.id { touched.insert(id) }
            } else {
                // A punch whose employee hasn't been pulled yet is skipped,
                // not invented: the next sync (which will have pulled the
                // employee) picks it up.
                guard let employeeID = row.employeeID,
                      let owner = employeesByID[employeeID] else { continue }
                let log = PunchLog(employee: owner, clockInTime: clockIn)
                log.id = row.id
                apply(row, to: log, clockIn: clockIn, updatedAt: remoteUpdatedAt)
                context.insert(log)
                punchesByID[row.id] = log
                touched.insert(owner.id)
            }
        }

        return touched
    }

    private func apply(_ row: RemotePunch, to log: PunchLog, clockIn: Date, updatedAt: Date) {
        log.clockInTime = clockIn
        log.clockOutTime = row.clockOutAt
        log.wasForcedOut = row.wasForcedOut ?? false
        if let raw = row.shiftRole, let role = ShiftRole(rawValue: raw) {
            log.shiftRoleRaw = role.rawValue
        }
        log.scheduledClasses = row.scheduledClasses ?? 0
        log.actualClassesTaught = row.actualClassesTaught ?? 0
        if let source = row.source, !source.isEmpty { log.originSource = source }
        log.note = row.note ?? ""
        log.updatedAt = updatedAt
        log.needsSync = false
    }

    private func recomputeClockedIn(for employeeIDs: Set<UUID>) {
        guard !employeeIDs.isEmpty else { return }
        // Re-indexed rather than reusing the merge index: this runs on the
        // far side of a save, so anything the merge deleted is genuinely
        // gone and must not be touched again.
        let employeesByID = employeeIndex()
        for id in employeeIDs {
            guard let employee = employeesByID[id] else { continue }
            let hasOpenShift = employee.punchLogs.contains { $0.isOpen }
            // Purely local bookkeeping — no column for it on the server, so
            // deliberately not marked dirty.
            if employee.isCurrentlyClockedIn != hasOpenShift {
                employee.isCurrentlyClockedIn = hasOpenShift
            }
        }
    }

    private func replaceMessages(_ rows: [RemoteMessage]) {
        let cached = (try? context.fetch(FetchDescriptor<KioskMessage>())) ?? []
        for message in cached { context.delete(message) }

        for row in rows {
            guard row.isActive ?? true else { continue }
            context.insert(
                KioskMessage(
                    id: row.id,
                    title: row.title ?? "",
                    body: row.body ?? "",
                    audience: MessageAudience(rawValue: row.audience ?? "") ?? .all,
                    targetEmployeeID: row.employeeID,
                    startsOn: row.startsOn,
                    endsOn: row.endsOn,
                    isActive: true,
                    sortOrder: row.sortOrder ?? 0
                )
            )
        }
    }

    // MARK: - Push

    private func push() async throws -> Int {
        // Deletions first so a tombstone can't be undone by a stale upsert,
        // then employees before punches because of the punches' FK.
        var total = try await pushDeletions()
        total += try await pushEmployees()
        total += try await pushPunches()
        total += try await pushReceipts()
        return total
    }

    private func pushDeletions() async throws -> Int {
        let queued = (try? context.fetch(
            FetchDescriptor<PendingDeletion>(sortBy: [SortDescriptor(\.queuedAt)])
        )) ?? []
        guard !queued.isEmpty else { return 0 }

        var pushed = 0
        let stamp = TombstonePush(deletedAt: Date())
        for item in queued {
            let table = item.kind == .employee ? SupabaseTable.employees : SupabaseTable.punches
            do {
                try await api.patch(
                    table: table,
                    filter: [URLQueryItem(name: "id", value: "eq.\(item.entityID.uuidString.lowercased())")],
                    payload: stamp
                )
            } catch SupabaseError.http(let status, _) where status == 404 {
                // Route-level 404 — the *table* looked missing, not the row.
                // (A PATCH that simply matches no rows returns 204, so a
                // never-uploaded row is already the success case above.)
                // PostgREST answers this way for a few seconds after a
                // schema deploy while its cache is cold, so dropping the
                // tombstone on the first one would leave a shift the admin
                // deleted alive on the server forever. Retry a couple of
                // runs, then write it off — deletions run ahead of every
                // other push and one that can never succeed must not block
                // payroll data from uploading.
                item.failedAttempts += 1
                if item.failedAttempts < Self.maxDeletionAttempts {
                    try context.save()
                    continue
                }
                context.delete(item)
                try context.save()
                continue
            }
            context.delete(item)
            try context.save()
            pushed += 1
        }
        return pushed
    }

    private func pushEmployees() async throws -> Int {
        let dirty = (try? context.fetch(
            FetchDescriptor<Employee>(predicate: #Predicate { $0.needsSync == true })
        )) ?? []
        guard !dirty.isEmpty else { return 0 }

        var pushed = 0
        for batch in chunk(dirty) {
            // Snapshot the stamps we are about to declare uploaded. An admin
            // saving an edit while the request is in flight re-stamps the
            // row, and clearing the flag unconditionally afterwards would
            // strand that edit on the iPad forever.
            let stamps = batch.map(\.updatedAt)
            let rows = batch.map { employee in
                EmployeePush(
                    id: employee.id,
                    // `PENDING:` placeholders travel through verbatim so the
                    // portal can see who still needs a card handed to them.
                    rfidTag: employee.rfidTag,
                    firstName: employee.firstName,
                    lastName: employee.lastName,
                    email: employee.email,
                    pin: employee.pin,
                    jobTitle: employee.role,
                    profileRole: employee.profileRoleRaw,
                    isActive: employee.isActive,
                    createdAt: employee.createdAt
                )
            }
            try await api.upsert(table: SupabaseTable.employees, rows: rows, onConflict: "id")
            for (employee, stamp) in zip(batch, stamps) where employee.updatedAt == stamp {
                employee.needsSync = false
            }
            try context.save()
            pushed += batch.count
        }
        return pushed
    }

    private func pushPunches() async throws -> Int {
        let dirty = (try? context.fetch(
            FetchDescriptor<PunchLog>(predicate: #Predicate { $0.needsSync == true })
        )) ?? []
        // An orphaned punch has no `employee_id` to satisfy the server's
        // NOT NULL FK; it stays dirty and out of the way rather than
        // poisoning the batch it happens to land in.
        let sendable = dirty.filter { $0.employee != nil }
        guard !sendable.isEmpty else { return 0 }

        var pushed = 0
        for batch in chunk(sendable) {
            // See `pushEmployees` — an admin edit landing mid-request must
            // survive the flag clear that follows.
            let stamps = batch.map(\.updatedAt)
            let rows: [PunchPush] = batch.compactMap { log in
                guard let employeeID = log.employee?.id else { return nil }
                return PunchPush(
                    id: log.id,
                    employeeID: employeeID,
                    clockInAt: log.clockInTime,
                    clockOutAt: log.clockOutTime,
                    wasForcedOut: log.wasForcedOut,
                    shiftRole: log.shiftRoleRaw,
                    scheduledClasses: log.scheduledClasses,
                    actualClassesTaught: log.actualClassesTaught,
                    source: log.originSource,
                    note: log.note,
                    // PunchLog has no separate creation stamp; clock-in is
                    // the moment the record came into existence, and it is
                    // stable across re-pushes.
                    createdAt: log.clockInTime
                )
            }
            try await api.upsert(table: SupabaseTable.punches, rows: rows, onConflict: "id")
            for (log, stamp) in zip(batch, stamps) where log.updatedAt == stamp {
                log.needsSync = false
            }
            try context.save()
            pushed += batch.count
        }
        return pushed
    }

    private func pushReceipts() async throws -> Int {
        let dirty = (try? context.fetch(
            FetchDescriptor<MessageReceipt>(predicate: #Predicate { $0.needsSync == true })
        )) ?? []
        guard !dirty.isEmpty else { return 0 }

        let sendable = pruneOrphanedReceipts(dirty)
        guard !sendable.isEmpty else { return 0 }

        var pushed = 0
        for batch in chunk(sendable) {
            let rows = batch.map { receipt in
                ReceiptPush(
                    id: receipt.id,
                    messageID: receipt.messageID,
                    employeeID: receipt.employeeID,
                    punchID: receipt.punchID,
                    seenAt: receipt.seenAt,
                    acknowledgedAt: receipt.acknowledgedAt
                )
            }
            // What each row claimed at send time. A receipt is no longer
            // immutable — tapping "Got it" stamps `acknowledgedAt` and
            // re-dirties an already-pushed row — so an ack landing while this
            // request is in flight must not be cleared by the success path
            // below, or it would never reach the server.
            let sentAcks = batch.map(\.acknowledgedAt)
            do {
                try await api.upsert(table: SupabaseTable.receipts, rows: rows, onConflict: "id")
            } catch SupabaseError.http(let status, _) where status == 409 {
                // A conflict the kiosk cannot resolve — almost always an FK
                // to a message the portal has since hard-deleted. A receipt
                // is telemetry ("did they see the notice?"); it is never
                // allowed to wedge the queue that payroll rides on, so the
                // batch is dropped locally and the run carries on.
                for receipt in batch { context.delete(receipt) }
                try context.save()
                continue
            }
            for (receipt, sentAck) in zip(batch, sentAcks) where receipt.acknowledgedAt == sentAck {
                receipt.needsSync = false
            }
            try context.save()
            pushed += batch.count
        }
        return pushed
    }

    /// Drops receipts that can no longer satisfy the server's foreign keys.
    ///
    /// A receipt outlives nothing: deleting the employee (or the punch) it
    /// points at leaves a row that will be rejected on every run from here
    /// to the end of time. Employee-orphans are deleted outright; a missing
    /// punch just loses the optional back-reference.
    private func pruneOrphanedReceipts(_ receipts: [MessageReceipt]) -> [MessageReceipt] {
        let employeeIDs = Set(employeeIndex().keys)
        var changed = false

        let survivors = receipts.filter { receipt in
            guard employeeIDs.contains(receipt.employeeID) else {
                context.delete(receipt)
                changed = true
                return false
            }
            if let punchID = receipt.punchID, punch(withID: punchID) == nil {
                receipt.punchID = nil
                changed = true
            }
            return true
        }

        if changed { try? context.save() }
        return survivors
    }

    // MARK: - Heartbeat

    /// Status row the office dashboard reads. Built from state that is
    /// already settled for this run — counts refreshed after the push,
    /// `lastError` after it has been cleared — so a clean run reports itself
    /// as clean instead of echoing the previous run's failure.
    private func sendHeartbeat() async throws {
        let status = KioskStatusPush(
            id: SupabaseConfig.kioskID,
            lastSeenAt: Date(),
            appVersion: SupabaseConfig.appVersion,
            pendingPush: pendingTotal,
            detail: KioskStatusPush.Detail(
                employees: pendingEmployees,
                punches: pendingPunches,
                receipts: pendingReceipts,
                deletions: pendingDeletions,
                lastError: lastError
            )
        )
        try await api.upsert(table: SupabaseTable.kioskStatus, rows: [status], onConflict: "id")
    }

    // MARK: - Bookkeeping

    func refreshPendingCounts() {
        pendingEmployees = count(FetchDescriptor<Employee>(predicate: #Predicate { $0.needsSync == true }))
        pendingPunches = count(FetchDescriptor<PunchLog>(predicate: #Predicate { $0.needsSync == true }))
        pendingReceipts = count(FetchDescriptor<MessageReceipt>(predicate: #Predicate { $0.needsSync == true }))
        pendingDeletions = count(FetchDescriptor<PendingDeletion>())
    }

    private func count<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }

    private func advanceWatermark(to observed: Date?) {
        // Only a timestamp Postgres actually produced may move the mark.
        // Deriving one from the device clock looks harmless — it saves
        // re-requesting an empty delta — but an iPad whose clock runs even a
        // few minutes fast would push the watermark past every row the
        // server is about to write, and pulls would silently stop returning
        // anything ever again. An empty delta query is cheap; that is not.
        guard let observed else { return }
        if observed > SupabaseConfig.pullWatermark {
            SupabaseConfig.pullWatermark = observed
        }
    }

    private func punch(withID id: UUID) -> PunchLog? {
        var descriptor = FetchDescriptor<PunchLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func chunk<T>(_ items: [T]) -> [[T]] {
        guard items.count > Self.batchSize else { return [items] }
        return stride(from: 0, to: items.count, by: Self.batchSize).map {
            Array(items[$0..<min($0 + Self.batchSize, items.count)])
        }
    }

    private func describe(_ error: any Error) -> String {
        if let supabase = error as? SupabaseError { return supabase.message }
        return error.localizedDescription
    }
}
