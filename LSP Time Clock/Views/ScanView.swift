import SwiftUI
import SwiftData

struct ScanView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.scenePhase) private var scenePhase

    let purpose: ScanPurpose

    @State private var isFieldActive = true
    @State private var pulse = false
    /// Bumped every time we want HiddenRFIDField to perform a fresh
    /// resign+become first-responder cycle. Critical for recovering
    /// scanner input after the iPad has slept overnight: iOS sometimes
    /// keeps the field's `isFirstResponder` flag set while the actual
    /// keyboard input pipeline is detached, so just toggling `isActive`
    /// isn't enough — we need to force iOS to re-grant focus.
    @State private var refocusGeneration: Int = 0
    @State private var showingTroubleshooting = false

    private var isCompact: Bool { hSizeClass == .compact }

    private var heading: String {
        switch purpose {
        case .punch: "Waiting for Card"
        case .replaceCard: "Scan New Card"
        }
    }

    private var subheading: String {
        switch purpose {
        case .punch: "Hold your RFID card against the reader"
        case .replaceCard: "Present the replacement card to the reader"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ringFrame: CGFloat = isCompact ? min(260, w * 0.7) : 320
            let innerCircle: CGFloat = ringFrame * 0.56
            let waveSize: CGFloat = ringFrame * 0.225
            let headingSize: CGFloat = isCompact ? 30 : 44
            let subheadingSize: CGFloat = isCompact ? 16 : 19
            let hPad: CGFloat = isCompact ? 24 : 48

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: isCompact ? 24 : 36) {
                    Spacer(minLength: 0)

                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .stroke(Theme.gold.opacity(0.45 - Double(i) * 0.12), lineWidth: 2)
                                .scaleEffect(pulse ? 1.4 + CGFloat(i) * 0.3 : 1)
                                .opacity(pulse ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 1.8)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.25),
                                    value: pulse
                                )
                        }

                        Circle()
                            .fill(Theme.brandGradient)
                            .frame(width: innerCircle, height: innerCircle)
                            .shadow(color: Theme.gold.opacity(0.45), radius: 30, y: 12)

                        Image(systemName: "wave.3.right")
                            .font(.system(size: waveSize, weight: .black))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(width: ringFrame, height: ringFrame)

                    VStack(spacing: 12) {
                        Text(heading)
                            .font(.system(size: headingSize, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(subheading)
                            .font(.system(size: subheadingSize, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, hPad)

                    Spacer(minLength: 0)

                    Button(role: .cancel) {
                        switch purpose {
                        case .punch:
                            coordinator.goHome()
                        case .replaceCard(let id):
                            coordinator.go(to: .adminEmployeeDetail(employeeID: id))
                        }
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 300)
                    .padding(.bottom, 4)

                    Button {
                        // Mark the troubleshooting sheet as a "system
                        // modal" so the 30s scan-screen auto-reset
                        // doesn't kick the kiosk back to Idle while the
                        // user is mid-video. The flag is cleared in the
                        // sheet's onDismiss.
                        coordinator.setPresentingSystemModal(true)
                        showingTroubleshooting = true
                        coordinator.userActivity()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Having trouble?")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .background(
                            Capsule()
                                .fill(Theme.surface)
                                .overlay(
                                    Capsule().stroke(Theme.surfaceStroke, lineWidth: 1)
                                )
                                .shadow(color: Theme.tan.opacity(0.12), radius: 6, y: 2)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, isCompact ? 16 : 24)
                }
                .padding(.horizontal, hPad)

                HiddenRFIDField(
                    isActive: $isFieldActive,
                    refocusGeneration: refocusGeneration
                ) { scanned in
                    handleScan(scanned)
                }
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
            }
            // Full-screen, invisible tap target. Every tap forces a fresh
            // focus grant on the hidden field — useful when iOS has
            // detached the input pipeline while the device slept.
            .contentShape(Rectangle())
            .onTapGesture {
                forceRefocus()
                coordinator.userActivity()
            }
        }
        .onAppear {
            pulse = true
            isFieldActive = true
            forceRefocus()
        }
        .onDisappear { isFieldActive = false }
        .onChange(of: scenePhase) { _, phase in
            // Recover input after the iPad has been backgrounded or
            // asleep — the most common cause of "scanner beeps but the
            // app shows nothing" after an overnight idle.
            if phase == .active {
                isFieldActive = true
                forceRefocus()
            }
        }
        .sheet(isPresented: $showingTroubleshooting, onDismiss: {
            // Restore the auto-reset timer and reclaim first responder
            // (the sheet briefly steals it during dismissal).
            coordinator.setPresentingSystemModal(false)
            forceRefocus()
        }) {
            TroubleshootingView()
        }
    }

    /// Bumps the refocus counter so HiddenRFIDField forces a clean
    /// resign+become cycle on its underlying UITextField.
    private func forceRefocus() {
        isFieldActive = true
        refocusGeneration &+= 1  // wraps cleanly on overflow
    }

    private func handleScan(_ raw: String) {
        let tag = sanitize(raw)
        guard !tag.isEmpty else { return }

        Feedback.cardRecognized()

        switch purpose {
        case .punch:
            resolvePunch(for: tag)
        case .replaceCard(let employeeID):
            resolveCardReplacement(newTag: tag, for: employeeID)
        }
    }

    private func resolvePunch(for tag: String) {
        if let employee = EmployeeLookup.byRFID(tag, in: modelContext) {
            let missed = detectMissedPunch(for: employee)
            coordinator.go(to: .verifying(employeeID: employee.id, missedPunchFrom: missed))
        } else {
            coordinator.go(to: .registering(rfid: tag))
        }
    }

    private func resolveCardReplacement(newTag: String, for employeeID: UUID) {
        if let existing = EmployeeLookup.byRFID(newTag, in: modelContext), existing.id != employeeID {
            Feedback.error()
            coordinator.showToast(
                "That card is already assigned to \(existing.fullName).",
                style: .error
            )
            coordinator.go(to: .adminEmployeeDetail(employeeID: employeeID))
            return
        }
        guard let target = EmployeeLookup.byID(employeeID, in: modelContext) else {
            coordinator.goHome()
            return
        }
        target.rfidTag = newTag
        target.markDirty()
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("Card replaced for \(target.fullName).", style: .success)
        coordinator.go(to: .adminEmployeeDetail(employeeID: employeeID))
    }

    private func detectMissedPunch(for employee: Employee) -> Date? {
        let openLogs = employee.punchLogs.filter { $0.isOpen }
        guard let openest = openLogs.sorted(by: { $0.clockInTime > $1.clockInTime }).first else {
            return nil
        }
        let calendar = Calendar.current
        if !calendar.isDateInToday(openest.clockInTime) {
            return openest.clockInTime
        }
        return nil
    }

    private func sanitize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

enum EmployeeLookup {
    static func byRFID(_ tag: String, in ctx: ModelContext) -> Employee? {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.rfidTag == tag }
        )
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor))?.first
    }

    static func byID(_ id: UUID, in ctx: ModelContext) -> Employee? {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor))?.first
    }
}
