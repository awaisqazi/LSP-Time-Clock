import SwiftUI
import UIKit

/// Invisible UITextField that captures input from a USB 125KHz RFID reader
/// (which behaves as a HID keyboard). The on-screen virtual keyboard is
/// suppressed by assigning a blank `inputView`, so hardware keystrokes are
/// still routed to the field but no keyboard is drawn.
struct HiddenRFIDField: UIViewRepresentable {
    @Binding var isActive: Bool
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
        if isActive {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: HiddenRFIDField
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
                // Re-focus so a follow-up scan still lands here.
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
