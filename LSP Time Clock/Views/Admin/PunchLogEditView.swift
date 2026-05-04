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
    @State private var showingDeleteConfirm = false
    @State private var saveError: String?

    private var canSave: Bool {
        if hasClockOut { return clockOut > clockIn }
        return true
    }

    private var hasChanges: Bool {
        clockIn != log.clockInTime ||
        hasClockOut != (log.clockOutTime != nil) ||
        (hasClockOut && clockOut != (log.clockOutTime ?? clockOut)) ||
        wasForcedOut != log.wasForcedOut
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
    }

    private func commit() {
        guard canSave else { return }

        log.clockInTime = clockIn
        log.clockOutTime = hasClockOut ? clockOut : nil
        log.wasForcedOut = hasClockOut ? wasForcedOut : false

        // Re-sync the employee's "currently clocked in" flag to their
        // newest open shift (if any). This avoids stale state when an
        // admin closes out the only open shift.
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
        modelContext.delete(log)
        if let employee {
            employee.isCurrentlyClockedIn = employee.punchLogs.contains(where: { $0 !== log && $0.isOpen })
        }
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("Punch deleted.", style: .success)
        dismiss()
    }
}
