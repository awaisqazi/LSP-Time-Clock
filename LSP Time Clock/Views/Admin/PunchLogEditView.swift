import SwiftUI
import SwiftData

/// Manual punch-log editor. Lets the admin correct a clock-in/clock-out
/// time, close out an open shift, or delete a stray punch entirely.
struct PunchLogEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var coordinator

    let log: PunchLog

    @State private var clockIn: Date = .now
    @State private var hasClockOut: Bool = false
    @State private var clockOut: Date = .now
    @State private var wasForcedOut: Bool = false
    @State private var shiftRole: ShiftRole = .instructor
    @State private var scheduledClasses: Int = 0
    @State private var actualClassesTaught: Int = 0
    @State private var showingDeleteConfirm = false
    @State private var saveError: String?

    private var canSave: Bool {
        if hasClockOut, clockOut <= clockIn { return false }
        // Sanity check: you can't have actually taught more classes than
        // you scheduled. Coordinator shifts force both class counters to
        // 0 on save, so they're never blocked by this rule.
        if shiftRole == .instructor, actualClassesTaught > scheduledClasses { return false }
        return true
    }

    private var hasChanges: Bool {
        clockIn != log.clockInTime ||
        hasClockOut != (log.clockOutTime != nil) ||
        (hasClockOut && clockOut != (log.clockOutTime ?? clockOut)) ||
        wasForcedOut != log.wasForcedOut ||
        shiftRole != log.shiftRole ||
        scheduledClasses != log.scheduledClasses ||
        actualClassesTaught != log.actualClassesTaught
    }

    var body: some View {
        NavigationStack {
            Form {
                if let employee = log.employee {
                    Section("Instructor") {
                        HStack(spacing: 12) {
                            EmployeeAvatar(employee: employee, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(employee.displayName)
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                if !employee.role.isEmpty {
                                    Text(employee.role)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                        }
                    }
                }

                // Notes are authored in the web portal, never here — the
                // kiosk shows them so an admin correcting a punch can see
                // why payroll flagged it, but editing stays on the desktop
                // where there's a real keyboard.
                if !log.note.isEmpty {
                    Section("Note from the office") {
                        Text(log.note)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                Section("Clock In") {
                    DatePicker("Time", selection: $clockIn)
                }

                Section("Clock Out") {
                    Toggle("Has Clock Out", isOn: $hasClockOut)
                    if hasClockOut {
                        DatePicker("Time", selection: $clockOut, in: clockIn...)
                        Toggle("Forced Out", isOn: $wasForcedOut)
                    }
                }

                Section("Shift Role") {
                    Picker("Worked As", selection: $shiftRole) {
                        ForEach(ShiftRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: shiftRole) { _, newRole in
                        if newRole == .instructor && scheduledClasses == 0 {
                            scheduledClasses = 1
                        }
                    }
                }

                if shiftRole == .instructor {
                    Section("Classes") {
                        Picker("Scheduled", selection: $scheduledClasses) {
                            ForEach(1...3, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        Picker("Actually Taught", selection: $actualClassesTaught) {
                            // Cap the picker at the number scheduled so the
                            // admin can't accidentally enter something the
                            // model rejects (canSave guards this too).
                            ForEach(0...max(scheduledClasses, 0), id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        Text("If a class had no students, count it as not taught.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .onChange(of: scheduledClasses) { _, newValue in
                        if actualClassesTaught > newValue {
                            actualClassesTaught = newValue
                        }
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Punch", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Punch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .disabled(!canSave || !hasChanges)
                }
            }
            .onAppear(perform: loadFromLog)
            .alert("Delete this punch?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deletePunch() }
            } message: {
                Text("This permanently removes the punch record. The instructor's clocked-in status will be re-synced.")
            }
        }
    }

    private func loadFromLog() {
        clockIn = log.clockInTime
        hasClockOut = log.clockOutTime != nil
        clockOut = log.clockOutTime ?? .now
        wasForcedOut = log.wasForcedOut
        shiftRole = log.shiftRole
        scheduledClasses = log.scheduledClasses
        actualClassesTaught = log.actualClassesTaught
    }

    private func commit() {
        guard canSave else { return }

        log.clockInTime = clockIn
        log.clockOutTime = hasClockOut ? clockOut : nil
        log.wasForcedOut = hasClockOut ? wasForcedOut : false
        log.shiftRole = shiftRole
        // Coordinator shifts have no class concept; zero both counters out
        // on save so a stale instructor-side value can't leak into payroll
        // after an admin reclassified the punch.
        if shiftRole == .coordinator {
            log.scheduledClasses = 0
            log.actualClassesTaught = 0
        } else {
            log.scheduledClasses = scheduledClasses
            log.actualClassesTaught = actualClassesTaught
        }
        log.markDirty()

        // Re-sync the employee's "currently clocked in" flag to their
        // newest open shift (if any). This avoids stale state when an
        // admin closes out the only open shift. Local bookkeeping with no
        // server column, so the employee row is deliberately left clean —
        // marking it dirty would push a stale profile over the portal's.
        if let employee = log.employee {
            employee.isCurrentlyClockedIn = employee.punchLogs.contains(where: { $0.isOpen })
        }

        do {
            try modelContext.save()
            Feedback.success()
            coordinator.showToast("Punch updated.", style: .success)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            Feedback.error()
        }
    }

    private func deletePunch() {
        let employee = log.employee
        // Enqueue the tombstone while the row still exists — see
        // `PendingDeletion` for why a hard delete is otherwise invisible
        // to the cloud.
        SyncDeletionQueue.enqueuePunch(log, in: modelContext)
        modelContext.delete(log)
        if let employee {
            // Local flag only — see `commit()`.
            employee.isCurrentlyClockedIn = employee.punchLogs.contains(where: { $0 !== log && $0.isOpen })
        }
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("Punch deleted.", style: .success)
        dismiss()
    }
}
