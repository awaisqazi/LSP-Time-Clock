import Foundation

// MARK: - Errors

nonisolated enum SupabaseError: Error {
    /// No device password has been entered yet — not a failure, just "off".
    case notConfigured
    case invalidURL
    case transport(String)
    case unauthorized
    /// Signed in fine, but the account isn't allowed to touch the
    /// `timeclock_*` tables. Kept separate from `.unauthorized` so the admin
    /// screen stops telling people to re-check a password that is correct.
    case forbidden
    case http(status: Int, body: String)
    case decoding(String)

    var message: String {
        switch self {
        case .notConfigured:
            return "Cloud sync isn't set up on this iPad yet."
        case .invalidURL:
            return "Could not build a valid Supabase URL."
        case .transport(let detail):
            return "Network error: \(detail)"
        case .unauthorized:
            return "Sign-in was rejected. Check the kiosk email and password."
        case .forbidden:
            return "Signed in, but this account doesn't have the Time Clock module granted. Ask an admin to give it access to the timeclock tables."
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Server error \(status)." : "Server error \(status): \(trimmed)"
        case .decoding(let detail):
            return "Unexpected server response: \(detail)"
        }
    }
}

extension SupabaseError: LocalizedError {
    nonisolated var errorDescription: String? { message }
}

// MARK: - Timestamp parsing

/// Tolerant ISO-8601 handling for values coming out of PostgREST.
///
/// Postgres hands back `timestamptz` with a variable number of fractional
/// digits (`…:56+00:00`, `…:56.12+00:00`, `…:56.123456+00:00`) and plain
/// `date` columns with no time at all. `ISO8601DateFormatter` is strict
/// about exactly-three fractional digits, so anything unusual is normalized
/// before the second attempt rather than being dropped on the floor.
nonisolated enum SupabaseDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// `date`-typed columns (`starts_on` / `ends_on`) arrive as bare
    /// calendar days. They describe studio days, so they're anchored to the
    /// device's time zone rather than UTC.
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        if let date = fractional.date(from: raw) { return date }
        if let date = plain.date(from: raw) { return date }
        if let normalized = normalizingFraction(raw) {
            if let date = fractional.date(from: normalized) { return date }
            if let date = plain.date(from: normalized) { return date }
        }
        if raw.count == 10, let date = dayOnly.date(from: raw) { return date }
        return nil
    }

    /// Outbound format. Always emits fractional seconds + `Z` so the value
    /// round-trips through `timestamptz` without ambiguity.
    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    /// Rewrites the fractional-seconds run to exactly three digits (or
    /// removes an empty `.`), leaving the date and time-zone parts alone.
    /// Returns nil when there is nothing to fix.
    private static func normalizingFraction(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        var end = raw.index(after: dot)
        while end < raw.endIndex, raw[end].isNumber {
            end = raw.index(after: end)
        }
        let digits = raw[raw.index(after: dot)..<end]
        guard digits.count != 3 else { return nil }

        let head = String(raw[raw.startIndex..<dot])
        let tail = String(raw[end...])
        guard !digits.isEmpty else { return head + tail }

        var fraction = String(digits.prefix(3))
        while fraction.count < 3 { fraction += "0" }
        return head + "." + fraction + tail
    }
}

// MARK: - Lenient decoding

/// Wrapper that turns "one bad row" into "one skipped row" instead of a
/// failed sync. A schema change made in the portal must never be able to
/// wedge the iPad.
nonisolated struct Lenient<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

// MARK: - Client

/// Minimal hand-rolled Supabase client: GoTrue password/refresh grants plus
/// the four PostgREST verbs the sync engine needs.
///
/// Declared as an `actor` so JSON encoding/decoding of a full history pull
/// happens off the main thread — the rest of this target is MainActor by
/// default, and a kiosk that stutters mid-punch is worse than a kiosk that
/// syncs a second later.
actor SupabaseAPI {

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        // Never queue a request waiting for the studio Wi-Fi to come back;
        // failing fast keeps `isSyncing` honest and the next trigger will
        // try again in a couple of minutes anyway.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SupabaseDate.string(from: date))
        }
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SupabaseDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized timestamp \"\(raw)\""
                )
            }
            return date
        }
        return decoder
    }()

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    init() {
        accessToken = SupabaseConfig.accessToken
        refreshToken = SupabaseConfig.refreshToken
        expiresAt = SupabaseConfig.tokenExpiresAt
    }

    // MARK: - Auth

    var hasSession: Bool { !(accessToken ?? "").isEmpty }

    /// Explicit sign-in used by the admin Cloud Sync screen so a bad
    /// password surfaces immediately instead of on the next background run.
    ///
    /// Verify-then-adopt: the candidate credentials are proven against
    /// GoTrue *before* anything replaces the session already in use, so a
    /// typo on the admin screen can't sign a working kiosk out.
    func signIn(email: String, password: String) async throws {
        let token = try await fetchToken(
            grant: "password",
            body: ["email": email, "password": password]
        )
        adopt(token)
    }

    /// Cheapest path to a usable bearer token: reuse, refresh, re-login.
    func ensureSignedIn() async throws {
        if let token = accessToken, !token.isEmpty,
           let expiresAt, expiresAt > Date().addingTimeInterval(60) {
            return
        }

        if let refreshToken, !refreshToken.isEmpty {
            do {
                try await requestToken(grant: "refresh_token", body: ["refresh_token": refreshToken])
                return
            } catch {
                // A revoked or rotated-out refresh token isn't fatal — fall
                // through to a fresh password grant below.
                clearSession()
            }
        }

        let email = SupabaseConfig.deviceEmail
        let password = SupabaseConfig.devicePassword
        guard !email.isEmpty, !password.isEmpty else { throw SupabaseError.notConfigured }
        try await requestToken(grant: "password", body: ["email": email, "password": password])
    }

    func clearSession() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        SupabaseConfig.clearSession()
    }

    private nonisolated struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    /// Runs a GoTrue grant and hands back the token without touching any
    /// stored state, so callers can decide whether the result is worth
    /// adopting.
    private func fetchToken(grant: String, body: [String: String]) async throws -> TokenResponse {
        var components = URLComponents(
            url: SupabaseConfig.projectURL.appending(path: "auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        guard let url = components?.url else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 403 {
                throw SupabaseError.unauthorized
            }
            throw SupabaseError.http(status: http.statusCode, body: snippet(data))
        }

        do {
            return try decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    /// Installs a freshly granted token as the live session.
    private func adopt(_ token: TokenResponse) {
        accessToken = token.accessToken
        if let refreshed = token.refreshToken, !refreshed.isEmpty {
            refreshToken = refreshed
        }
        expiresAt = Date().addingTimeInterval(token.expiresIn ?? 3600)

        SupabaseConfig.accessToken = accessToken
        SupabaseConfig.refreshToken = refreshToken
        SupabaseConfig.tokenExpiresAt = expiresAt
    }

    private func requestToken(grant: String, body: [String: String]) async throws {
        do {
            adopt(try await fetchToken(grant: grant, body: body))
        } catch {
            // Only a definitive rejection (400/401/403 → `.unauthorized`)
            // invalidates what we have stored. Throwing away a perfectly
            // good refresh token because the studio Wi-Fi blipped or GoTrue
            // answered 429 would turn a transient hiccup into a kiosk that
            // needs the password typed in again.
            if case SupabaseError.unauthorized = error { clearSession() }
            throw error
        }
    }

    // MARK: - PostgREST

    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        table: String,
        query: [URLQueryItem]
    ) async throws -> [T] {
        let data = try await restData(method: "GET", table: table, query: query, body: nil, prefer: nil)
        do {
            return try decoder.decode([Lenient<T>].self, from: data).compactMap(\.value)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    /// `POST` + `resolution=merge-duplicates` is PostgREST's upsert. Rows
    /// carry their primary key, so a re-push after a flaky response is
    /// idempotent rather than duplicating history.
    func upsert<T: Encodable & Sendable>(
        table: String,
        rows: [T],
        onConflict: String? = nil
    ) async throws {
        guard !rows.isEmpty else { return }
        let body = try encode(rows)
        var query: [URLQueryItem] = []
        if let onConflict {
            query.append(URLQueryItem(name: "on_conflict", value: onConflict))
        }
        _ = try await restData(
            method: "POST",
            table: table,
            query: query,
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func patch<T: Encodable & Sendable>(
        table: String,
        filter: [URLQueryItem],
        payload: T
    ) async throws {
        let body = try encode(payload)
        _ = try await restData(
            method: "PATCH",
            table: table,
            query: filter,
            body: body,
            prefer: "return=minimal"
        )
    }

    // MARK: - Plumbing

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    private func restData(
        method: String,
        table: String,
        query: [URLQueryItem],
        body: Data?,
        prefer: String?
    ) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1

            var components = URLComponents(
                url: SupabaseConfig.projectURL.appending(path: "rest/v1/\(table)"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = query.isEmpty ? nil : query
            guard let url = components?.url else { throw SupabaseError.invalidURL }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            if let accessToken, !accessToken.isEmpty {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let prefer {
                request.setValue(prefer, forHTTPHeaderField: "Prefer")
            }
            request.httpBody = body

            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else {
                throw SupabaseError.transport("No HTTP response")
            }

            // One silent re-auth: access tokens expire on their own schedule
            // and a kiosk that has been asleep for a day will always land
            // here on its first request.
            if http.statusCode == 401, attempt == 1 {
                expiresAt = .distantPast
                try await ensureSignedIn()
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                // 401 means the token is stale or the credentials are wrong;
                // 403 means the token is fine and RLS said no. Conflating
                // them sends the admin off to re-type a working password.
                if http.statusCode == 401 { throw SupabaseError.unauthorized }
                if http.statusCode == 403 { throw SupabaseError.forbidden }
                throw SupabaseError.http(status: http.statusCode, body: snippet(data))
            }
            return data
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SupabaseError.transport(error.localizedDescription)
        }
    }

    /// Error bodies from PostgREST can be long; the toast/admin screen only
    /// needs enough to identify the constraint that blew up.
    private nonisolated func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(400), as: UTF8.self)
    }
}
