import SwiftUI
import SwiftData

struct VerificationView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let employeeID: UUID
    let missedPunchFrom: Date?

    @State private var employee: Employee?

    private var isCompact: Bool { hSizeClass == .compact }

    private var action: String {
        guard let employee else { return "…" }
        if missedPunchFrom != nil { return "Clock In" }
        return employee.isCurrentlyClockedIn ? "Clock Out" : "Clock In"
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let photoSize: CGFloat = isCompact ? min(180, w * 0.45) : 240
            let nameSize: CGFloat = isCompact ? 30 : 44
            let statusSize: CGFloat = isCompact ? 15 : 18
            let confirmTextSize: CGFloat = isCompact ? 17 : 22
            let confirmIconSize: CGFloat = isCompact ? 22 : 28
            let hPad: CGFloat = isCompact ? 24 : 48

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if let employee {
                    VStack(spacing: isCompact ? 20 : 28) {
                        Spacer(minLength: 0)

                        photo(for: employee, size: photoSize)

                        VStack(spacing: 8) {
                            Text(employee.fullName)
                                .font(.system(size: nameSize, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(statusLine(for: employee))
                                .font(.system(size: statusSize, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, hPad)

                        if let missed = missedPunchFrom {
                            missedPunchAlert(date: missed)
                        }

                        Spacer(minLength: 0)

                        VStack(spacing: 14) {
                            Button(action: confirm) {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: confirmIconSize, weight: .bold))
                                    Text("Confirm — \(action)")
                                        .font(.system(size: confirmTextSize, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 540)

                            Button(role: .cancel) {
                                coordinator.goHome()
                            } label: {
                                Text(isCompact ? "Not me — Cancel" : "That's not me — Cancel")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(maxWidth: 540)
                        }
                        .padding(.bottom, isCompact ? 16 : 20)
                    }
                    .padding(.horizontal, hPad)
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView().tint(Theme.text)
                }
            }
            .onTapGesture { coordinator.userActivity() }
        }
        .onAppear(perform: loadEmployee)
    }

    // MARK: - Pieces

    private func photo(for employee: Employee, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: size + 14, height: size + 14)
                .shadow(color: Theme.gold.opacity(0.4), radius: 24, y: 10)

            if let img = PhotoStorage.load(fileName: employee.photoFileName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(Theme.textFaint)
                    )
            }
        }
    }

    private func statusLine(for employee: Employee) -> String {
        if missedPunchFrom != nil { return "Missed punch detected — see below." }
        if employee.isCurrentlyClockedIn {
            if let openLog = employee.punchLogs
                .filter({ $0.isOpen })
                .sorted(by: { $0.clockInTime > $1.clockInTime })
                .first {
                return "Clocked in since \(timeString(openLog.clockInTime))"
            }
            return "Currently clocked in"
        }
        return "Tap to clock in"
    }

    private func missedPunchAlert(date: Date) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Missed Clock-Out")
                    .font(.system(size: isCompact ? 14 : 16, weight: .heavy, design: .rounded))
                    .tracking(2)
            }
            .foregroundStyle(Theme.text)

            Text("You did not clock out of your last shift (started \(fullDateString(date))). Please see an admin. That shift will be closed now and a new clock-in will begin.")
                .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.text.opacity(0.85))
        }
        .padding(isCompact ? 14 : 18)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.4), radius: 18, y: 6)
        )
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func fullDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Data

    private func loadEmployee() {
        employee = EmployeeLookup.byID(employeeID, in: modelContext)
    }

    private func confirm() {
        guard let employee else { return }
        coordinator.userActivity()

        if missedPunchFrom != nil {
            let openLogs = employee.punchLogs.filter { $0.isOpen }
            let endOfDay = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: openLogs.first?.clockInTime ?? Date()
            ) ?? Date()
            for log in openLogs {
                log.clockOutTime = endOfDay
                log.wasForcedOut = true
            }
            let newLog = PunchLog(employee: employee, clockInTime: Date())
            modelContext.insert(newLog)
            employee.isCurrentlyClockedIn = true
            try? modelContext.save()
            Feedback.success()
            coordinator.go(to: .punchSuccess(name: employee.fullName, didClockIn: true))
            return
        }

        if employee.isCurrentlyClockedIn {
            if let openLog = employee.punchLogs
                .filter({ $0.isOpen })
                .sorted(by: { $0.clockInTime > $1.clockInTime })
                .first {
                openLog.clockOutTime = Date()
            }
            employee.isCurrentlyClockedIn = false
            try? modelContext.save()
            Feedback.success()
            coordinator.go(to: .punchSuccess(name: employee.fullName, didClockIn: false))
        } else {
            let log = PunchLog(employee: employee, clockInTime: Date())
            modelContext.insert(log)
            employee.isCurrentlyClockedIn = true
            try? modelContext.save()
            Feedback.success()
            coordinator.go(to: .punchSuccess(name: employee.fullName, didClockIn: true))
        }
    }
}

struct PunchSuccessView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let name: String
    let didClockIn: Bool

    @State private var show = false

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let circleSize: CGFloat = isCompact ? min(180, w * 0.5) : 220
            let iconSize: CGFloat = circleSize * 0.5
            let titleSize: CGFloat = isCompact ? 36 : 48
            let messageSize: CGFloat = isCompact ? 17 : 20

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: isCompact ? 24 : 32) {
                    ZStack {
                        Circle()
                            .fill(Theme.brandGradient)
                            .frame(width: circleSize, height: circleSize)
                            .shadow(color: Theme.gold.opacity(0.5), radius: 30, y: 12)
                            .scaleEffect(show ? 1 : 0.5)
                            .opacity(show ? 1 : 0)
                        Image(systemName: didClockIn ? "checkmark" : "hand.wave.fill")
                            .font(.system(size: iconSize, weight: .black))
                            .foregroundStyle(Theme.text)
                            .scaleEffect(show ? 1 : 0.2)
                            .opacity(show ? 1 : 0)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.6), value: show)

                    VStack(spacing: 6) {
                        Text(didClockIn ? "Clocked In" : "Clocked Out")
                            .font(.system(size: titleSize, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(didClockIn ? "Have a great class, \(name)!" : "Thanks for teaching, \(name)!")
                            .font(.system(size: messageSize, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, isCompact ? 24 : 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            show = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                coordinator.goHome()
            }
        }
    }
}
