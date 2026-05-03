import SwiftUI
import SwiftData

struct AdminDashboardView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query(sort: [
        SortDescriptor(\Employee.firstName),
        SortDescriptor(\Employee.lastName)
    ])
    private var employees: [Employee]

    @Query private var allLogs: [PunchLog]

    @State private var search = ""
    @State private var exportFile: ExportFile?
    @FocusState private var searchFocused: Bool

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var isCompact: Bool { hSizeClass == .compact }

    private var filtered: [Employee] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return employees }
        return employees.filter { emp in
            emp.firstName.lowercased().contains(q) ||
            emp.lastName.lowercased().contains(q) ||
            emp.email.lowercased().contains(q) ||
            emp.rfidTag.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                searchBar

                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: isCompact ? 10 : 12) {
                            ForEach(filtered) { emp in
                                Button {
                                    Feedback.tap()
                                    coordinator.go(to: .adminEmployeeDetail(employeeID: emp.id))
                                } label: {
                                    employeeRow(emp)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, isCompact ? 16 : 24)
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .onTapGesture { coordinator.userActivity() }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var header: some View {
        if isCompact {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        coordinator.goHome()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }

                    Text("Admin Dashboard")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Button(action: exportCSV) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.brandGradient))
                    }
                }

                Text("\(employees.count) instructors · \(allLogs.count) punches")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Theme.surface
                    .shadow(color: Theme.tan.opacity(0.15), radius: 8, y: 2)
            )
        } else {
            HStack(spacing: 12) {
                Button {
                    coordinator.goHome()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }

                Text("Admin Dashboard")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)

                Spacer()

                Text("\(employees.count) instructors · \(allLogs.count) punches")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)

                Button(action: exportCSV) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.brandGradient))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                Theme.surface
                    .shadow(color: Theme.tan.opacity(0.15), radius: 8, y: 2)
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textFaint)
            TextField(isCompact ? "Search" : "Search by name, email, or card tag", text: $search)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .onSubmit { searchFocused = false }
                .foregroundStyle(Theme.text)
                .tint(Theme.gold)
            if !search.isEmpty {
                Button {
                    search = ""
                    coordinator.userActivity()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: isCompact ? 15 : 17, weight: .medium, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            searchFocused ? Theme.gold : Theme.surfaceStroke,
                            lineWidth: 1.5
                        )
                )
        )
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.top, isCompact ? 12 : 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(employees.isEmpty ? "No instructors yet" : "No results")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
    }

    private func employeeRow(_ employee: Employee) -> some View {
        let photoSize: CGFloat = isCompact ? 48 : 56

        return HStack(spacing: isCompact ? 12 : 16) {
            photo(for: employee, size: photoSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(employee.fullName)
                    .font(.system(size: isCompact ? 16 : 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(employee.email)
                    .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 10))
                    Text(employee.rfidTag)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.textFaint)
            }

            Spacer(minLength: 0)

            statusBadge(for: employee)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(isCompact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Theme.tan.opacity(0.1), radius: 10, y: 3)
        )
    }

    private func photo(for employee: Employee, size: CGFloat) -> some View {
        Group {
            if let img = PhotoStorage.load(fileName: employee.photoFileName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.tan.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func statusBadge(for employee: Employee) -> some View {
        let isIn = employee.isCurrentlyClockedIn
        return Text(isIn ? "IN" : "OUT")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isIn ? Theme.success.opacity(0.15) : Theme.tan.opacity(0.2))
            )
            .foregroundStyle(isIn ? Theme.success : Theme.textMuted)
    }

    private func exportCSV() {
        coordinator.userActivity()
        let csv = CSVExporter.csv(from: allLogs)
        let fileName = "LSP-PunchLogs-\(Self.timestamp()).csv"
        do {
            let url = try CSVExporter.writeToTempFile(csv, fileName: fileName)
            exportFile = ExportFile(url: url)
            Feedback.success()
        } catch {
            Feedback.error()
            coordinator.showToast("Export failed: \(error.localizedDescription)", style: .error)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
