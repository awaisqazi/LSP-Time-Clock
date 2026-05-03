import SwiftUI
import SwiftData
import PhotosUI

/// Sequential queue for assigning RFID cards + profile photos to employees
/// who were bulk-imported via CSV. Each employee is saved to persistent
/// storage as soon as their card and photo are captured, so the queue is
/// crash-resilient — completed records are filtered out automatically the
/// next time the admin re-enters this view.
struct BulkOnboardingView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @Query(sort: [SortDescriptor(\Employee.createdAt), SortDescriptor(\Employee.email)])
    private var allEmployees: [Employee]

    @State private var skippedIDs: Set<UUID> = []
    @State private var scannedTag: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var saveError: String?
    @State private var rfidFieldActive = true

    private var isCompact: Bool { hSizeClass == .compact }

    /// All pending employees that haven't been skipped during the current
    /// session. Filtering happens on each render so an immediate save makes
    /// the just-completed record fall out of the queue automatically.
    private var queue: [Employee] {
        allEmployees.filter { $0.isPendingOnboarding && !skippedIDs.contains($0.id) }
    }

    private var current: Employee? { queue.first }

    /// Total number originally pending when the user entered this flow plus
    /// any new ones added since (we treat queue.count + already-completed
    /// in this session as the total). For simplicity we just show position
    /// out of the live queue length plus the index already passed.
    @State private var sessionStartCount: Int = 0
    @State private var sessionCompletedCount: Int = 0

    private var positionIndex: Int { sessionCompletedCount + 1 }
    private var totalCount: Int {
        max(positionIndex + queue.count - 1, sessionStartCount)
    }

    /// The card is mandatory; the photo can be added later via Edit on the
    /// dashboard, so it does not block save here.
    private var canSave: Bool {
        !scannedTag.isEmpty
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let employee = current {
                    ScrollView {
                        VStack(spacing: isCompact ? 18 : 24) {
                            progressPill
                            employeeCard(employee)
                            cardSection
                            photoSection
                            actions(for: employee)
                            if let saveError {
                                Text(saveError)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        .padding(isCompact ? 16 : 24)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    emptyState
                }

                if current != nil {
                    HiddenRFIDField(isActive: $rfidFieldActive) { scanned in
                        let cleaned = sanitize(scanned)
                        if !cleaned.isEmpty {
                            scannedTag = cleaned
                            Feedback.cardRecognized()
                        }
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            sessionStartCount = queue.count
            rfidFieldActive = true
        }
        .onDisappear { rfidFieldActive = false }
        .onChange(of: pickedItem) { _, newItem in
            Task { await loadPicked(newItem) }
        }
        .onChange(of: current?.id) { _, _ in
            scannedTag = ""
            selectedImage = nil
            pickedItem = nil
            saveError = nil
            rfidFieldActive = true
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { img in
                    selectedImage = img
                    showingCamera = false
                    coordinator.setPresentingSystemModal(false)
                    rfidFieldActive = true
                },
                onCancel: {
                    showingCamera = false
                    coordinator.setPresentingSystemModal(false)
                    rfidFieldActive = true
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $pickedItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: showingPhotosPicker) { _, isShowing in
            if !isShowing {
                // Cancel-without-pick path: loadPicked() never runs, so we
                // must clear the modal flag here too. Idempotent with the
                // flag clearing inside loadPicked().
                coordinator.setPresentingSystemModal(false)
                rfidFieldActive = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.go(to: .admin)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Done")
                }
                .font(.system(size: isCompact ? 15 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            }

            Spacer()

            Text("Complete Setup")
                .font(.system(size: isCompact ? 17 : 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

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

    private var progressPill: some View {
        Text("Employee \(positionIndex) of \(totalCount)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Theme.brandGradient)
            )
            .foregroundStyle(Theme.text)
    }

    private func employeeCard(_ employee: Employee) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: isCompact ? 38 : 44, weight: .black))
                .foregroundStyle(Theme.brandGradient)

            Text(employee.fullName.trimmingCharacters(in: .whitespaces).isEmpty
                 ? employee.email
                 : employee.fullName)
                .font(.system(size: isCompact ? 22 : 26, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(employee.email)
                .font(.system(size: isCompact ? 13 : 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Step 1 — Scan Card")

            HStack(spacing: 12) {
                Image(systemName: scannedTag.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scannedTag.isEmpty ? Theme.textFaint : Theme.success)

                if scannedTag.isEmpty {
                    Text("Hold the RFID card to the reader…")
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Card captured")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(Theme.success)
                        Text(scannedTag)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Spacer()

                if !scannedTag.isEmpty {
                    Button {
                        scannedTag = ""
                        rfidFieldActive = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private var photoSection: some View {
        let size: CGFloat = isCompact ? 130 : 160

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Step 2 — Add Photo")
                Text("(optional)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
            }

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.surfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Theme.surfaceStroke, lineWidth: 1)
                        )
                        .frame(width: size, height: size)

                    if let img = selectedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "person.crop.square.badge.camera")
                                .font(.system(size: size * 0.3, weight: .light))
                            Text("No photo")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Theme.textFaint)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        coordinator.setPresentingSystemModal(true)
                        rfidFieldActive = false
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        // Set the flag *before* the picker presents so the
                        // .inactive scenePhase event arrives with the flag
                        // already true. simultaneousGesture races the
                        // picker's own tap target on iPad and is unreliable.
                        coordinator.setPresentingSystemModal(true)
                        rfidFieldActive = false
                        showingPhotosPicker = true
                    } label: {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card()
    }

    @ViewBuilder
    private func actions(for employee: Employee) -> some View {
        let primaryLabel: String = {
            if selectedImage == nil {
                return queue.count > 1 ? "Save & Add Photo Later" : "Save Without Photo"
            } else {
                return queue.count > 1 ? "Save & Next" : "Save & Finish"
            }
        }()

        VStack(spacing: 12) {
            Button {
                save(for: employee)
            } label: {
                Text(primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)

            if selectedImage == nil {
                Text("You can add the photo any time from the dashboard's Edit screen.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    skip(employee)
                } label: { Text("Skip") }
                .buttonStyle(SecondaryButtonStyle())

                Button(role: .cancel) {
                    coordinator.go(to: .admin)
                } label: { Text("Pause") }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(Theme.success)
            Text("All set!")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(sessionCompletedCount > 0
                 ? "\(sessionCompletedCount) instructor\(sessionCompletedCount == 1 ? "" : "s") fully onboarded."
                 : "No instructors are awaiting setup.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                coordinator.go(to: .admin)
            } label: {
                Text("Back to Dashboard")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(Theme.textFaint)
    }

    // MARK: - Actions

    private func skip(_ employee: Employee) {
        skippedIDs.insert(employee.id)
        Feedback.tap()
    }

    private func save(for employee: Employee) {
        guard canSave else { return }

        // Reject duplicate cards before any partial work happens.
        if let conflict = EmployeeLookup.byRFID(scannedTag, in: modelContext),
           conflict.id != employee.id {
            saveError = "That card is already assigned to \(conflict.fullName)."
            Feedback.error()
            return
        }

        do {
            // Photo is optional. Only write a new file (and clean up the
            // old one) if the admin actually picked an image.
            if let image = selectedImage {
                let photoFileName = try PhotoStorage.save(image)
                let oldPhoto = employee.photoFileName
                employee.photoFileName = photoFileName
                if !oldPhoto.isEmpty, oldPhoto != photoFileName {
                    PhotoStorage.delete(fileName: oldPhoto)
                }
            }
            employee.rfidTag = scannedTag

            try modelContext.save()

            sessionCompletedCount += 1
            Feedback.success()
            let displayName = employee.fullName.trimmingCharacters(in: .whitespaces).isEmpty
                ? employee.email
                : employee.fullName
            coordinator.showToast("\(displayName) is set up.", style: .success)
            // Clear local state — `onChange(of: current?.id)` will also fire
            // as the next employee surfaces in the live query.
            scannedTag = ""
            selectedImage = nil
            pickedItem = nil
            saveError = nil
            rfidFieldActive = true
        } catch {
            saveError = error.localizedDescription
            Feedback.error()
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            await MainActor.run { selectedImage = ui }
        }
        await MainActor.run {
            coordinator.setPresentingSystemModal(false)
            rfidFieldActive = true
        }
    }

    private func sanitize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
