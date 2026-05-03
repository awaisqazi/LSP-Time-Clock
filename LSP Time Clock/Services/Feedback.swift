import Foundation
import UIKit
import AudioToolbox

enum Feedback {
    static func cardRecognized() {
        AudioServicesPlaySystemSound(1104) // key click tick
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        AudioServicesPlaySystemSound(1057) // Tink / short positive chime
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        AudioServicesPlaySystemSound(1073)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        AudioServicesPlaySystemSound(1073)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
