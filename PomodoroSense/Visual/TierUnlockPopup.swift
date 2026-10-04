import SwiftUI

struct TierUnlockPopup: View {
    let tier: CurrencyTier

    var backgroundColor: Color
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var ringExpanded = false
    @State private var sparklesVisible = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.55).ignoresSafeArea())
                .opacity(appeared ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            ZStack {
                // Anillos expansivos de fondo
                Circle()
                    .stroke(tier.tintColor.opacity(0.4), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .scaleEffect(ringExpanded ? 1.6 : 0.8)
                    .opacity(ringExpanded ? 0 : 0.9)

                Circle()
                    .stroke(tier.tintColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .scaleEffect(ringExpanded ? 2.2 : 0.8)
                    .opacity(ringExpanded ? 0 : 0.6)

                // Contenido
                VStack(spacing: 22) {
                    iconBadge
                    headline
                    tierName
                    descriptionText
                    continueButton
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(tier.tintColor.opacity(0.5), lineWidth: 1.5)
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 20)
                .shadow(color: tier.tintColor.opacity(0.5), radius: 40, x: 0, y: 0)
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear(perform: animateIn)
    }

    // MARK: - Componentes

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tier.tintColor.opacity(0.35),
                            tier.tintColor.opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            Circle()
                .stroke(tier.tintColor.opacity(0.8), lineWidth: 2)
                .frame(width: 100, height: 100)

            Image(systemName: tier.iconName)
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(tier.tintColor)
                .shadow(color: tier.tintColor.opacity(0.9), radius: 20)
        }
    }

    private var headline: some View {
        Text(tier.unlockHeadline)
            .font(.system(size: 12, weight: .heavy))
            .tracking(5)
            .foregroundColor(tier.tintColor)
            .shadow(color: tier.tintColor.opacity(0.6), radius: 8)
    }

    private var tierName: some View {
        Text(tier.displayName)
            .font(.system(size: 44, weight: .black, design: .rounded))
            .tracking(8)
            .foregroundColor(.white)
            .shadow(color: tier.tintColor.opacity(0.8), radius: 16)
            .scaleEffect(sparklesVisible ? 1.0 : 0.85)
            .opacity(sparklesVisible ? 1 : 0)
    }

    private var descriptionText: some View {
        Text(descriptionForTier)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .foregroundColor(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }

    private var descriptionForTier: String {
        switch tier {
        case .bronze: return ""
        case .silver: return "You've unlocked a new currency.\nLonger streaks now earn Silver on top of Chips."
        case .gold:   return "The final tier.\nGold only accumulates at the highest levels of consistency."
        }
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
                    RoundedRectangle(cornerRadius: 12).fill(tier.tintColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.top, 4)
    }

    // MARK: - Animación

    private func animateIn() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            appeared = true
        }

        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            ringExpanded = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                sparklesVisible = true
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