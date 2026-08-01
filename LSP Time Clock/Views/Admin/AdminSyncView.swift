import SwiftUI
import SwiftData
import Combine

/// Cloud Sync control panel. Three jobs, in priority order: tell the admin
/// whether the iPad is talking to Supabase, let them fix it if it isn't,
/// and give them a big obvious button to force a run before they walk away
/// with the day's punches still on the device.
struct AdminSyncView: View {
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var email: String = SupabaseConfig.deviceEmail
    @State private var password: String = ""
    @State private var isSigningIn = false
    @State private var now: Date = .now

    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var isCompact: Bool { hSizeClass == .compact }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        !isSigningIn
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                syncButton
                pendingGrid
                credentialsCard
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
        .onAppear {
            email = SupabaseConfig.deviceEmail
            syncEngine.refreshPendingCounts()
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        DashboardCard("Connection", trailing: AnyView(statusPill)) {
            VStack(alignment: .leading, spacing: 12) {
                infoRow(
                    icon: "person.badge.key.fill",
                    title: "Kiosk account",
                    value: syncEngine.isConfigured ? syncEngine.accountEmail : "Not configured"
                )
                infoRow(
                    icon: "clock.arrow.circlepath",
                    title: "Last successful sync",
                    value: lastSyncDescription
                )
                infoRow(
                    icon: "arrow.down.circle",
                    title: "Last pull",
                    value: "\(syncEngine.lastPulledCount) row\(syncEngine.lastPulledCount == 1 ? "" : "s")"
                )
                infoRow(
                    icon: "arrow.up.circle",
                    title: "Last push",
                    value: "\(syncEngine.lastPushedCount) row\(syncEngine.lastPushedCount == 1 ? "" : "s")"
                )

                if let error = syncEngine.lastError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.danger)
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.danger.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.danger.opacity(0.28), lineWidth: 1)
                            )
                    )
                }

                Text("Punching never waits on the network. Anything that can't be uploaded stays queued on this iPad and goes up on the next successful sync.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusPill: some View {
        let (label, tint): (String, Color) = {
            if syncEngine.isSyncing { return ("SYNCING", Theme.gold) }
            if !syncEngine.isConfigured { return ("NOT SET UP", Theme.textFaint) }
            if syncEngine.lastError != nil { return ("ERROR", Theme.danger) }
            if syncEngine.isSignedIn { return ("CONNECTED", Theme.success) }
            return ("IDLE", Theme.tan)
        }()

        return Text(label)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    /// `now` is refreshed on a timer purely so this string stays honest
    /// while an admin sits on the screen watching it.
    private var lastSyncDescription: String {
        guard let last = syncEngine.lastSyncAt else { return "Never" }
        let absolute = DateFormatter.syncStamp.string(from: last)
        let relative = RelativeDateTimeFormatter.sync.localizedString(for: last, relativeTo: now)
        return "\(absolute) · \(relative)"
    }

    // MARK: - Sync now

    private var syncButton: some View {
        Button {
            Feedback.tap()
            Task { await syncEngine.syncNow() }
        } label: {
            HStack(spacing: 10) {
                if syncEngine.isSyncing {
                    ProgressView().tint(Theme.text)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .bold))
                }
                Text(syncEngine.isSyncing ? "Syncing…" : "Sync Now")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(syncEngine.isSyncing || !syncEngine.isConfigured)
        .opacity(syncEngine.isSyncing || !syncEngine.isConfigured ? 0.5 : 1)
    }

    // MARK: - Pending

    private var pendingGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200), spacing: 16)],
            spacing: 16
        ) {
            MetricTile(
                title: "Employees Queued",
                value: "\(syncEngine.pendingEmployees)",
                icon: "person.2.fill",
                tint: Theme.gold
            )
            MetricTile(
                title: "Punches Queued",
                value: "\(syncEngine.pendingPunches)",
                icon: "wave.3.right",
                tint: Theme.success
            )
            MetricTile(
                title: "Read Receipts",
                value: "\(syncEngine.pendingReceipts)",
                icon: "checkmark.message.fill",
                tint: Theme.tan
            )
            MetricTile(
                title: "Deletions Queued",
                value: "\(syncEngine.pendingDeletions)",
                icon: "trash.fill",
                tint: Theme.danger
            )
        }
    }

    // MARK: - Credentials

    private var credentialsCard: some View {
        DashboardCard("Device Credentials") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("KIOSK EMAIL")
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .tint(Theme.gold)
                        .padding(.vertical, 8)
                        .overlay(underline, alignment: .bottom)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("PASSWORD")
                    SecureField("", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .tint(Theme.gold)
                        .padding(.vertical, 8)
                        .overlay(underline, alignment: .bottom)
                }

                Button {
                    signIn()
                } label: {
                    Label(isSigningIn ? "Signing in…" : "Save & Sign In", systemImage: "key.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!canSignIn)
                .opacity(canSignIn ? 1 : 0.5)

                Text("The password is stored on this iPad only and is never shown again. Re-enter it here if the kiosk ever reports a sign-in error.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(Theme.textFaint)
    }

    private var underline: some View {
        Rectangle()
            .fill(Theme.surfaceStroke)
            .frame(height: 1.5)
    }

    private func signIn() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let secret = password
        isSigningIn = true
        Task {
            await syncEngine.signIn(email: trimmed, password: secret)
            isSigningIn = false
            // Clear the field either way — a stale password sitting in a
            // text field on an unattended kiosk is a liability, and the
            // status pill already reports whether it worked.
            password = ""
            if syncEngine.lastError == nil {
                Feedback.success()
            } else {
                Feedback.error()
            }
        }
    }
}

private extension DateFormatter {
    static let syncStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}

private extension RelativeDateTimeFormatter {
    static let sync: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
