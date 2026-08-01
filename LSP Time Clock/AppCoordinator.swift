import SwiftUI
import Observation

enum ScanPurpose: Equatable {
    case punch
    case replaceCard(employeeID: UUID)
}

enum AppMode: Equatable {
    case idle
    case scanning(ScanPurpose)
    case registering(rfid: String)
    case verifying(employeeID: UUID, missedPunchFrom: Date?)
    case punchSuccess(name: String, didClockIn: Bool)
    case adminPIN
    case admin
    case adminEmployeeDetail(employeeID: UUID)
    case bulkOnboarding
}

@Observable
@MainActor
final class AppCoordinator {
    static let adminPIN = "2468"
    static let autoResetInterval: TimeInterval = 30

    var mode: AppMode = .idle
    var toast: ToastMessage?

    /// Set to `true` while a system modal (PhotosPicker, fileImporter, camera,
    /// share sheet, etc.) is being presented. While true, scenePhase changes
    /// caused by the OS handing the scene to that modal are ignored — they
    /// are not treated as the user leaving the app, so the kiosk lock does
    /// not fire and the auto-reset timer does not run.
    var isPresentingSystemModal: Bool = false

    /// Hook the App wires to the sync engine at launch. Every trip back to
    /// the Idle screen is a safe, no-one-is-mid-punch moment to talk to the
    /// cloud, so that's where the opportunistic sync is triggered from. Kept
    /// as a closure rather than a direct reference so the coordinator stays
    /// ignorant of networking entirely.
    var onReturnHome: (() -> Void)?

    private var resetTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    struct ToastMessage: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var style: Style
        enum Style { case success, warning, error, info }
    }

    func go(to newMode: AppMode) {
        mode = newMode
        restartResetTimerIfNeeded()
    }

    func goHome() {
        go(to: .idle)
        onReturnHome?()
    }

    func userActivity() {
        restartResetTimerIfNeeded()
    }

    func setPresentingSystemModal(_ presenting: Bool) {
        isPresentingSystemModal = presenting
        // Pausing/resuming any pending reset timer keeps the admin's place
        // while a system picker is up (which can take a while to dismiss).
        restartResetTimerIfNeeded()
    }

    /// Invoked from `ContentView` whenever `scenePhase` changes. When the
    /// scene goes inactive/background, the app locks itself back to the idle
    /// screen — admins must re-enter the PIN to return to the dashboard.
    /// Skipped while a system modal is being presented so iPad picker/file
    /// importer flows don't trigger an unwanted lock.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            return
        case .inactive, .background:
            if isPresentingSystemModal { return }
            lockToIdle()
        @unknown default:
            return
        }
    }

    private func lockToIdle() {
        switch mode {
        case .idle, .punchSuccess:
            return
        default:
            mode = .idle
            resetTask?.cancel()
            resetTask = nil
        }
    }

    private func restartResetTimerIfNeeded() {
        resetTask?.cancel()
        resetTask = nil

        // Don't auto-reset while a system modal is presented (the user
        // could be browsing the photo library for longer than 30s).
        if isPresentingSystemModal { return }

        let needs: Bool
        switch mode {
        // Idle states: no timer needed (already at the destination).
        case .idle, .punchSuccess:
            needs = false
        // Admin sessions: kiosk should stay open until the admin
        // explicitly locks via the Lock button or the scene ends
        // (app backgrounded / device locked). `handleScenePhaseChange`
        // takes care of the latter.
        //
        // Registration is grouped here even though it's triggered by a
        // customer-facing card scan: filling in name/email/photo is a
        // deliberate, admin-supervised data-entry flow that routinely
        // takes longer than the 30-second kiosk timeout. Letting it
        // auto-reset would discard the half-typed form. The Cancel
        // button or scenePhase change still gets it back to idle.
        case .admin, .adminEmployeeDetail, .bulkOnboarding, .registering:
            needs = false
        // Customer-facing kiosk states: reset after inactivity so the
        // next person walking up sees a clean Idle screen.
        case .scanning, .verifying, .adminPIN:
            needs = true
        }
        guard needs else { return }

        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoResetInterval))
            guard let self, !Task.isCancelled else { return }
            self.mode = .idle
        }
    }

    func showToast(_ text: String, style: ToastMessage.Style = .info, duration: TimeInterval = 2.5) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, style: style)
        toast = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            if self.toast?.id == message.id { self.toast = nil }
        }
    }
}
