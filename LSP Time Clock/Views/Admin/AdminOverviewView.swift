import SwiftUI
import SwiftData
import Combine

/// Overview / "at-a-glance" dashboard. The first thing an admin sees when
/// they unlock the kiosk: who's on the clock, how many hours have been
/// tracked this week, and which shifts look forgotten.
struct AdminOverviewView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query private var employees: [Employee]
    @Query private var allLogs: [PunchLog]

    /// Caller hook so the overview can deep-link into another sidebar
    /// section (e.g. "See all 4 missed punches" → audit tab).
    var switchTo: (AdminSection) -> Void

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var isCompact: Bool { hSizeClass == .compact }

    private var activeEmployees: [Employee] { employees.filter { $0.isActive } }

    private var clockedIn: [Employee] {
        activeEmployees
            .filter { $0.isCurrentlyClockedIn }
            .sorted { lhs, rhs in
                (openShift(for: lhs)?.clockInTime ?? .distantFuture)
                    < (openShift(for: rhs)?.clockInTime ?? .distantFuture)
            }
    }

    private var hoursThisWeek: Double {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return allLogs
            .filter { $0.clockInTime >= weekStart }
            .compactMap { $0.totalHours }
            .reduce(0, +)
    }

    private var punchesToday: Int {
        let cal = Calendar.current
        return allLogs.reduce(0) { acc, log in
            var add = 0
            if cal.isDateInToday(log.clockInTime) { add += 1 }
            if let out = log.clockOutTime, cal.isDateInToday(out) { add += 1 }
            return acc + add
        }
    }

    private var missedPunches: [PunchLog] {
        let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
        return allLogs
            .filter { $0.isOpen && $0.clockInTime < twelveHoursAgo }
            .sorted { $0.clockInTime < $1.clockInTime }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricsGrid
                clockedInCard
                if !missedPunches.isEmpty {
                    missedPunchesCard
                }
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Sections

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
            spacing: 16
        ) {
            MetricTile(
                title: "Currently On-Site",
                value: "\(clockedIn.count)",
                icon: "person.fill.checkmark",
                tint: Theme.success
            )
            MetricTile(
                title: "Hours This Week",
                value: String(format: "%.1f", hoursThisWeek),
                icon: "clock.fill",
                tint: Theme.gold
            )
            MetricTile(
                title: "Punches Today",
                value: "\(punchesToday)",
                icon: "wave.3.right",
                tint: Theme.tan
            )
            MetricTile(
                title: "Active Roster",
                value: "\(activeEmployees.count)",
                icon: "person.2.fill",
                tint: Theme.text
            )
        }
    }

    private var clockedInCard: some View {
        DashboardCard("Currently Clocked In") {
            if clockedIn.isEmpty {
                emptyClockedIn
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(clockedIn) { emp in
                        Button {
                            coordinator.go(to: .adminEmployeeDetail(employeeID: emp.id))
                        } label: {
                            clockedInTile(emp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyClockedIn: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Studio is empty.")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                Text("Nobody is currently clocked in.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func clockedInTile(_ employee: Employee) -> some View {
        let elapsed = openShift(for: employee).map {
            now.timeIntervalSince($0.clockInTime)
        } ?? 0

        return HStack(spacing: 12) {
            EmployeeAvatar(employee: employee, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(employee.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !employee.role.isEmpty {
                    Text(employee.role)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
                Text("On-clock \(DurationFormat.short(elapsed))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.success)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
        )
    }

    private var missedPunchesCard: some View {
        DashboardCard(
            "Missed Punches",
            trailing: AnyView(
                Button("See all") { switchTo(.audit) }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.gold)
            )
        ) {
            VStack(spacing: 10) {
                ForEach(missedPunches.prefix(3)) { log in
                    missedRow(log)
                }
                if missedPunches.count > 3 {
                    Text("+ \(missedPunches.count - 3) more")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func missedRow(_ log: PunchLog) -> some View {
        let elapsed = now.timeIntervalSince(log.clockInTime)

        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.warning)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.warning.opacity(0.18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(log.employee?.displayName ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("Open \(DurationFormat.short(elapsed))")
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.gold))
            }
        }
    }

    // MARK: - Helpers

    private func openShift(for employee: Employee) -> PunchLog? {
        employee.punchLogs
            .filter(\.isOpen)
            .max(by: { $0.clockInTime < $1.clockInTime })
    }

    private func forceOut(_ log: PunchLog) {
        log.clockOutTime = now
        log.wasForcedOut = true
        log.employee?.isCurrentlyClockedIn = false
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("Forced out \(log.employee?.displayName ?? "shift").", style: .success)
    }
}
