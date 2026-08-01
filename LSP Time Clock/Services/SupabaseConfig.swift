import Foundation

/// Static endpoint configuration plus the device-local credential and
/// session store for the Supabase backend the kiosk syncs against.
///
/// Everything mutable lives in `UserDefaults` rather than the Keychain,
/// deliberately. This build is side-loaded onto exactly one studio-owned
/// iPad that boots straight into kiosk mode and is expected to keep
/// punching people in unattended for weeks; the Keychain would add
/// entitlement and "device locked, item unavailable" failure modes to a
/// credential that only unlocks a machine account whose RLS grants reach
/// nothing but the five `timeclock_*` tables. If this app ever ships to
/// more than one device, move `devicePassword` to the Keychain first.
nonisolated enum SupabaseConfig {

    // MARK: - Fixed project settings

    static let projectURL = URL(string: "https://jcseaxtvsozylsbmykka.supabase.co")!

    /// Publishable (anon-role) key. Safe to embed: it grants nothing on its
    /// own — every table is RLS-gated behind the signed-in machine account.
    static let publishableKey = "sb_publishable_ByKQH4QqhYhrT7K-gqEhsw_zqdEvkB_"

    static let defaultDeviceEmail = "timeclock-kiosk@latinasweatproject.com"

    /// Intentionally empty — the password is typed once on the device from
    /// the admin Cloud Sync screen and never committed to the repo.
    static let defaultDevicePassword = ""

    /// Primary key of this kiosk's row in `timeclock_kiosk_status`.
    static let kioskID = "studio-ipad"

    /// How far back the incremental pull reaches beyond the stored
    /// watermark. Covers clock skew between the iPad and Postgres plus the
    /// window between a row being stamped and the transaction committing,
    /// either of which could otherwise let an update slip through unseen.
    static let watermarkSlack: TimeInterval = 60

    // MARK: - Storage keys

    private enum Key {
        static let deviceEmail = "supabase.deviceEmail"
        static let devicePassword = "supabase.devicePassword"
        static let accessToken = "supabase.accessToken"
        static let refreshToken = "supabase.refreshToken"
        static let expiresAt = "supabase.tokenExpiresAt"
        static let watermark = "supabase.pullWatermark"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Credentials

    static var deviceEmail: String {
        get { defaults.string(forKey: Key.deviceEmail) ?? defaultDeviceEmail }
        set { defaults.set(newValue, forKey: Key.deviceEmail) }
    }

    static var devicePassword: String {
        get { defaults.string(forKey: Key.devicePassword) ?? defaultDevicePassword }
        set { defaults.set(newValue, forKey: Key.devicePassword) }
    }

    /// Sync is opt-in: with no password stored the engine bails out
    /// silently on every trigger so a studio that hasn't been set up yet
    /// behaves exactly like the old offline-only build.
    static var isConfigured: Bool {
        !deviceEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        !devicePassword.isEmpty
    }

    // MARK: - Session

    static var accessToken: String? {
        get { defaults.string(forKey: Key.accessToken) }
        set { defaults.set(newValue, forKey: Key.accessToken) }
    }

    static var refreshToken: String? {
        get { defaults.string(forKey: Key.refreshToken) }
        set { defaults.set(newValue, forKey: Key.refreshToken) }
    }

    static var tokenExpiresAt: Date? {
        get {
            let raw = defaults.double(forKey: Key.expiresAt)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.expiresAt) }
    }

    static func clearSession() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
    }

    // MARK: - Incremental pull watermark

    /// Highest server `updated_at` this device has already merged. Starts
    /// at the epoch so the very first sync pulls the entire dataset.
    static var pullWatermark: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: Key.watermark)) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: Key.watermark) }
    }

    // MARK: - Build identity

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
