import SwiftUI
import SwiftData
import Combine

/// Audit / housekeeping section. Surfaces shifts that are still open
/// past the 12-hour threshold (probable forgotten clock-outs), and lets
/// the admin add a missing punch retroactively for an employee who
/// forgot their card.
struct AdminAuditView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query private var employees: [Employee]
    @Query(sort: [SortDescriptor(\PunchLog.clockInTime, order: .reverse)])
    private var allLogs: [PunchLog]

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @State private var showingManualAdd = false

    private var isCompact: Bool { hSizeClass == .compact }

    private var missedPunches: [PunchLog] {
        let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
        return allLogs
            .filter { $0.isOpen && $0.clockInTime < twelveHoursAgo }
            .sorted { $0.clockInTime < $1.clockInTime }
    }

    private var openShifts: [PunchLog] {
        allLogs.filter { $0.isOpen && !missedPunches.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                missedCard
                openShiftsCard
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingManualAdd = true
                } label: {
                    Label("Add Punch", systemImage: "plus.circle.fill")
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .sheet(isPresented: $showingManualAdd) {
            ManualPunchAddView()
        }
    }

    // MARK: - Cards

    private var missedCard: some View {
        DashboardCard(
            "Missed Punches (> 12 h)",
            trailing: AnyView(
                Text("\(missedPunches.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(missedPunches.isEmpty ? Theme.textFaint : Theme.warning)
            )
        ) {
            if missedPunches.isEmpty {
                emptyMissed
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(missedPunches) { log in
                        missedRow(log)
                    }
                }
            }
        }
    }

    private var emptyMissed: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.success)
            Text("Nothing flagged.")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 8)
    }

    private func missedRow(_ log: PunchLog) -> some View {
        let elapsed = now.timeIntervalSince(log.clockInTime)

        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.warning)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.warning.opacity(0.18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(log.employee?.displayName ?? "—")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("Clocked in \(DurationFormat.short(elapsed)) ago")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            Button {
                forceOut(log)
            } label: {
                Text("Force Out")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.gold))
            }
            .buttonStyle(.plain)

            NavigationLink {
                PunchLogEditView(log: log)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.warning.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var openShiftsCard: some View {
        DashboardCard("Open Shifts (< 12 h)") {
            if openShifts.isEmpty {
                Text("No other open shifts right now.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(openShifts) { log in
                        NavigationLink {
                            PunchLogEditView(log: log)
                        } label: {
                            openRow(log)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func openRow(_ log: PunchLog) -> some View {
        let elapsed = now.timeIntervalSince(log.clockInTime)

        return HStack(spacing: 12) {
            if let emp = log.employee {
                EmployeeAvatar(employee: emp, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(log.employee?.displayName ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("On clock \(DurationFormat.short(elapsed))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.success)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func forceOut(_ log: PunchLog) {
        log.clockOutTime = now
        log.wasForcedOut = true
        log.employee?.isCurrentlyClockedIn = false
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast(
            "Forced out \(log.employee?.displayName ?? "shift").",
            style: .success
        )
    }
}

/// Sheet for retroactively recording a punch on behalf of an instructor
/// who forgot their card. When `prefilledEmployee` is non-nil the picker
/// is hidden and the punch is locked to that employee — used by the
/// detail view's "Add Punch" affordance.
struct ManualPunchAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var coordinator

    @Query(sort: [SortDescriptor(\Employee.firstName), SortDescriptor(\Employee.lastName)])
    private var employees: [Employee]

    var prefilledEmployee: Employee? = nil

    @State private var selectedEmployeeID: UUID?
    @State private var clockIn: Date = Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now
    @State private var hasClockOut: Bool = true
    @State private var clockOut: Date = .now
    @State private var saveError: String?

    private var eligible: [Employee] {
        if let prefilledEmployee {
            return [prefilledEmployee]
        }
        return employees.filter { $0.isActive && $0.hasAssignedCard }
    }

    private var canSave: Bool {
        guard let id = selectedEmployeeID,
              eligible.contains(where: { $0.id == id }) else { return false }
        if hasClockOut { return clockOut > clockIn }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if prefilledEmployee == nil {
                    Section("Instructor") {
                        Picker("Instructor", selection: $selectedEmployeeID) {
                            Text("Select…").tag(UUID?.none)
                            ForEach(eligible) { emp in
                                Text(emp.displayName).tag(Optional(emp.id))
                            }
                        }
                    }
                }

                Section("Times") {
                    DatePicker("Clock In", selection: $clockIn)
                    Toggle("Add Clock Out", isOn: $hasClockOut)
                    if hasClockOut {
                        DatePicker("Clock Out", selection: $clockOut, in: clockIn...)
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(prefilledEmployee.map { "Add Punch — \($0.displayName)" } ?? "Add Punch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let prefilledEmployee, selectedEmployeeID == nil {
                    selectedEmployeeID = prefilledEmployee.id
                }
            }
        }
    }

    private func commit() {
        guard let id = selectedEmployeeID,
              let employee = eligible.first(where: { $0.id == id }) else { return }

        let log = PunchLog(
            employee: employee,
            clockInTime: clockIn,
            clockOutTime: hasClockOut ? clockOut : nil
        )
        modelContext.insert(log)
        if !hasClockOut {
            employee.isCurrentlyClockedIn = true
        }

        do {
            try modelContext.save()
            Feedback.success()
            coordinator.showToast("Punch added for \(employee.displayName).", style: .success)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            Feedback.error()
        }
    }
}
