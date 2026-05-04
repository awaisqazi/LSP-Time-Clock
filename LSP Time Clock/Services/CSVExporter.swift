import Foundation

enum CSVExporter {
    static func csv(from logs: [PunchLog]) -> String {
        let header = "Employee ID,First Name,Last Name,Email,RFID Tag,Clock In,Clock Out,Total Hours,Forced Out\n"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let sorted = logs.sorted { $0.clockInTime < $1.clockInTime }

        var body = ""
        for log in sorted {
            let id = log.employee?.id.uuidString ?? ""
            let first = log.employee?.firstName ?? ""
            let last = log.employee?.lastName ?? ""
            let email = log.employee?.email ?? ""
            let rfid = log.employee?.rfidTag ?? ""
            let inStr = iso.string(from: log.clockInTime)
            let outStr = log.clockOutTime.map { iso.string(from: $0) } ?? ""
            let hours = log.totalHours.map { String(format: "%.2f", $0) } ?? ""
            let forced = log.wasForcedOut ? "true" : "false"

            body += [
                id,
                escape(first),
                escape(last),
                escape(email),
                escape(rfid),
                inStr,
                outStr,
                hours,
                forced
            ].joined(separator: ",") + "\n"
        }
        return header + body
    }

    static func writeToTempFile(_ csv: String, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Roster Export

    /// Roster CSV with the columns admins use for HRIS imports / payroll
    /// onboarding: name, RFID card #, PIN, role, status. Pending-onboarding
    /// employees show a blank RFID column rather than the internal sentinel.
    static func rosterCSV(_ employees: [Employee]) -> String {
        let header = "Full Name,Email,RFID Card,PIN,Role,Status\n"
        let sorted = employees.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
        var body = ""
        for emp in sorted {
            let card = emp.hasAssignedCard ? emp.rfidTag : ""
            let status = emp.isActive ? "Active" : "Inactive"
            body += [
                escape(emp.fullName),
                escape(emp.email),
                escape(card),
                escape(emp.pin),
                escape(emp.role),
                status
            ].joined(separator: ",") + "\n"
        }
        return header + body
    }

    // MARK: - Timesheet Export (Date Range)

    /// Timesheet CSV scoped to a date range. Each row is one shift with the
    /// total hours pre-computed in **decimal hours** so a payroll import
    /// can multiply directly by an hourly rate (e.g. `1.50` not `1:30`).
    /// Open shifts (no clock-out) are included with a blank Clock Out and
    /// blank Total Hours so they're visible to whoever is doing payroll.
    static func timesheetCSV(_ logs: [PunchLog], from start: Date, to end: Date) -> String {
        let header = "Date,Employee,Email,Role,Clock In,Clock Out,Total Hours,Forced Out\n"
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        let dateTime = DateFormatter()
        dateTime.dateFormat = "yyyy-MM-dd HH:mm"

        let inRange = logs
            .filter { $0.clockInTime >= start && $0.clockInTime <= end }
            .sorted { $0.clockInTime < $1.clockInTime }

        var body = ""
        for log in inRange {
            let name = log.employee?.fullName ?? "—"
            let email = log.employee?.email ?? ""
            let role = log.employee?.role ?? ""
            let hours = log.totalHours.map { String(format: "%.2f", $0) } ?? ""
            let outStr = log.clockOutTime.map(dateTime.string(from:)) ?? ""
            let forced = log.wasForcedOut ? "true" : "false"
            body += [
                dateOnly.string(from: log.clockInTime),
                escape(name),
                escape(email),
                escape(role),
                dateTime.string(from: log.clockInTime),
                outStr,
                hours,
                forced
            ].joined(separator: ",") + "\n"
        }
        return header + body
    }

    // MARK: - Bulk Import Template

    /// Blank template the admin can fill in and re-upload to bulk-create
    /// pending employees. A single example row is included so it's obvious
    /// what shape the file should be in.
    static func bulkImportTemplate() -> String {
        """
        First Name,Last Name,Email
        Jane,Doe,jane@example.com
        """
    }

    // MARK: - Bulk Import Parser

    struct ImportRow: Equatable {
        var firstName: String
        var lastName: String
        var email: String
    }

    enum ImportError: LocalizedError {
        case empty
        case missingHeader(found: [String])

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The CSV file is empty."
            case .missingHeader(let found):
                let foundList = found.isEmpty ? "no headers" : found.joined(separator: ", ")
                return "Missing required headers. Need an Email column plus either First Name + Last Name or a single Name. Found: \(foundList)."
            }
        }
    }

    /// Parses an uploaded CSV. Recognized headers (case-insensitive):
    /// `First Name` + `Last Name` + `Email`, or a combined `Name` + `Email`.
    /// Strips a UTF-8 BOM if Numbers/Excel injected one. Rows with a blank
    /// email are skipped.
    static func parseImport(_ text: String) throws -> [ImportRow] {
        var working = text
        // Excel and Numbers happily prepend a UTF-8 BOM that wrecks an
        // otherwise-valid header match. Strip it before parsing anything.
        if working.first == "\u{FEFF}" {
            working.removeFirst()
        }

        let lines = splitRows(working)
        guard !lines.isEmpty else { throw ImportError.empty }

        let header = parseRow(lines[0]).map(normalizeHeader)
        guard let emailIdx = header.firstIndex(of: "email") else {
            throw ImportError.missingHeader(found: header)
        }

        let firstIdx = header.firstIndex(of: "first name")
            ?? header.firstIndex(of: "firstname")
            ?? header.firstIndex(of: "first")
        let lastIdx = header.firstIndex(of: "last name")
            ?? header.firstIndex(of: "lastname")
            ?? header.firstIndex(of: "last")
        let combinedNameIdx = header.firstIndex(of: "name")
            ?? header.firstIndex(of: "full name")
            ?? header.firstIndex(of: "fullname")

        // Need at least one source for the name (combined or split).
        guard firstIdx != nil || lastIdx != nil || combinedNameIdx != nil else {
            throw ImportError.missingHeader(found: header)
        }

        var rows: [ImportRow] = []
        for raw in lines.dropFirst() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cells = parseRow(raw)

            let email = cell(cells, at: emailIdx)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard !email.isEmpty else { continue }

            let firstFromSplit = firstIdx.map { cell(cells, at: $0).trimmingCharacters(in: .whitespaces) } ?? ""
            let lastFromSplit = lastIdx.map { cell(cells, at: $0).trimmingCharacters(in: .whitespaces) } ?? ""

            let first: String
            let last: String
            if !firstFromSplit.isEmpty || !lastFromSplit.isEmpty {
                first = firstFromSplit
                last = lastFromSplit
            } else if let combinedIdx = combinedNameIdx {
                let combined = cell(cells, at: combinedIdx).trimmingCharacters(in: .whitespaces)
                (first, last) = splitName(combined)
            } else {
                first = ""
                last = ""
            }

            rows.append(ImportRow(firstName: first, lastName: last, email: email))
        }
        return rows
    }

    private nonisolated static func normalizeHeader(_ value: String) -> String {
        let stripped = value
            .replacingOccurrences(of: "\u{FEFF}", with: "")   // BOM
            .replacingOccurrences(of: "\u{00A0}", with: " ")  // non-breaking space
            .replacingOccurrences(of: "_", with: " ")          // first_name → first name
        // Collapse any run of whitespace/newlines into a single regular space
        // so "First   Name", "First\u{00A0}Name", "First\tName", and trailing
        // CR/LF artifacts all normalize identically.
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.lowercased()
    }

    private nonisolated static func cell(_ cells: [String], at index: Int) -> String {
        cells.indices.contains(index) ? cells[index] : ""
    }

    private static func splitName(_ value: String) -> (String, String) {
        let parts = value.split(
            separator: " ",
            maxSplits: 1,
            omittingEmptySubsequences: true
        )
        let first = parts.first.map(String.init) ?? ""
        let last = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return (first, last)
    }

    /// Split CSV text into row strings while honoring quoted newlines.
    ///
    /// Critical detail: Swift iterates strings by extended grapheme cluster,
    /// and `"\r\n"` is *one* Character — equal to neither `"\r"` nor `"\n"`.
    /// That means equality checks against either character silently drop the
    /// CRLF that Numbers/Excel actually emit, collapsing the whole file into
    /// one row. `Character.isNewline` matches the combined CRLF grapheme as
    /// well as LF, CR, VT, FF, NEL, LS, and PS, so this is the only reliable
    /// way to find row boundaries.
    private nonisolated static func splitRows(_ text: String) -> [String] {
        var rows: [String] = []
        var current = ""
        var inQuotes = false

        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
                continue
            }
            if !inQuotes && ch.isNewline {
                if !current.isEmpty { rows.append(current) }
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// Parse a single CSV row into cells, handling quoted commas and
    /// escaped double quotes (`""` → `"`).
    private static func parseRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        var i = row.startIndex

        while i < row.endIndex {
            let ch = row[i]
            if ch == "\"" {
                if inQuotes {
                    let next = row.index(after: i)
                    if next < row.endIndex, row[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = row.index(after: i)
        }
        cells.append(current)
        return cells
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
