import SwiftUI
import SwiftData

struct VerificationView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Cached studio announcements. The whole table is a handful of rows,
    /// so it's cheaper to fetch them all and filter in Swift than to build
    /// a predicate for the optional personal-target column.
    @Query(sort: [SortDescriptor(\KioskMessage.sortOrder)])
    private var cachedMessages: [KioskMessage]

    let employeeID: UUID
    let missedPunchFrom: Date?

    @State private var employee: Employee?

    // Clock-in inputs. `selectedShiftRole` is nil only while a "both"
    // profile is picking which side they are working today; profiles that
    // can only ever work one side pre-fill it on appear.
    @State private var selectedShiftRole: ShiftRole?
    @State private var scheduledClasses: Int = 0

    // Clock-out inputs. Cached pointer to the active shift so we can read
    // its `shiftRole` / `scheduledClasses` to decide which questions to
    // ask, and an answer slot per class for the no-shows survey.
    @State private var openLog: PunchLog?
    @State private var classSurvey: [Bool?] = []

    private var isCompact: Bool { hSizeClass == .compact }

    /// Treat a missed punch as a brand-new clock-in: the prior shift is
    /// going to be force-closed in `confirm()`, and the kiosk should ask
    /// the role/classes questions for the *new* shift.
    private var isClockIn: Bool {
        guard let employee else { return true }
        if missedPunchFrom != nil { return true }
        return !employee.isCurrentlyClockedIn
    }

    private var action: String {
        guard employee != nil else { return "…" }
        return isClockIn ? "Clock In" : "Clock Out"
    }

    /// Effective role for the screen. During clock-in this is whatever the
    /// user has picked (or had auto-picked); during clock-out this is the
    /// role baked into the open shift, regardless of their profile (a
    /// "both" employee may have clocked in as a coordinator yesterday).
    private var effectiveShiftRole: ShiftRole? {
        if isClockIn { return selectedShiftRole }
        return openLog?.shiftRole
    }

    /// Announcements this specific person should see on this specific
    /// punch. Recomputed on every render, so a "both" employee tapping
    /// Instructor immediately reveals the instructor-only notices.
    private var applicableMessages: [KioskMessage] {
        guard let employee else { return [] }
        let now = Date()
        return cachedMessages
            .filter { $0.applies(to: employee, shiftRole: effectiveShiftRole, on: now) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var canConfirm: Bool {
        if isClockIn {
            // "Both" employees must pick a side before confirming. The
            // scheduled-classes picker has a default of 1, which is a
            // valid answer, so it never blocks confirmation.
            return selectedShiftRole != nil
        }
        // Clock-out: instructor shifts with scheduled classes need every
        // survey question answered before payroll can be computed.
        if effectiveShiftRole == .instructor && !classSurvey.isEmpty {
            return classSurvey.allSatisfy { $0 != nil }
        }
        return true
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let photoSize: CGFloat = isCompact ? min(160, w * 0.42) : 220
            let nameSize: CGFloat = isCompact ? 28 : 40
            let statusSize: CGFloat = isCompact ? 14 : 17
            let confirmTextSize: CGFloat = isCompact ? 17 : 22
            let confirmIconSize: CGFloat = isCompact ? 22 : 28
            let hPad: CGFloat = isCompact ? 24 : 48

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if let employee {
                    ScrollView {
                        VStack(spacing: isCompact ? 18 : 24) {
                            photo(for: employee, size: photoSize)

                            VStack(spacing: 8) {
                                Text(employee.fullName)
                                    .font(.system(size: nameSize, weight: .black, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                Text(statusLine(for: employee))
                                    .font(.system(size: statusSize, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textMuted)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, hPad)

                            if let missed = missedPunchFrom {
                                missedPunchAlert(date: missed)
                            }

                            // Studio announcements sit above the questions:
                            // they're context the employee may need *before*
                            // answering (e.g. "3rd class is cancelled today").
                            ForEach(applicableMessages) { message in
                                AnnouncementCard(message: message)
                            }

                            // Conditional question cards (clock-in side).
                            if isClockIn {
                                if employee.profileRole == .both {
                                    shiftRoleChooser
                                }
                                if effectiveShiftRole == .instructor {
                                    scheduledClassesPicker
                                }
                            }

                            // Conditional survey card (clock-out side).
                            if !isClockIn,
                               effectiveShiftRole == .instructor,
                               !classSurvey.isEmpty {
                                classSurveyCard
                            }

                            VStack(spacing: 14) {
                                Button(action: confirm) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: confirmIconSize, weight: .bold))
                                        Text("Confirm — \(action)")
                                            .font(.system(size: confirmTextSize, weight: .bold, design: .rounded))
                                            .tracking(1)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .frame(maxWidth: 540)
                                .disabled(!canConfirm)
                                .opacity(canConfirm ? 1 : 0.5)

                                Button(role: .cancel) {
                                    coordinator.goHome()
                                } label: {
                                    Text(isCompact ? "Not me — Cancel" : "That's not me — Cancel")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .frame(maxWidth: 540)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .padding(.vertical, isCompact ? 16 : 24)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView().tint(Theme.text)
                }
            }
            .onTapGesture { coordinator.userActivity() }
        }
        .onAppear(perform: loadEmployee)
    }

    // MARK: - Pieces

    private func photo(for employee: Employee, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: size + 14, height: size + 14)
                .shadow(color: Theme.gold.opacity(0.4), radius: 24, y: 10)

            if let img = PhotoStorage.load(fileName: employee.photoFileName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(Theme.textFaint)
                    )
            }
        }
    }

    private var shiftRoleChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Are you clocking in as an Instructor or a Coordinator for this shift?")
                .font(.system(size: isCompact ? 16 : 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                roleButton(role: .instructor)
                roleButton(role: .coordinator)
            }
        }
        .card()
        .frame(maxWidth: 540)
    }

    private func roleButton(role: ShiftRole) -> some View {
        let isSelected = selectedShiftRole == role
        return Button {
            Feedback.tap()
            selectedShiftRole = role
            // Coordinator shifts never ask the classes question, so reset
            // any half-completed selection if the user flips back and forth.
            if role == .coordinator {
                scheduledClasses = 0
            } else {
                scheduledClasses = 1
            }
            coordinator.userActivity()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: role == .instructor ? "figure.yoga" : "person.2.badge.gearshape")
                    .font(.system(size: 28, weight: .bold))
                Text(role.displayName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.clear : Theme.surfaceStroke, lineWidth: 1.5)
                    )
            )
        }
    }

    private var scheduledClassesPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How many classes are you scheduled to teach today?")
                .font(.system(size: isCompact ? 16 : 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)

            Picker("Scheduled classes", selection: $scheduledClasses) {
                ForEach(1...3, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)
        }
        .card()
        .frame(maxWidth: 540)
    }

    private var classSurveyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(classSurvey.count == 1
                 ? "Did you teach your scheduled class?"
                 : "Did you teach each of your scheduled classes?")
                .font(.system(size: isCompact ? 16 : 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            Text("If a class had no students, count it as **not taught**.")
                .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)

            VStack(spacing: 10) {
                ForEach(classSurvey.indices, id: \.self) { idx in
                    surveyRow(index: idx)
                }
            }
        }
        .card()
        .frame(maxWidth: 540)
    }

    private func surveyRow(index: Int) -> some View {
        let label: String = classSurvey.count == 1
            ? "Did you teach your scheduled class?"
            : "Did you teach your \(ordinal(index + 1)) class?"
        let answer = classSurvey[index]

        return HStack(spacing: 12) {
            Text(label)
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                surveyChoice(label: "Yes", isOn: answer == true) {
                    classSurvey[index] = true
                }
                surveyChoice(label: "No", isOn: answer == false) {
                    classSurvey[index] = false
                }
            }
        }
    }

    private func surveyChoice(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
            coordinator.userActivity()
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(isOn ? Theme.text : Theme.textMuted)
                .frame(minWidth: 64)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isOn ? Color.clear : Theme.surfaceStroke, lineWidth: 1.5)
                        )
                )
        }
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func statusLine(for employee: Employee) -> String {
        if missedPunchFrom != nil { return "Missed punch detected — see below." }
        if employee.isCurrentlyClockedIn {
            if let openLog = employee.punchLogs
                .filter({ $0.isOpen })
                .sorted(by: { $0.clockInTime > $1.clockInTime })
                .first {
                let opened = "Clocked in since \(timeString(openLog.clockInTime))"
                return "\(opened) · \(openLog.shiftRole.displayName)"
            }
            return "Currently clocked in"
        }
        return "Tap to clock in"
    }

    private func missedPunchAlert(date: Date) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Missed Clock-Out")
                    .font(.system(size: isCompact ? 14 : 16, weight: .heavy, design: .rounded))
                    .tracking(2)
            }
            .foregroundStyle(Theme.text)

            Text("You did not clock out of your last shift (started \(fullDateString(date))). Please see an admin. That shift will be closed now and a new clock-in will begin.")
                .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.text.opacity(0.85))
        }
        .padding(isCompact ? 14 : 18)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.4), radius: 18, y: 6)
        )
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func fullDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Data

    private func loadEmployee() {
        let loaded = EmployeeLookup.byID(employeeID, in: modelContext)
        employee = loaded
        guard let loaded else { return }

        // Pre-fill the inputs based on what side of the punch we're on.
        // Doing this in `onAppear` (vs. computed property) keeps the
        // segmented controls bindable directly to @State.
        if isClockIn {
            // Profiles with only one possible role get the answer pre-filled
            // so the picker is auto-skipped; "both" stays nil until the
            // user makes a choice on screen.
            switch loaded.profileRole {
            case .instructor:
                selectedShiftRole = .instructor
                scheduledClasses = 1
            case .coordinator:
                selectedShiftRole = .coordinator
                scheduledClasses = 0
            case .both:
                selectedShiftRole = nil
                scheduledClasses = 1
            }
            openLog = nil
            classSurvey = []
        } else {
            // Clock-out: pull the active shift and pre-size the survey.
            let active = loaded.punchLogs
                .filter { $0.isOpen }
                .sorted { $0.clockInTime > $1.clockInTime }
                .first
            openLog = active
            if let active, active.shiftRole == .instructor, active.scheduledClasses > 0 {
                classSurvey = Array(repeating: nil, count: active.scheduledClasses)
            } else {
                classSurvey = []
            }
        }
    }

    /// Records that this employee actually saw each announcement rendered
    /// on the screen they just confirmed, linked to the punch it happened
    /// on. Written locally and pushed later — the receipt must survive a
    /// studio with no Wi-Fi just as reliably as the punch does.
    private func recordReceipts(
        for employee: Employee,
        shown: [KioskMessage],
        punchID: UUID?
    ) {
        let employeeID = employee.id
        for message in shown {
            let messageID = message.id
            // A shift shows the same announcement twice — once on the way
            // in, once on the way out — and both confirmations point at the
            // same punch. One receipt per (message, employee, punch) keeps
            // that from looking like the notice was read twice.
            if let punchID {
                var descriptor = FetchDescriptor<MessageReceipt>(
                    predicate: #Predicate {
                        $0.messageID == messageID &&
                        $0.employeeID == employeeID &&
                        $0.punchID == punchID
                    }
                )
                descriptor.fetchLimit = 1
                if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty { continue }
            }
            modelContext.insert(
                MessageReceipt(
                    messageID: messageID,
                    employeeID: employeeID,
                    punchID: punchID
                )
            )
        }
    }

    private func confirm() {
        guard let employee else { return }
        guard canConfirm else { return }
        coordinator.userActivity()

        // Snapshot before any state changes — after the punch commits the
        // role selection is gone and the filter would produce a different
        // (wrong) set.
        let shownMessages = applicableMessages

        if missedPunchFrom != nil {
            // Force-close any still-open prior shifts to the end of the day
            // they began, then start a new shift using the role/classes the
            // user just supplied for this clock-in.
            let openLogs = employee.punchLogs.filter { $0.isOpen }
            let endOfDay = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: openLogs.first?.clockInTime ?? Date()
            ) ?? Date()
            for log in openLogs {
                log.clockOutTime = endOfDay
                log.wasForcedOut = true
                log.markDirty()
            }
            let role = selectedShiftRole ?? .instructor
            let newLog = PunchLog(
                employee: employee,
                clockInTime: Date(),
                shiftRole: role,
                scheduledClasses: role == .instructor ? scheduledClasses : 0
            )
            modelContext.insert(newLog)
            newLog.markDirty()
            // `isCurrentlyClockedIn` is local bookkeeping with no server
            // column, so the employee row is *not* dirtied — doing so would
            // push a stale copy of their profile on every punch and stomp
            // whatever the portal edited in the meantime.
            employee.isCurrentlyClockedIn = true
            recordReceipts(for: employee, shown: shownMessages, punchID: newLog.id)
            try? modelContext.save()
            Feedback.success()
            syncEngine.syncAfterPunch()
            coordinator.go(to: .punchSuccess(
                name: employee.fullName,
                didClockIn: true,
                employeeID: employee.id,
                punchID: newLog.id
            ))
            return
        }

        if employee.isCurrentlyClockedIn {
            // Clock-out path. Tally the survey before closing the shift so
            // payroll can read `actualClassesTaught` directly.
            var closedPunchID: UUID?
            if let active = openLog ?? employee.punchLogs
                .filter({ $0.isOpen })
                .sorted(by: { $0.clockInTime > $1.clockInTime })
                .first {
                if active.shiftRole == .instructor && !classSurvey.isEmpty {
                    let yes = classSurvey.compactMap { $0 }.filter { $0 }.count
                    active.actualClassesTaught = yes
                } else if active.shiftRole == .coordinator {
                    // No questions asked of coordinators — payroll uses
                    // wall-clock time. Make sure stale class counts from a
                    // mistaken edit don't survive into the export.
                    active.actualClassesTaught = 0
                }
                active.clockOutTime = Date()
                active.markDirty()
                closedPunchID = active.id
            }
            // Local flag only — see the clock-in path above.
            employee.isCurrentlyClockedIn = false
            recordReceipts(for: employee, shown: shownMessages, punchID: closedPunchID)
            try? modelContext.save()
            Feedback.success()
            syncEngine.syncAfterPunch()
            coordinator.go(to: .punchSuccess(
                name: employee.fullName,
                didClockIn: false,
                employeeID: employee.id,
                punchID: closedPunchID
            ))
        } else {
            // Plain clock-in path.
            let role = selectedShiftRole ?? .instructor
            let log = PunchLog(
                employee: employee,
                clockInTime: Date(),
                shiftRole: role,
                scheduledClasses: role == .instructor ? scheduledClasses : 0
            )
            modelContext.insert(log)
            log.markDirty()
            // Local flag only — see the missed-punch path above.
            employee.isCurrentlyClockedIn = true
            recordReceipts(for: employee, shown: shownMessages, punchID: log.id)
            try? modelContext.save()
            Feedback.success()
            syncEngine.syncAfterPunch()
            coordinator.go(to: .punchSuccess(
                name: employee.fullName,
                didClockIn: true,
                employeeID: employee.id,
                punchID: log.id
            ))
        }
    }
}

/// Announcement card. Uses the same rounded-surface `.card()` shell as the
/// question cards so it reads as part of the same screen, with a gold accent
/// bar + megaphone to mark it as information rather than something the
/// employee has to answer. Shared between the verification screen (where it
/// is passive) and the success screen (where it gates the reset), so the two
/// can never drift into looking like different kinds of notice.
struct AnnouncementCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let message: KioskMessage

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text(message.title.isEmpty ? "Studio Announcement" : message.title)
                        .font(.system(size: isCompact ? 15 : 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                }

                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.system(size: isCompact ? 13 : 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .card()
        .frame(maxWidth: 540)
    }
}

struct PunchSuccessView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// How long the kiosk waits before resetting itself when there is
    /// nothing to acknowledge — just long enough to read your own name.
    private static let autoDismissDelay: TimeInterval = 2.5

    /// Safety net for the acknowledgement state. The screen is meant to be
    /// dismissed by a human tapping "Got it", but someone who badges in and
    /// walks straight to the studio floor must not leave the kiosk parked on
    /// their name. Generous enough to actually read a notice.
    private static let acknowledgeTimeout: TimeInterval = 60

    let name: String
    let didClockIn: Bool
    /// Identify the punch that just happened so the screen can find the
    /// receipts written for it. Nil from call sites with nothing to
    /// acknowledge (registration), which lands on the plain 2.5s behaviour.
    let employeeID: UUID?
    let punchID: UUID?

    @State private var show = false

    /// Announcements shown on this punch that this employee has never
    /// acknowledged, with the matching receipts to stamp on "Got it".
    /// Snapshotted once in `onAppear` — the punch is already committed, so
    /// nothing on screen should change underneath the person reading it.
    @State private var pendingMessages: [KioskMessage] = []
    @State private var pendingReceipts: [MessageReceipt] = []

    /// Held so a second punch arriving while this one is still on screen
    /// can't leave an older timer alive to reset the kiosk out from under it.
    @State private var dismissTask: Task<Void, Never>?

    private var isCompact: Bool { hSizeClass == .compact }

    private var needsAcknowledgement: Bool { !pendingMessages.isEmpty }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let circleSize: CGFloat = isCompact ? min(180, w * 0.5) : 220
            let iconSize: CGFloat = circleSize * 0.5
            let titleSize: CGFloat = isCompact ? 36 : 48
            let messageSize: CGFloat = isCompact ? 17 : 20

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                let content = VStack(spacing: isCompact ? 24 : 32) {
                    ZStack {
                        Circle()
                            .fill(Theme.brandGradient)
                            .frame(width: circleSize, height: circleSize)
                            .shadow(color: Theme.gold.opacity(0.5), radius: 30, y: 12)
                            .scaleEffect(show ? 1 : 0.5)
                            .opacity(show ? 1 : 0)
                        Image(systemName: didClockIn ? "checkmark" : "hand.wave.fill")
                            .font(.system(size: iconSize, weight: .black))
                            .foregroundStyle(Theme.text)
                            .scaleEffect(show ? 1 : 0.2)
                            .opacity(show ? 1 : 0)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.6), value: show)

                    VStack(spacing: 6) {
                        Text(didClockIn ? "Clocked In" : "Clocked Out")
                            .font(.system(size: titleSize, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(didClockIn ? "Have a great class, \(name)!" : "Thanks for teaching, \(name)!")
                            .font(.system(size: messageSize, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }

                    // The punch itself is already committed — these cards are
                    // the only reason the screen is still up.
                    ForEach(pendingMessages) { message in
                        AnnouncementCard(message: message)
                    }

                    if needsAcknowledgement {
                        Button(action: acknowledge) {
                            Text("Got it")
                                .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .rounded))
                                .tracking(1)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 540)
                    }
                }
                .padding(.horizontal, isCompact ? 24 : 32)
                .frame(maxWidth: .infinity)

                // A long announcement on a compact device can outgrow the
                // screen, so the gated state scrolls; the plain success
                // state keeps its centred, non-scrolling layout.
                if needsAcknowledgement {
                    ScrollView {
                        content.padding(.vertical, isCompact ? 24 : 32)
                    }
                } else {
                    content.frame(maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            show = true
            // The load result is threaded through explicitly rather than
            // re-read from `pendingMessages`, so the timer length can never
            // depend on when SwiftUI publishes the state write.
            startDismissTimer(gated: loadPendingAcknowledgements())
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    // MARK: - Acknowledgement

    /// Finds the announcements this punch displayed that the employee has
    /// never acknowledged on *any* punch. Once someone has tapped "Got it"
    /// on a notice it keeps appearing on the verification screen but stops
    /// gating the kiosk — nobody should have to dismiss the same sign twice.
    /// Returns whether anything ended up needing acknowledgement.
    @discardableResult
    private func loadPendingAcknowledgements() -> Bool {
        guard let employeeID, let punchID else { return false }

        var mine = FetchDescriptor<MessageReceipt>(
            predicate: #Predicate<MessageReceipt> {
                $0.employeeID == employeeID && $0.punchID == punchID
            }
        )
        mine.fetchLimit = 50
        let thisPunch = (try? modelContext.fetch(mine)) ?? []
        guard !thisPunch.isEmpty else { return false }

        let acknowledged = (try? modelContext.fetch(
            FetchDescriptor<MessageReceipt>(
                predicate: #Predicate<MessageReceipt> {
                    $0.employeeID == employeeID && $0.acknowledgedAt != nil
                }
            )
        )) ?? []
        let acknowledgedIDs = Set(acknowledged.map(\.messageID))

        let unacknowledged = thisPunch.filter { !acknowledgedIDs.contains($0.messageID) }
        guard !unacknowledged.isEmpty else { return false }

        // Receipts survive the message they point at (the portal can delete
        // an announcement at any time), so the card list is driven by the
        // messages that still exist and the receipts follow from those.
        let wanted = Set(unacknowledged.map(\.messageID))
        let messages = (try? modelContext.fetch(
            FetchDescriptor<KioskMessage>(sortBy: [SortDescriptor(\KioskMessage.sortOrder)])
        )) ?? []
        pendingMessages = messages.filter { wanted.contains($0.id) }

        let shownIDs = Set(pendingMessages.map(\.id))
        pendingReceipts = unacknowledged.filter { shownIDs.contains($0.messageID) }
        return !pendingMessages.isEmpty
    }

    /// One timer, replaced rather than stacked, so a rapid second punch can
    /// never inherit the previous screen's countdown.
    private func startDismissTimer(gated: Bool) {
        dismissTask?.cancel()
        let delay = gated ? Self.acknowledgeTimeout : Self.autoDismissDelay
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            coordinator.goHome()
        }
    }

    private func acknowledge() {
        dismissTask?.cancel()
        dismissTask = nil
        Feedback.tap()

        let now = Date()
        for receipt in pendingReceipts {
            receipt.acknowledgedAt = now
            // Re-dirtied even when the seen-only version already reached the
            // server: the push is a whole-row upsert, so the next run simply
            // overwrites that row with the acknowledged one.
            receipt.needsSync = true
        }
        try? modelContext.save()
        syncEngine.syncAfterPunch()
        coordinator.goHome()
    }
}
