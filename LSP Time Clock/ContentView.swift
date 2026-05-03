import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            screen
                .id(modeKey(coordinator.mode))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            toastOverlay
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.25), value: modeKey(coordinator.mode))
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var screen: some View {
        switch coordinator.mode {
        case .idle:
            IdleView()
        case .scanning(let purpose):
            ScanView(purpose: purpose)
        case .registering(let rfid):
            RegistrationView(rfidTag: rfid)
        case .verifying(let id, let missed):
            VerificationView(employeeID: id, missedPunchFrom: missed)
        case .punchSuccess(let name, let didClockIn):
            PunchSuccessView(name: name, didClockIn: didClockIn)
        case .adminPIN:
            AdminPINView()
        case .admin:
            AdminDashboardView()
        case .adminEmployeeDetail(let id):
            EmployeeDetailView(employeeID: id)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = coordinator.toast {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: icon(for: toast.style))
                        .font(.system(size: 18, weight: .bold))
                    Text(toast.text)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(foreground(for: toast.style))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(background(for: toast.style))
                )
                .shadow(color: Theme.tan.opacity(0.4), radius: 14, y: 6)
                .padding(.bottom, 48)
                .padding(.horizontal, 32)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast.id)
        }
    }

    private func icon(for style: AppCoordinator.ToastMessage.Style) -> String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error:   "xmark.octagon.fill"
        case .info:    "info.circle.fill"
        }
    }

    private func foreground(for style: AppCoordinator.ToastMessage.Style) -> Color {
        switch style {
        case .success, .info, .error: .white
        case .warning: Theme.text
        }
    }

    private func background(for style: AppCoordinator.ToastMessage.Style) -> Color {
        switch style {
        case .success: Theme.success
        case .warning: Theme.gold
        case .error:   Theme.danger
        case .info:    Theme.text
        }
    }

    private func modeKey(_ mode: AppMode) -> String {
        switch mode {
        case .idle: "idle"
        case .scanning(let p):
            switch p {
            case .punch: "scan.punch"
            case .replaceCard(let id): "scan.replace.\(id)"
            }
        case .registering(let tag): "register.\(tag)"
        case .verifying(let id, let d): "verify.\(id).\(d?.timeIntervalSince1970 ?? 0)"
        case .punchSuccess(let n, let inOut): "success.\(n).\(inOut)"
        case .adminPIN: "adminPIN"
        case .admin: "admin"
        case .adminEmployeeDetail(let id): "admin.detail.\(id)"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppCoordinator())
        .modelContainer(for: [Employee.self, PunchLog.self], inMemory: true)
}
