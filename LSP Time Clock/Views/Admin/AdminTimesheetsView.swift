import SwiftUI
import SwiftData

/// Date-range timesheet exports + a live preview of the punches that
/// would be exported. Tapping a row opens the manual-edit sheet.
struct AdminTimesheetsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query(sort: [SortDescriptor(\PunchLog.clockInTime, order: .reverse)])
    private var allLogs: [PunchLog]

    @State private var startDate: Date = Self.defaultStart()
    @State private var endDate: Date = Self.defaultEnd()
    @State private var exportURL: URL?
    @State private var editing: PunchLog?

    private var isCompact: Bool { hSizeClass == .compact }

    /// Logs whose clock-in falls in the chosen range, newest first.
    private var rangeLogs: [PunchLog] {
        let range = startOfDay(startDate)...endOfDay(endDate)
        return allLogs.filter { range.contains($0.clockInTime) }
    }

    private var totalHours: Double {
        rangeLogs.compactMap(\.totalHours).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangeCard
                summaryRow
                logsCard
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Timesheets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = exportURL {
                    ShareLink(item: url, preview: SharePreview(
                        "Timesheet \(rangeLabel)",
                        icon: Image(systemName: "doc.text")
                    )) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: cacheKey) {
            exportURL = makeURL()
        }
        .sheet(item: $editing) { log in
            PunchLogEditView(log: log)
        }
    }

    // MARK: - Sections

    private var rangeCard: some View {
        DashboardCard("Date Range") {
            VStack(alignment: .leading, spacing: 14) {
                if isCompact {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .tint(Theme.gold)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                        .tint(Theme.gold)
                } else {
                    HStack(spacing: 24) {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .tint(Theme.gold)
                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                            .tint(Theme.gold)
                    }
                }

                HStack(spacing: 8) {
                    quickRangeButton("This Week") {
                        let cal = Calendar.current
                        if let interval = cal.dateInterval(of: .weekOfYear, for: .now) {
                            startDate = interval.start
                            endDate = interval.end.addingTimeInterval(-1)
                        }
                    }
                    quickRangeButton("Last Week") {
                        let cal = Calendar.current
                        if let interval = cal.dateInterval(of: .weekOfYear, for: .now) {
                            startDate = cal.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
                            endDate = cal.date(byAdding: .day, value: -7, to: interval.end.addingTimeInterval(-1)) ?? interval.end
                        }
                    }
                    quickRangeButton("This Month") {
                        let cal = Calendar.current
                        if let interval = cal.dateInterval(of: .month, for: .now) {
                            startDate = interval.start
                            endDate = interval.end.addingTimeInterval(-1)
                        }
                    }
                    quickRangeButton("Last 30 Days") {
                        endDate = .now
                        startDate = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
                    }
                }
            }
        }
    }

    private func quickRangeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.tan.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private var summaryRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
            spacing: 16
        ) {
            MetricTile(
                title: "Shifts",
                value: "\(rangeLogs.count)",
                icon: "wave.3.right",
                tint: Theme.gold
            )
            MetricTile(
                title: "Total Hours",
                value: String(format: "%.2f", totalHours),
                icon: "clock.fill",
                tint: Theme.success
            )
            MetricTile(
                title: "Open Shifts",
                value: "\(rangeLogs.filter(\.isOpen).count)",
                icon: "exclamationmark.triangle.fill",
                tint: Theme.warning
            )
        }
    }

    private var logsCard: some View {
        DashboardCard("Recent Punches in Range") {
            if rangeLogs.isEmpty {
                Text("No punches in this range.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(rangeLogs.prefix(50)) { log in
                        Button {
                            editing = log
                        } label: {
                            logRow(log)
                        }
                        .buttonStyle(.plain)
                    }
                    if rangeLogs.count > 50 {
                        Text("Showing 50 of \(rangeLogs.count). Export the CSV for the full list.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func logRow(_ log: PunchLog) -> some View {
        let dateFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "MMM d"; return f
        }()
        let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
        }()

        return HStack(spacing: 14) {
            VStack(alignment: .center, spacing: 0) {
                Text(dateFmt.string(from: log.clockInTime))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.employee?.displayName ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("IN \(timeFmt.string(from: log.clockInTime))")
                    Text("·")
                    if let out = log.clockOutTime {
                        Text("OUT \(timeFmt.string(from: out))")
                    } else {
                        Text("OPEN").foregroundStyle(Theme.warning)
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(log.totalHours.map { String(format: "%.2fh", $0) } ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                if log.wasForcedOut {
                    Text("FORCED")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.gold))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceSubtle)
        )
    }

    // MARK: - Helpers

    private var rangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: startDate)) to \(f.string(from: endDate))"
    }

    /// Cache key invalidates when range *or* underlying logs change. We
    /// hash log IDs and last-modified-ish properties so manual edits to a
    /// row invalidate the export.
    private var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(startDate.timeIntervalSince1970)
        hasher.combine(endDate.timeIntervalSince1970)
        for log in rangeLogs {
            hasher.combine(log.id)
            hasher.combine(log.clockInTime)
            hasher.combine(log.clockOutTime)
        }
        return hasher.finalize()
    }

    private func makeURL() -> URL? {
        let csv = CSVExporter.timesheetCSV(
            allLogs,
            from: startOfDay(startDate),
            to: endOfDay(endDate)
        )
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        let name = "LSP-Timesheets-\(f.string(from: startDate))-to-\(f.string(from: endDate)).csv"
        return try? CSVExporter.writeToTempFile(csv, fileName: name)
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func endOfDay(_ date: Date) -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
        return next.addingTimeInterval(-1)
    }

    private static func defaultStart() -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    private static func defaultEnd() -> Date { .now }
}
