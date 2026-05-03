import SwiftUI
import SwiftData
import PhotosUI

/// Sheet presented from `EmployeeDetailView` for editing an existing
/// instructor's name, email, and profile photo. Saving requires re-entry
/// of the admin PIN — the dashboard is already unlocked, but mutating an
/// existing record is still treated as a privileged action.
///
/// RFID assignment is intentionally NOT exposed here; the "Replace Lost
/// Card" flow on the detail view handles that with its own fee-collection
/// confirmation.
struct EmployeeEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let employee: Employee

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""

    /// Set only when the admin picks a new image; nil means "keep the
    /// employee's existing photo". This lets us avoid rewriting the photo
    /// file on every save and avoid a flaky "is the displayed image the
    /// stored one or a fresh pick?" check.
    @State private var newImage: UIImage?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false

    @State private var askingPIN = false
    @State private var saveError: String?

    @FocusState private var focused: Field?

    enum Field: Hashable { case first, last, email }

    private var isCompact: Bool { hSizeClass == .compact }

    private var trimmedFirst: String { firstName.trimmingCharacters(in: .whitespaces) }
    private var trimmedLast: String { lastName.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    private var canSave: Bool {
        !trimmedFirst.isEmpty &&
        !trimmedLast.isEmpty &&
        isValidEmail(trimmedEmail) &&
        hasChanges
    }

    private var hasChanges: Bool {
        trimmedFirst != employee.firstName ||
        trimmedLast != employee.lastName ||
        trimmedEmail != employee.email ||
        newImage != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: isCompact ? 18 : 24) {
                        photoSection

                        VStack(spacing: isCompact ? 12 : 16) {
                            textField("First name", text: $firstName, field: .first)
                            textField("Last name", text: $lastName, field: .last)
                            textField("Email", text: $email, field: .email, keyboard: .emailAddress)
                        }
                        .card()

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
            .navigationTitle("Edit Instructor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focused = nil
                        askingPIN = true
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            firstName = employee.firstName
            lastName = employee.lastName
            email = employee.email
        }
        .onChange(of: pickedItem) { _, newItem in
            Task { await loadPicked(newItem) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { img in
                    newImage = img
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
        .sheet(isPresented: $askingPIN) {
            PINConfirmationView(
                title: "Confirm Edits",
                subtitle: "Enter the admin PIN to save changes for \(employee.fullName).",
                onSuccess: {
                    askingPIN = false
                    commitSave()
                },
                onCancel: {
                    askingPIN = false
                }
            )
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        let size: CGFloat = isCompact ? 140 : 170

        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Theme.surfaceStroke, lineWidth: 1)
                    )
                    .frame(width: size, height: size)

                if let displayed = displayedImage {
                    Image(uiImage: displayed)
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

    private var displayedImage: UIImage? {
        if let newImage { return newImage }
        return PhotoStorage.load(fileName: employee.photoFileName)
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
        case .email: focused = nil
        }
    }

    // MARK: - Save flow

    private func loadPicked(_ item: PhotosPickerItem?) async {
        defer {
            Task { @MainActor in coordinator.setPresentingSystemModal(false) }
        }
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            await MainActor.run { newImage = ui }
        }
    }

    private func commitSave() {
        guard canSave else { return }

        // Detect email collisions with another instructor (model doesn't
        // enforce uniqueness on email, so we have to check ourselves).
        if trimmedEmail != employee.email,
           let conflict = findEmployee(byEmail: trimmedEmail),
           conflict.id != employee.id {
            saveError = "Another instructor already uses \(trimmedEmail)."
            Feedback.error()
            return
        }

        do {
            // Apply the photo first so we can roll back the file on failure.
            var newPhotoFileName: String?
            if let image = newImage {
                newPhotoFileName = try PhotoStorage.save(image)
            }

            let oldPhoto = employee.photoFileName
            employee.firstName = trimmedFirst
            employee.lastName = trimmedLast
            employee.email = trimmedEmail
            if let newPhotoFileName {
                employee.photoFileName = newPhotoFileName
            }

            try modelContext.save()

            // Once SwiftData has the new value committed, prune the orphan.
            if let newPhotoFileName, !oldPhoto.isEmpty, oldPhoto != newPhotoFileName {
                PhotoStorage.delete(fileName: oldPhoto)
            }

            Feedback.success()
            coordinator.showToast("Changes saved.", style: .success)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            Feedback.error()
        }
    }

    private func findEmployee(byEmail email: String) -> Employee? {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.email == email }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), trimmed.contains(".") else { return false }
        return trimmed.count >= 5
    }
}
