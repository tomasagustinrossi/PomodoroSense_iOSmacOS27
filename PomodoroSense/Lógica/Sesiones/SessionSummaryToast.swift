import SwiftUI

struct SessionSummaryToast: View {
    let chipsEarned: Int
    let newStreak: Int

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var dismissTask: Task<Void, Never>?

    private var chipsText: String {
        chipsEarned > 0 ? "+\(chipsEarned)" : "\(chipsEarned)"
    }

    private var chipsColor: Color {
        if chipsEarned < 0 { return .red }
        return accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            // Chips
            HStack(spacing: 4) {
                Text(chipsText)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(chipsColor)
                    .contentTransition(.numericText())

                Text(chipsEarned == 1 || chipsEarned == -1 ? "CHIP" : "CHIPS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor)
            }

            // Separador
            Rectangle()
                .fill(dimmedColor.opacity(0.3))
                .frame(width: 1, height: 14)

            // Racha
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)

                Text("\(newStreak)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text(newStreak == 1 ? "DAY" : "DAYS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor)
            }

            // X
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(dimmedColor)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(backgroundColor.opacity(0.95))
                .overlay(
                    Capsule().stroke(chipsColor.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear(perform: animateIn)
        .onDisappear { dismissTask?.cancel() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            appeared = true
        }

        // Auto-dismiss a los 5s
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}