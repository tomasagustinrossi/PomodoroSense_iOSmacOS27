//
//  SessionRewardPopup.swift
//  PomodoroSense
//

import SwiftUI

struct FallingChip: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let size: CGFloat
    let rotation: Double
    let delay: Double
    let duration: Double
    let color: Color
}

struct SessionRewardPopup: View {
    let payload: SessionRewardPayload

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var contentVisible = false

    var body: some View {
        ZStack {
            // Backdrop tenue
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { dismiss() }

            // Card compacto
            VStack(spacing: 12) {
                iconRow
                amountRow
                if payload.silverEarned > 0 || payload.goldEarned > 0 {
                    extraTiersRow
                }
                if payload.newStreak > 0 {
                    streakRow
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                payload.isJackpot
                                    ? Color.yellow.opacity(0.5)
                                    : accentColor.opacity(0.15),
                                lineWidth: payload.isJackpot ? 1.5 : 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 15)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear(perform: animateIn)
    }

    // MARK: - Componentes

    private var iconRow: some View {
        HStack(spacing: 6) {
            if payload.isJackpot {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("JACKPOT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(3)
                    .foregroundColor(.yellow)
            } else if payload.isLucky {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("LUCKY")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(3)
                    .foregroundColor(.yellow)
            } else if payload.newlyUnlockedTier != nil {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(payload.newlyUnlockedTier!.tintColor)
                Text("UNLOCKED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(3)
                    .foregroundColor(payload.newlyUnlockedTier!.tintColor)
            } else {
                Text("SESSION COMPLETE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(3)
                    .foregroundColor(dimmedColor)
            }
        }
        .opacity(contentVisible ? 1 : 0)
    }

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(payload.isJackpot ? .yellow : accentColor)

            Text("+\(payload.bronzeEarned)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(payload.isJackpot ? .yellow : accentColor)
                .shadow(
                    color: payload.isJackpot ? .yellow.opacity(0.5) : .clear,
                    radius: 12
                )

            Text(payload.bronzeEarned == 1 ? "CHIP" : "CHIPS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(dimmedColor)
                .padding(.bottom, 4)
        }
        .scaleEffect(contentVisible ? 1.0 : 0.7)
        .opacity(contentVisible ? 1 : 0)
    }

    private var extraTiersRow: some View {
        HStack(spacing: 10) {
            if payload.silverEarned > 0 {
                tierBadge(amount: payload.silverEarned,
                          label: "SILVER",
                          tint: CurrencyTier.silver.tintColor)
            }
            if payload.goldEarned > 0 {
                tierBadge(amount: payload.goldEarned,
                          label: "CROWN",
                          tint: CurrencyTier.gold.tintColor)
            }
        }
        .opacity(contentVisible ? 1 : 0)
    }

    private func tierBadge(amount: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("+\(amount)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundColor(tint.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.1))
        )
    }

    private var streakRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.orange)
            Text("\(payload.newStreak)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.85))
            Text(payload.newStreak == 1 ? "DAY" : "DAYS")
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundColor(dimmedColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
        )
        .opacity(contentVisible ? 1 : 0)
    }

    // MARK: - Animación

    private func animateIn() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            appeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                contentVisible = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
        }
    }
}

