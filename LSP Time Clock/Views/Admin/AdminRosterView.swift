import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Searchable, filterable employee roster. Top of the view holds quick
/// actions (Bulk Import, Scan-to-Register, Export Roster) that admins use
/// most frequently; the list below is the primary navigation surface.
struct AdminRosterView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query(sort: [SortDescriptor(\Employee.firstName), SortDescriptor(\Employee.lastName)])
    private var employees: [Employee]

    enum StatusFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case inactive = "Inactive"
        case all = "All"
        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var filter: StatusFilter = .active
    @State private var showImporter = false
    @State private var rosterURL: URL?
    @State private var templateURL: URL?
    @FocusState private var searchFocused: Bool

    private var isCompact: Bool { hSizeClass == .compact }

    private var filtered: [Employee] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return employees
            .filter { emp in
                switch filter {
                case .active:   return emp.isActive
                case .inactive: return !emp.isActive
                case .all:      return true
                }
            }
            .filter { emp in
                guard !q.isEmpty else { return true }
                return emp.firstName.lowercased().contains(q) ||
                       emp.lastName.lowercased().contains(q) ||
                       emp.email.lowercased().contains(q) ||
                       emp.role.lowercased().contains(q) ||
                       emp.rfidTag.lowercased().contains(q)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                quickActions
                searchAndFilter
                rosterList
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Roster")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = rosterURL {
                    ShareLink(item: url, preview: SharePreview(
                        "Roster.csv",
                        icon: Image(systemName: "doc.text")
                    )) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: rosterCacheKey) {
            rosterURL = makeRosterURL()
        }
        .task {
            templateURL = makeTemplateURL()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            coordinator.setPresentingSystemModal(false)
            handleImport(result)
        }
    }

    // MARK: - Sections

    private var quickActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
            spacing: 12
        ) {
            Button {
                coordinator.setPresentingSystemModal(true)
                showImporter = true
            } label: {
                actionCardLabel(
                    title: "Bulk Import CSV",
                    subtitle: "Pre-load names, then assign cards.",
                    icon: "tray.and.arrow.down.fill",
                    tint: Theme.gold
                )
            }
            .buttonStyle(.plain)

            Button {
                coordinator.go(to: .scanning(.punch))
            } label: {
                actionCardLabel(
                    title: "Scan to Register",
                    subtitle: "Tap a new card to start signup.",
                    icon: "wave.3.right.circle.fill",
                    tint: Theme.success
                )
            }
            .buttonStyle(.plain)

            if let url = templateURL {
                ShareLink(item: url, preview: SharePreview(
                    "Instructor Template",
                    icon: Image(systemName: "doc.text")
                )) {
                    actionCardLabel(
                        title: "Download Template",
                        subtitle: "Blank CSV with the right headers.",
                        icon: "doc.text",
                        tint: Theme.tan
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchAndFilter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textFaint)
                TextField("Name, email, role, or card", text: $search)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onSubmit { searchFocused = false }
                    .foregroundStyle(Theme.text)
                    .tint(Theme.gold)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(searchFocused ? Theme.gold : Theme.surfaceStroke, lineWidth: 1.5)
                    )
            )

            Picker("Status", selection: $filter) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var rosterList: some View {
        DashboardCard("\(filtered.count) instructor\(filtered.count == 1 ? "" : "s")") {
            if filtered.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { emp in
                        Button {
                            coordinator.go(to: .adminEmployeeDetail(employeeID: emp.id))
                        } label: {
                            employeeRow(emp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(employees.isEmpty ? "No instructors yet." : "No matches.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func employeeRow(_ employee: Employee) -> some View {
        HStack(spacing: 14) {
            EmployeeAvatar(employee: employee, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(employee.displayName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    if !employee.role.isEmpty {
                        Text(employee.role)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.tan.opacity(0.18)))
                    }
                    Text(employee.email)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)

            statusBadge(employee)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statusBadge(_ employee: Employee) -> some View {
        if !employee.isActive {
            badge("INACTIVE", tint: Theme.textFaint)
        } else if employee.isPendingOnboarding {
            badge("SETUP", tint: Theme.gold)
        } else if employee.isCurrentlyClockedIn {
            badge("IN", tint: Theme.success)
        } else {
            badge("OUT", tint: Theme.tan)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    private func actionCardLabel(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Theme.tan.opacity(0.12), radius: 10, y: 4)
        )
    }

    // MARK: - Roster CSV cache key

    /// Drives `.task(id:)` regeneration. We hash the bits the export
    /// actually depends on so renames / reactivations / card changes all
    /// invalidate the cached file.
    private var rosterCacheKey: Int {
        var hasher = Hasher()
        for emp in employees {
            hasher.combine(emp.id)
            hasher.combine(emp.firstName)
            hasher.combine(emp.lastName)
            hasher.combine(emp.email)
            hasher.combine(emp.rfidTag)
            hasher.combine(emp.pin)
            hasher.combine(emp.role)
            hasher.combine(emp.isActive)
        }
        return hasher.finalize()
    }

    private func makeRosterURL() -> URL? {
        let csv = CSVExporter.rosterCSV(employees)
        let stamp = timestamp()
        return try? CSVExporter.writeToTempFile(csv, fileName: "LSP-Roster-\(stamp).csv")
    }

    private func makeTemplateURL() -> URL? {
        let csv = CSVExporter.bulkImportTemplate()
        return try? CSVExporter.writeToTempFile(csv, fileName: "LSP-Instructor-Template.csv")
    }

    // MARK: - Bulk import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            Feedback.error()
            coordinator.showToast("Import failed: \(error.localizedDescription)", style: .error)
        case .success(let urls):
            guard let url = urls.first else { return }
            importCSV(at: url)
        }
    }

    private func importCSV(at url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try readCSVText(at: url)
            let rows = try CSVExporter.parseImport(text)
            let result = ingest(rows: rows)

            if result.created == 0 && result.skipped == 0 {
                coordinator.showToast("CSV had no valid rows.", style: .warning)
                Feedback.warning()
                return
            }

            var parts: [String] = []
            if result.created > 0 { parts.append("\(result.created) added") }
            if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
            coordinator.showToast(parts.joined(separator: " · "), style: .success)
            Feedback.success()

            if result.created > 0 {
                coordinator.go(to: .bulkOnboarding)
            }
        } catch {
            Feedback.error()
            coordinator.showToast(error.localizedDescription, style: .error)
        }
    }

    private struct IngestResult { var created = 0; var skipped = 0 }

    private func ingest(rows: [CSVExporter.ImportRow]) -> IngestResult {
        var result = IngestResult()
        var seenEmails: Set<String> = []

        for row in rows {
            let email = row.email
            guard !email.isEmpty, !seenEmails.contains(email) else {
                result.skipped += 1
                continue
            }
            seenEmails.insert(email)

            if let _ = findEmployee(byEmail: email) {
                result.skipped += 1
                continue
            }

            let employee = Employee(
                rfidTag: Employee.makePendingTag(),
                firstName: row.firstName,
                lastName: row.lastName,
                email: email,
                photoFileName: ""
            )
            modelContext.insert(employee)
            result.created += 1
        }

        if result.created > 0 {
            do { try modelContext.save() }
            catch { coordinator.showToast("Save failed: \(error.localizedDescription)", style: .error) }
        }
        return result
    }

    private func readCSVText(at url: URL) throws -> String {
        var used = String.Encoding.utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &used) {
            return detected
        }
        for encoding: String.Encoding in [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1] {
            if let s = try? String(contentsOf: url, encoding: encoding) {
                return s
            }
        }
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    private func findEmployee(byEmail email: String) -> Employee? {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.email == email }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
