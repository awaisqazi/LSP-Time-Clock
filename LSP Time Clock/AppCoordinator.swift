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
}

@Observable
@MainActor
final class AppCoordinator {
    static let adminPIN = "2468"
    static let autoResetInterval: TimeInterval = 30

    var mode: AppMode = .idle
    var toast: ToastMessage?

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
    }

    func userActivity() {
        restartResetTimerIfNeeded()
    }

    private func restartResetTimerIfNeeded() {
        resetTask?.cancel()
        resetTask = nil

        let needs: Bool
        switch mode {
        case .idle, .punchSuccess: needs = false
        default: needs = true
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
