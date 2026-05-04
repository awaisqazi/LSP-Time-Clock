import SwiftUI
import SwiftData

/// iPadOS-first management hub. Uses `NavigationSplitView` so the layout
/// shows a persistent sidebar on iPad and gracefully collapses to a
/// push-stack on iPhone. The sidebar is the source of truth for which
/// section is visible; sub-views live in dedicated files under `Admin/`.
struct AdminDashboardView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Employee.firstName), SortDescriptor(\Employee.lastName)])
    private var employees: [Employee]

    // iOS requires `List(selection:)` for single-selection to bind to an
    // Optional value. We treat `nil` as "fall back to Overview" downstream.
    @State private var section: AdminSection? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var pendingCount: Int {
        employees.filter { $0.isPendingOnboarding }.count
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.light)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        // Selection binding + NavigationLink(value:) is the documented
        // pattern Apple recommends for NavigationSplitView sidebars (WWDC22
        // "The SwiftUI cookbook for navigation"). Plain Label.tag(_) rows
        // *can* fail to register taps depending on listStyle — using
        // NavigationLink with a matching value is the bulletproof form.
        List(selection: $section) {
            if pendingCount > 0 {
                Section {
                    Button {
                        coordinator.go(to: .bulkOnboarding)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.system(size: 18, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(pendingCount) need setup")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                Text("Tap to assign cards")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.text.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.gold.opacity(0.18))
                }
            }

            Section("Studio") {
                ForEach(AdminSection.allCases) { sec in
                    NavigationLink(value: sec) {
                        Label(sec.title, systemImage: sec.icon)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    coordinator.goHome()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section ?? .overview {
        case .overview:   AdminOverviewView(switchTo: { section = $0 })
        case .roster:     AdminRosterView()
        case .timesheets: AdminTimesheetsView()
        case .audit:      AdminAuditView()
        }
    }
}

enum AdminSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case roster
    case timesheets
    case audit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   "Overview"
        case .roster:     "Roster"
        case .timesheets: "Timesheets"
        case .audit:      "Audit"
        }
    }

    var icon: String {
        switch self {
        case .overview:   "square.grid.2x2.fill"
        case .roster:     "person.2.fill"
        case .timesheets: "calendar"
        case .audit:      "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Shared building blocks used across admin sections

struct DashboardCard<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    var content: Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Theme.tan.opacity(0.12), radius: 14, y: 5)
        )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = Theme.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint.opacity(0.15)))
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Theme.tan.opacity(0.10), radius: 10, y: 4)
        )
    }
}

struct EmployeeAvatar: View {
    let employee: Employee
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let img = PhotoStorage.load(fileName: employee.photoFileName) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Theme.tan.opacity(0.18))
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let f = employee.firstName.first.map(String.init) ?? ""
        let l = employee.lastName.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        return combined.isEmpty ? "?" : combined
    }
}

/// Pretty-print a `TimeInterval` as `Hh Mm` for the dashboard.
enum DurationFormat {
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}
