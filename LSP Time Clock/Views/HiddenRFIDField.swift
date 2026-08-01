import SwiftUI
import UIKit

/// Invisible UITextField that captures input from a USB 125KHz RFID reader
/// (which behaves as a HID keyboard). The on-screen virtual keyboard is
/// suppressed by assigning a blank `inputView`, so hardware keystrokes are
/// still routed to the field but no keyboard is drawn.
///
/// Note on focus management: `@FocusState` only binds to SwiftUI's own
/// focus-eligible views (TextField / SecureField). Because we wrap a
/// UIKit field, we expose two SwiftUI-native focus controls instead:
///
/// 1. `isActive` — Bool binding tracking whether the field *should* be
///    focused. Setting it to false explicitly resigns first responder.
/// 2. `refocusGeneration` — bumping counter that forces a resign+become
///    cycle even when `isActive` hasn't changed. Callers bump it from
///    `scenePhase` transitions, foreground-app taps, and `.onAppear`,
///    which is what makes the kiosk recover focus after the iPad has
///    slept overnight (iOS often hands first responder to nothing on
///    foregrounding from `.background`).
struct HiddenRFIDField: UIViewRepresentable {
    @Binding var isActive: Bool
    var refocusGeneration: Int = 0
    var onSubmit: (String) -> Void

    func makeUIView(context: Context) -> KioskTextField {
        let tf = KioskTextField()
        tf.delegate = context.coordinator
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        tf.keyboardType = .asciiCapable
        tf.returnKeyType = .done
        tf.inputView = UIView() // suppress software keyboard
        tf.inputAccessoryView = UIView()
        tf.tintColor = .clear // hide caret
        tf.textColor = .clear
        tf.backgroundColor = .clear
        tf.isAccessibilityElement = false
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingDidEndOnExit(_:)),
            for: .editingDidEndOnExit
        )
        return tf
    }

    func updateUIView(_ uiView: KioskTextField, context: Context) {
        context.coordinator.parent = self

        guard isActive else {
            if uiView.isFirstResponder { uiView.resignFirstResponder() }
            return
        }

        let generationAdvanced = context.coordinator.lastSeenGeneration != refocusGeneration
        context.coordinator.lastSeenGeneration = refocusGeneration

        // Hop the runloop so the responder cycle isn't fighting a SwiftUI
        // layout pass. When the generation has been bumped, force a fresh
        // resign+become — iOS sometimes reports `isFirstResponder == true`
        // while the actual keyboard input pipeline is detached (the
        // overnight-sleep failure mode), and only a clean resign breaks it.
        if generationAdvanced {
            DispatchQueue.main.async {
                if uiView.isFirstResponder { uiView.resignFirstResponder() }
                uiView.becomeFirstResponder()
            }
        } else if !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: HiddenRFIDField
        // Sentinel below any plausible starting value so the first
        // `updateUIView` always treats focus as needing a fresh grant.
        var lastSeenGeneration: Int = .min

        init(_ parent: HiddenRFIDField) { self.parent = parent }

        @objc func editingDidEndOnExit(_ sender: UITextField) {
            submit(sender)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            submit(textField)
            return false
        }

        private func submit(_ textField: UITextField) {
            let raw = (textField.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            textField.text = ""
            guard !raw.isEmpty else {
                if parent.isActive { textField.becomeFirstResponder() }
                return
            }
            parent.onSubmit(raw)
            // Stay focused so the next card can be read without another tap.
            if parent.isActive { textField.becomeFirstResponder() }
        }
    }
}

final class KioskTextField: UITextField {
    override var canBecomeFirstResponder: Bool { true }
    override func caretRect(for position: UITextPosition) -> CGRect { .zero }
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    // Disable all editing menu actions so the field is truly invisible
    // and cannot be interacted with via long-press.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
