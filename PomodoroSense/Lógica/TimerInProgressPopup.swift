import SwiftUI

struct TimerInProgressPopup: View {
    let accentColor: Color
    let dimmedColor: Color
    let backgroundColor: Color

    var title: String = "TIMER IN PROGRESS"
    var message: String = "You already have a session running.\nStarting a new one will discard the current progress."
    var confirmLabel: String = "START NEW"
    var iconName: String = "exclamationmark.triangle.fill"

    let onCancel: () -> Void
    let onStartNew: () -> Void

    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(spacing: 22) {
                iconBadge

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(3)
                        .foregroundColor(accentColor)

                    Text(message)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(dimmedColor)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(dimmedColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(dimmedColor.opacity(0.3), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button(action: onStartNew) {
                        Text(confirmLabel)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundColor(backgroundColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(accentColor)
                            )
                            .shadow(color: accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        }
        .onAppear {
            Haptics.warning()

            #if os(macOS)
            installKeyMonitor()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            removeKeyMonitor()
            #endif
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 72, height: 72)

            Circle()
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
                .frame(width: 72, height: 72)

            Image(systemName: iconName)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(accentColor)
                .shadow(color: accentColor.opacity(0.5), radius: 8, x: 0, y: 0)
        }
    }

    // MARK: - Keyboard (macOS)

    #if os(macOS)
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return event }

            switch event.keyCode {
            case 36, 76:  // Return / Enter
                onStartNew()
                return nil
            case 53:      // Escape
                onCancel()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
    #endif
}
