import SwiftUI
import SwiftData
import PhotosUI

struct RegistrationView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let rfidTag: String

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var profileRole: EmployeeRole = .instructor
    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var saveError: String?

    @FocusState private var focused: Field?

    enum Field: Hashable { case first, last, email }

    private var isCompact: Bool { hSizeClass == .compact }

    private var canSave: Bool {
        // Photo is optional — matches the bulk-onboarding flow, where the
        // admin can fill in a photo later from the dashboard.
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: isCompact ? 20 : 24) {
                    header

                    photoSection

                    VStack(spacing: isCompact ? 12 : 16) {
                        textField("First name", text: $firstName, field: .first)
                        textField("Last name", text: $lastName, field: .last)
                        textField("Email", text: $email, field: .email, keyboard: .emailAddress)
                        rolePicker
                    }
                    .card()

                    if isCompact {
                        VStack(spacing: 12) {
                            Button(action: save) {
                                Text("Save & Continue")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.5)

                            Button(role: .cancel) {
                                coordinator.goHome()
                            } label: { Text("Cancel") }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    } else {
                        HStack(spacing: 16) {
                            Button(role: .cancel) {
                                coordinator.goHome()
                            } label: { Text("Cancel") }
                            .buttonStyle(SecondaryButtonStyle())

                            Button(action: save) {
                                Text("Save & Continue")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.5)
                        }
                    }

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
        }
        .onChange(of: pickedItem) { _, newItem in
            Task { await loadPicked(newItem) }
        }
        .onTapGesture { coordinator.userActivity() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { img in
                    selectedImage = img
                    showingCamera = false
                    coordinator.setPresentingSystemModal(false)
                },
                onCancel: {
                    showingCamera = false
                    coordinator.setPresentingSystemModal(false)
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
                coordinator.setPresentingSystemModal(false)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: isCompact ? 38 : 44, weight: .black))
                .foregroundStyle(Theme.brandGradient)

            Text("Card not found")
                .font(.system(size: isCompact ? 24 : 28, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Register this card to an instructor")
                .font(.system(size: isCompact ? 14 : 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            Text(rfidTag)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.tan.opacity(0.2)))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var photoSection: some View {
        let size: CGFloat = isCompact ? 140 : 170

        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("PHOTO")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.textFaint)
                Text("(optional)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Theme.surfaceStroke, lineWidth: 1)
                    )
                    .frame(width: size, height: size)

                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.square.badge.camera")
                            .font(.system(size: size * 0.27, weight: .light))
                        Text("No photo")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Theme.textFaint)
                }
            }

            HStack(spacing: 12) {
                Button {
                    coordinator.setPresentingSystemModal(true)
                    showingCamera = true
                } label: {
                    Label(isCompact ? "Camera" : "Take Photo", systemImage: "camera.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    // Programmatic presentation guarantees the modal flag
                    // is set in the same synchronous step, before scenePhase
                    // flips to .inactive on iPad. (PhotosPicker's own button
                    // races simultaneousGesture and would cause the kiosk
                    // lock to fire while the picker was opening.)
                    coordinator.setPresentingSystemModal(true)
                    showingPhotosPicker = true
                } label: {
                    Label(isCompact ? "Library" : "Photo Library", systemImage: "photo.on.rectangle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROLE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textFaint)
            Picker("Role", selection: $profileRole) {
                ForEach(EmployeeRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func textField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textFaint)
            TextField("", text: text)
                .focused($focused, equals: field)
                .keyboardType(keyboard)
                .autocorrectionDisabled(field == .email)
                .textInputAutocapitalization(field == .email ? .never : .words)
                .submitLabel(field == .email ? .done : .next)
                .onSubmit { advanceFocus(from: field) }
                .font(.system(size: isCompact ? 18 : 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .tint(Theme.gold)
                .padding(.vertical, 10)
                .overlay(
                    Rectangle()
                        .fill(focused == field ? Theme.gold : Theme.surfaceStroke)
                        .frame(height: 1.5),
                    alignment: .bottom
                )
        }
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .first: focused = .last
        case .last:  focused = .email
        case .email:
            focused = nil
            if canSave { save() }
        }
    }

    // MARK: Data

    private func loadPicked(_ item: PhotosPickerItem?) async {
        defer {
            Task { @MainActor in coordinator.setPresentingSystemModal(false) }
        }
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            await MainActor.run { selectedImage = ui }
        }
    }

    private func save() {
        guard canSave else { return }
        coordinator.userActivity()

        do {
            // Photo is optional. When omitted we store an empty file
            // name; the rest of the app already treats that as "no
            // photo" and falls back to the placeholder avatar.
            let photoFileName: String
            if let image = selectedImage {
                photoFileName = try PhotoStorage.save(image)
            } else {
                photoFileName = ""
            }
            let employee = Employee(
                rfidTag: rfidTag,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                photoFileName: photoFileName,
                profileRole: profileRole
            )
            modelContext.insert(employee)

            // Auto-clock-in for the freshly registered card. A "both"
            // employee defaults to the instructor side because that's the
            // overwhelmingly common case at the studio; the admin can flip
            // the shift role and scheduled-class count from the punch-log
            // editor if this happens to be a coordinator-only shift.
            let initialShiftRole: ShiftRole = profileRole == .coordinator ? .coordinator : .instructor
            let log = PunchLog(
                employee: employee,
                clockInTime: Date(),
                shiftRole: initialShiftRole,
                scheduledClasses: initialShiftRole == .instructor ? 1 : 0,
                actualClassesTaught: 0
            )
            modelContext.insert(log)
            employee.isCurrentlyClockedIn = true

            employee.markDirty()
            log.markDirty()

            try modelContext.save()
            Feedback.success()
            coordinator.go(to: .punchSuccess(name: employee.fullName, didClockIn: true))
        } catch {
            saveError = error.localizedDescription
            Feedback.error()
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), trimmed.contains(".") else { return false }
        return trimmed.count >= 5
    }
}
