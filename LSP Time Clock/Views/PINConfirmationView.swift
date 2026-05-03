import SwiftUI

/// Modal PIN re-prompt used to gate destructive or mutating admin actions
/// (e.g. saving an edit) even after the dashboard has already been
/// unlocked. UI mirrors `AdminPINView` so muscle memory carries over, but
/// it's sized for a sheet and reports its result through callbacks rather
/// than mutating the global app mode.
struct PINConfirmationView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var title: String = "Confirm with PIN"
    var subtitle: String = "Enter the admin PIN to apply changes."
    var onSuccess: () -> Void
    var onCancel: () -> Void

    @State private var entered = ""
    @State private var shake = false

    private let pinLength = 4
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let padButtonSize: CGFloat = isCompact ? min(70, (w - 80) / 3) : 88
            let rowSpacing: CGFloat = isCompact ? 12 : 16

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: isCompact ? 20 : 30) {
                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: isCompact ? 40 : 50, weight: .black))
                            .foregroundStyle(Theme.brandGradient)
                        Text(title)
                            .font(.system(size: isCompact ? 24 : 30, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(subtitle)
                            .font(.system(size: isCompact ? 13 : 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    pinIndicator
                        .offset(x: shake ? -14 : 0)
                        .animation(
                            shake
                                ? .default.repeatCount(3, autoreverses: true).speed(4)
                                : .default,
                            value: shake
                        )

                    pad(buttonSize: padButtonSize, spacing: rowSpacing)

                    Button(role: .cancel) {
                        onCancel()
                    } label: { Text("Cancel") }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 300)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, isCompact ? 20 : 32)
            }
        }
    }

    private var pinIndicator: some View {
        HStack(spacing: isCompact ? 16 : 20) {
            ForEach(0..<pinLength, id: \.self) { i in
                Circle()
                    .fill(
                        i < entered.count
                            ? AnyShapeStyle(Theme.brandGradient)
                            : AnyShapeStyle(Theme.tan.opacity(0.25))
                    )
                    .frame(width: isCompact ? 18 : 22, height: isCompact ? 18 : 22)
            }
        }
    }

    private func pad(buttonSize: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<3) { row in
                HStack(spacing: spacing) {
                    ForEach(1..<4) { col in
                        let digit = row * 3 + col
                        padButton(title: "\(digit)", size: buttonSize) { append("\(digit)") }
                    }
                }
            }
            HStack(spacing: spacing) {
                padButton(title: "", size: buttonSize) {}
                    .opacity(0)
                    .disabled(true)
                padButton(title: "0", size: buttonSize) { append("0") }
                padButton(title: "⌫", size: buttonSize) { backspace() }
            }
        }
        .frame(maxWidth: 360)
    }

    private func padButton(title: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Theme.surface)
                        .overlay(
                            Circle().stroke(Theme.surfaceStroke, lineWidth: 1)
                        )
                        .shadow(color: Theme.tan.opacity(0.15), radius: 8, y: 3)
                )
        }
    }

    private func append(_ ch: String) {
        guard entered.count < pinLength else { return }
        entered += ch
        if entered.count == pinLength { submit() }
    }

    private func backspace() {
        if !entered.isEmpty { entered.removeLast() }
    }

    private func submit() {
        if entered == AppCoordinator.adminPIN {
            Feedback.success()
            onSuccess()
        } else {
            Feedback.error()
            shake.toggle()
            entered = ""
        }
    }
}
