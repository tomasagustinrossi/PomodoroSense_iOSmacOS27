import SwiftUI

struct SessionRewardPopup: View {
    let payload: SessionRewardPayload

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var chipsAnimated = false
    @State private var luckyAnimated = false

    var body: some View {
        ZStack {
            // Backdrop
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .opacity(appeared ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // Card
            VStack(spacing: 22) {
                iconBadge
                headerRow
                chipsDisplay
                streakRow
                continueButton
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                payload.isLucky
                                    ? Color.yellow.opacity(0.4)
                                    : accentColor.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
            .shadow(
                color: payload.isLucky ? .yellow.opacity(0.25) : .clear,
                radius: 30, x: 0, y: 0
            )
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear(perform: animateIn)
    }

    // MARK: - Componentes

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 90, height: 90)

            Circle()
                .stroke(
                    payload.isLucky
                        ? Color.yellow.opacity(0.5)
                        : accentColor.opacity(0.35),
                    lineWidth: 1.5
                )
                .frame(width: 90, height: 90)

            CasinoChipView(size: 54, tint: accentColor)
                .scaleEffect(chipsAnimated ? 1.0 : 0.4)
                .rotationEffect(.degrees(chipsAnimated ? 0 : -180))
                .opacity(chipsAnimated ? 1 : 0)
        }
    }

    private var headerRow: some View {
        VStack(spacing: 6) {
            Text(payload.isLastSession ? "ALL SESSIONS COMPLETE" : "SESSION COMPLETE")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundColor(dimmedColor)

            if payload.isLucky {
                Text("LUCKY!")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(4)
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.7), radius: 10)
                    .scaleEffect(luckyAnimated ? 1.0 : 0.6)
                    .opacity(luckyAnimated ? 1 : 0)
            }
        }
    }

    private var chipsDisplay: some View {
        VStack(spacing: 2) {
            Text("+\(payload.chipsEarned)")
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(accentColor)
                .scaleEffect(chipsAnimated ? 1.0 : 0.4)
                .opacity(chipsAnimated ? 1 : 0)

            Text(payload.chipsEarned == 1 ? "CHIP" : "CHIPS")
                .font(.system(size: 11, weight: .bold))
                .tracking(4)
                .foregroundColor(dimmedColor)
                .opacity(chipsAnimated ? 1 : 0)
        }
    }

    private var streakRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.orange)
                .shadow(color: .orange.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(payload.newStreak)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text(payload.newStreak == 1 ? "DAY STREAK" : "DAYS STREAK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(payload.totalChipsToday)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(dimmedColor)

                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .opacity(chipsAnimated ? 1 : 0)
    }

    private var continueButton: some View {
        Button(action: dismiss) {
            Text("CONTINUE")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundColor(backgroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(accentColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(chipsAnimated ? 1 : 0)
    }

    // MARK: - Animación

    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            appeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                chipsAnimated = true
            }
        }
        if payload.isLucky {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    luckyAnimated = true
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}