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

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
