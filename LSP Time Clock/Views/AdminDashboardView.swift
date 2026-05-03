import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var showImporter = false
    @State private var showImportMenu = false
    @FocusState private var searchFocused: Bool

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var isCompact: Bool { hSizeClass == .compact }

    private var pendingCount: Int {
        employees.filter { $0.isPendingOnboarding }.count
    }

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

                if pendingCount > 0 {
                    pendingBanner
                }

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
        .sheet(item: $exportFile, onDismiss: {
            coordinator.setPresentingSystemModal(false)
        }) { file in
            ShareSheet(items: [file.url])
                .onAppear { coordinator.setPresentingSystemModal(true) }
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

                    Menu {
                        importMenuContent
                    } label: {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(Theme.surface)
                                    .overlay(Circle().stroke(Theme.surfaceStroke, lineWidth: 1))
                            )
                    }

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

                Menu {
                    importMenuContent
                } label: {
                    Label("Bulk Import", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Theme.surface)
                                .overlay(Capsule().stroke(Theme.surfaceStroke, lineWidth: 1))
                        )
                }

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

    @ViewBuilder
    private var importMenuContent: some View {
        Button {
            shareTemplate()
        } label: {
            Label("Download CSV Template", systemImage: "doc.text")
        }
        Button {
            coordinator.setPresentingSystemModal(true)
            showImporter = true
        } label: {
            Label("Import CSV…", systemImage: "square.and.arrow.down")
        }
    }

    private var pendingBanner: some View {
        Button {
            coordinator.go(to: .bulkOnboarding)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pendingCount) instructor\(pendingCount == 1 ? "" : "s") need setup")
                        .font(.system(size: isCompact ? 14 : 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Tap to assign cards and photos")
                        .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.vertical, isCompact ? 12 : 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.brandGradient)
                    .shadow(color: Theme.gold.opacity(0.35), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.top, isCompact ? 12 : 14)
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
                Text(employee.fullName.trimmingCharacters(in: .whitespaces).isEmpty
                     ? employee.email
                     : employee.fullName)
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
                    Text(employee.hasAssignedCard ? employee.rfidTag : "No card yet")
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

    @ViewBuilder
    private func statusBadge(for employee: Employee) -> some View {
        if employee.isPendingOnboarding {
            Text("SETUP")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.gold.opacity(0.25)))
                .foregroundStyle(Theme.text)
        } else {
            let isIn = employee.isCurrentlyClockedIn
            Text(isIn ? "IN" : "OUT")
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
    }

    // MARK: - Actions

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

    private func shareTemplate() {
        coordinator.userActivity()
        let csv = CSVExporter.bulkImportTemplate()
        do {
            let url = try CSVExporter.writeToTempFile(csv, fileName: "LSP-Instructor-Template.csv")
            exportFile = ExportFile(url: url)
            Feedback.tap()
        } catch {
            Feedback.error()
            coordinator.showToast("Template failed: \(error.localizedDescription)", style: .error)
        }
    }

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
            if result.created > 0 {
                parts.append("\(result.created) added")
            }
            if result.skipped > 0 {
                parts.append("\(result.skipped) skipped")
            }
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

    private struct IngestResult {
        var created: Int = 0
        var skipped: Int = 0
    }

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

            if let existing = findEmployee(byEmail: email) {
                if existing.hasAssignedCard {
                    // Already complete (or at least has a card). Skip per spec.
                    result.skipped += 1
                } else {
                    // Already on the pending queue — leave intact, don't dupe.
                    result.skipped += 1
                }
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
            do {
                try modelContext.save()
            } catch {
                coordinator.showToast("Save failed: \(error.localizedDescription)", style: .error)
            }
        }
        return result
    }

    /// Reads CSV text robustly. Excel/Numbers exports can land in UTF-8,
    /// UTF-8 with BOM, UTF-16, or even CP-1252 — we let the system sniff the
    /// encoding first, then fall back through the most common ones.
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
        // Last resort: read raw bytes and force-decode as UTF-8 (lossy).
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

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
