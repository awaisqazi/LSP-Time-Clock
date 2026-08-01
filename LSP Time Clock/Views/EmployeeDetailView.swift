import SwiftUI
import SwiftData

struct EmployeeDetailView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let employeeID: UUID

    @State private var employee: Employee?
    @State private var showingReplaceConfirm = false
    @State private var showingDeactivateConfirm = false
    @State private var showingActivateConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var showingAddPunch = false
    @State private var editingPunch: PunchLog?

    /// Mirror of `employee.profileRole` so the segmented control has
    /// something to bind to. We sync this from the model on appear and
    /// write back through `updateProfileRole(_:)` whenever the admin
    /// taps a different segment.
    @State private var profileRoleSelection: EmployeeRole = .instructor

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if let employee {
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: isCompact ? 16 : 24) {
                            profileCard(for: employee)

                            classificationCard(for: employee)

                            actions(for: employee)

                            historySection(for: employee)
                        }
                        .padding(isCompact ? 16 : 24)
                    }
                }
            } else {
                ProgressView().tint(Theme.text)
            }
        }
        .onAppear {
            let loaded = EmployeeLookup.byID(employeeID, in: modelContext)
            employee = loaded
            profileRoleSelection = loaded?.profileRole ?? .instructor
        }
        .onTapGesture { coordinator.userActivity() }
        .sheet(isPresented: $showingEdit, onDismiss: {
            // The Edit sheet can also flip profileRole, so re-sync the
            // inline picker to whatever was saved while it was open.
            if let employee {
                profileRoleSelection = employee.profileRole
            }
        }) {
            if let employee {
                EmployeeEditView(employee: employee)
            }
        }
        .sheet(isPresented: $showingAddPunch) {
            if let employee {
                ManualPunchAddView(prefilledEmployee: employee)
            }
        }
        .sheet(item: $editingPunch) { log in
            PunchLogEditView(log: log)
        }
        .alert("Has the lost card fee been collected?", isPresented: $showingReplaceConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Yes — Scan New Card") {
                coordinator.go(to: .scanning(.replaceCard(employeeID: employeeID)))
            }
        } message: {
            Text("Scan the replacement card after collecting the fee. The new card will overwrite the instructor's current card tag.")
        }
        .alert("Deactivate Instructor?", isPresented: $showingDeactivateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Deactivate", role: .destructive) { deactivateEmployee() }
        } message: {
            Text("They will be hidden from the active roster and unable to clock in. Their punch history is preserved and they can be reactivated any time.")
        }
        .alert("Reactivate Instructor?", isPresented: $showingActivateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reactivate") { activateEmployee() }
        } message: {
            Text("They will reappear on the active roster and can clock in with their card.")
        }
        .alert("Delete Permanently?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteEmployee() }
        } message: {
            Text(deleteConfirmMessage)
        }
    }

    /// Built per-render so the message can name the employee and surface
    /// the card # that's about to free up — admins typically need the
    /// number to hand the physical card to a new hire on the spot.
    private var deleteConfirmMessage: String {
        guard let employee else { return "" }
        let name = employee.displayName
        let card: String = employee.hasAssignedCard
            ? "\nThe RFID card #\(employee.rfidTag) will be released and can be assigned to someone else."
            : ""
        return "\(name)'s profile, photo, and entire punch history will be permanently deleted. This cannot be undone — use Deactivate if you may need their history later.\(card)"
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.go(to: .admin)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Directory")
                }
                .font(.system(size: isCompact ? 15 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            }

            Spacer()

            Button {
                coordinator.goHome()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, isCompact ? 12 : 16)
        .background(
            Theme.surface
                .shadow(color: Theme.tan.opacity(0.15), radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private func profileCard(for employee: Employee) -> some View {
        if isCompact {
            compactProfileCard(for: employee)
        } else {
            regularProfileCard(for: employee)
        }
    }

    private func compactProfileCard(for employee: Employee) -> some View {
        VStack(spacing: 12) {
            profilePhoto(for: employee, size: 100)

            VStack(spacing: 4) {
                Text(employee.fullName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(employee.email)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                    Text(employee.rfidTag)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Theme.textFaint)

                statusPill(clockedIn: employee.isCurrentlyClockedIn)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func regularProfileCard(for employee: Employee) -> some View {
        HStack(spacing: 20) {
            profilePhoto(for: employee, size: 120)

            VStack(alignment: .leading, spacing: 6) {
                Text(employee.fullName)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(employee.email)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                    Text(employee.rfidTag)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Theme.textFaint)

                statusPill(clockedIn: employee.isCurrentlyClockedIn)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .card()
    }

    private func profilePhoto(for employee: Employee, size: CGFloat) -> some View {
        Group {
            if let img = PhotoStorage.load(fileName: employee.photoFileName) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.37))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.tan.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.brandGradient, lineWidth: 3))
    }

    private func statusPill(clockedIn: Bool) -> some View {
        Text(clockedIn ? "CLOCKED IN" : "CLOCKED OUT")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    clockedIn
                        ? Theme.success.opacity(0.15)
                        : Theme.tan.opacity(0.2)
                )
            )
            .foregroundStyle(clockedIn ? Theme.success : Theme.textMuted)
    }

    /// Inline classification editor surfaced directly on the detail page so
    /// admins don't have to open the full Edit sheet (and re-confirm the
    /// PIN) just to flip an instructor's role. Saves on every selection
    /// change with a toast for feedback.
    private func classificationCard(for employee: Employee) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLASSIFICATION")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Text(employee.profileRole.displayName)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.brandGradient))
                    .foregroundStyle(Theme.text)
            }

            Picker("Classification", selection: $profileRoleSelection) {
                ForEach(EmployeeRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: profileRoleSelection) { _, newValue in
                updateProfileRole(newValue)
            }

            Text("Determines whether this employee can clock in as an Instructor, a Coordinator, or pick a side at clock-in.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
    }

    private func updateProfileRole(_ newRole: EmployeeRole) {
        guard let employee else { return }
        guard employee.profileRole != newRole else { return }
        employee.profileRole = newRole
        employee.markDirty()
        do {
            try modelContext.save()
            Feedback.success()
            coordinator.showToast("Role set to \(newRole.displayName).", style: .success)
            // Re-bind to force the header chip + any computed views to
            // re-render with the new value.
            self.employee = employee
        } catch {
            Feedback.error()
            coordinator.showToast("Couldn't save role: \(error.localizedDescription)", style: .error)
            // Revert the picker so the UI mirrors what's actually persisted.
            profileRoleSelection = employee.profileRole
        }
    }

    private func actions(for employee: Employee) -> some View {
        VStack(spacing: 12) {
            Button {
                showingEdit = true
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                showingReplaceConfirm = true
            } label: {
                Label("Replace Lost Card", systemImage: "creditcard.trianglebadge.exclamationmark")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(SecondaryButtonStyle())

            if employee.isActive {
                Button(role: .destructive) {
                    showingDeactivateConfirm = true
                } label: {
                    Label("Deactivate Instructor", systemImage: "person.fill.xmark")
                        .foregroundStyle(Theme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    showingActivateConfirm = true
                } label: {
                    Label("Reactivate Instructor", systemImage: "person.fill.checkmark")
                        .foregroundStyle(Theme.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            // Hard delete sits below Deactivate so it isn't the obvious
            // first choice — the safer "keep history" action is what an
            // admin lands on by default. Use this when the card needs to
            // come back into circulation for a new hire.
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Permanently", systemImage: "trash.fill")
                    .foregroundStyle(Theme.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func historySection(for employee: Employee) -> some View {
        let sorted = employee.punchLogs.sorted { $0.clockInTime > $1.clockInTime }
        let totalHours = sorted.compactMap { $0.totalHours }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Punch History")
                    .font(.system(size: isCompact ? 18 : 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(String(format: "%.1f hrs total", totalHours))
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textMuted)

                Button {
                    showingAddPunch = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: isCompact ? 12 : 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.gold))
                }
                .buttonStyle(.plain)
            }

            if sorted.isEmpty {
                Text("No punches recorded.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(sorted) { log in
                        Button {
                            editingPunch = log
                        } label: {
                            punchRow(log)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private func punchRow(_ log: PunchLog) -> some View {
        let dateFmt: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, MMM d"
            return f
        }()
        let timeFmt: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f
        }()

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateFmt.string(from: log.clockInTime))
                    .font(.system(size: isCompact ? 13 : 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Text("IN \(timeFmt.string(from: log.clockInTime))")
                    Text("·")
                    if let out = log.clockOutTime {
                        Text("OUT \(timeFmt.string(from: out))")
                    } else {
                        Text("OUT —")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(log.totalHours.map { String(format: "%.2f h", $0) } ?? "—")
                    .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                if log.wasForcedOut {
                    Text("FORCED")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Theme.gold)
                        )
                        .foregroundStyle(Theme.text)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .padding(.leading, 4)
        }
        .padding(.horizontal, isCompact ? 10 : 14)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cream.opacity(0.7))
        )
        .contentShape(Rectangle())
    }

    private func deactivateEmployee() {
        guard let employee else { return }
        // If they're on the clock when deactivated, close the open shift
        // so it doesn't sit dangling in payroll exports forever.
        if employee.isCurrentlyClockedIn,
           let open = employee.punchLogs.filter(\.isOpen).max(by: { $0.clockInTime < $1.clockInTime }) {
            open.clockOutTime = .now
            open.wasForcedOut = true
            open.markDirty()
            employee.isCurrentlyClockedIn = false
        }
        employee.isActive = false
        employee.markDirty()
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("\(employee.displayName) deactivated.", style: .success)
        // Re-bind the local state so the UI flips to "Reactivate" without
        // a navigation pop. The @Model object is the same instance.
        self.employee = employee
    }

    private func activateEmployee() {
        guard let employee else { return }
        employee.isActive = true
        employee.markDirty()
        try? modelContext.save()
        Feedback.success()
        coordinator.showToast("\(employee.displayName) reactivated.", style: .success)
        self.employee = employee
    }

    /// Hard delete — wipes the employee row, their photo file, and (via
    /// the cascade rule on `Employee.punchLogs`) every punch attached to
    /// them. Once the row is gone the unique-constraint slot on `rfidTag`
    /// is freed, so the card can be re-registered to a new person on the
    /// next scan.
    private func deleteEmployee() {
        guard let employee else { return }

        let displayName = employee.displayName
        let photoFileName = employee.photoFileName

        // Queue the cloud tombstones *before* the rows vanish — afterwards
        // there is nothing left to mark dirty and the deletion would be
        // invisible to Supabase. The punches need their own entries: the
        // server's FK cascade only fires on a hard delete, and setting
        // `deleted_at` on the employee doesn't propagate.
        SyncDeletionQueue.enqueueEmployee(employee, in: modelContext)

        // Drop the model first so the cascade fires; SwiftData removes
        // the related PunchLog rows in the same save.
        modelContext.delete(employee)

        do {
            try modelContext.save()
        } catch {
            Feedback.error()
            coordinator.showToast("Couldn't delete: \(error.localizedDescription)", style: .error)
            return
        }

        // Photo cleanup runs after the save so we don't orphan the file
        // on disk if SwiftData rolls the delete back. Best-effort — the
        // PhotoStorage helper already swallows IO errors.
        if !photoFileName.isEmpty {
            PhotoStorage.delete(fileName: photoFileName)
        }

        Feedback.success()
        coordinator.showToast("\(displayName) deleted.", style: .success)
        // Pop back to the roster so we don't render stale fields against
        // a now-deleted model object.
        coordinator.go(to: .admin)
    }
}
