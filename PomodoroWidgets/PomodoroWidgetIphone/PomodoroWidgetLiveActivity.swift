//
//  PomodoroWidgetLiveActivity.swift
//  PomodoroWidget
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Rango seguro para Text(timerInterval:). `Date()...fecha` CRASHEA si la fecha ya pasó
/// (rango inválido), y eso puede pasar cuando el widget se vuelve a renderizar tras vencer el timer.
private func safeTimerRange(to target: Date) -> ClosedRange<Date> {
    let now = Date()
    return now...max(now, target)
}

/// Color del texto compacto (Dynamic Island compacta/minimal) según fase.
private func compactTint(isBreak: Bool) -> Color {
    isBreak
        ? Color(red: 0.85, green: 0.90, blue: 0.60)
        : Color(red: 0.95, green: 0.77, blue: 0.62)
}

/// Formatea segundos como mm:ss.
private func formatPaused(_ seconds: Int) -> String {
    String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
}

struct TimeRemainingText: View {
    let state: PomodoroAttributes.ContentState

    var body: some View {
        if !state.isRunning, let p = state.pausedSeconds {
            Text(formatPaused(p))
        } else {
            Text(timerInterval: safeTimerRange(to: state.targetDate),
                 countsDown: true,
                 showsHours: false)
        }
    }
}

// MARK: - Panel de Reward

struct SessionRewardPanel: View {
    let reward: SessionRewardPayload
    let theme: PomodoroTheme

    var body: some View {
        VStack(spacing: 10) {
            // ── Header: título + lucky badge ──
            HStack(spacing: 8) {
                Image(systemName: reward.isLucky ? "sparkles" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(reward.isLucky ? Color.yellow : theme.workAccent)

                Text(reward.isLastSession ? "ALL DONE!" : "NICE WORK!")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(reward.isLucky ? Color.yellow : theme.workAccent)

                if reward.isLucky {
                    Text("LUCKY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow))
                }
            }

            // ── Rewards: chips + silver + gold + streak ──
            HStack(spacing: 14) {
                // Bronze
                rewardBadge(amount: reward.bronzeEarned,
                            label: "CHIPS",
                            tint: theme.workAccent)

                // Silver (solo si ganó algo)
                if reward.silverEarned > 0 {
                    rewardBadge(amount: reward.silverEarned,
                                label: "SILVER",
                                tint: CurrencyTier.silver.tintColor)
                }

                // Gold (solo si ganó algo)
                if reward.goldEarned > 0 {
                    rewardBadge(amount: reward.goldEarned,
                                label: "GOLD",
                                tint: CurrencyTier.gold.tintColor)
                }

                // Streak
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(reward.newStreak)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Badge de reward reutilizable

    private func rewardBadge(amount: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("+\(amount)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.5), radius: 4)

            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(tint.opacity(0.7))
        }
    }
}

// MARK: - Widget Live Activity

struct PomodoroWidgetLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            let theme = ThemeManager.getTheme(for: context.state.noiseId)
            let activeColor = context.state.isBreak ? theme.breakAccent : theme.workAccent

            return DynamicIsland {
                // ── LEADING: solo cuando NO hay reward ──
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.reward == nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.isBreak ? "BREAK" : "FOCUS")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(activeColor)

                            if !context.state.isRunning {
                                Text("PAUSED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                            } else {
                                Text("Session \(context.state.currentSession) of \(context.state.totalSessions)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.top, 6)
                        .padding(.leading, 8)
                    }
                }

                // ── TRAILING: solo cuando NO hay reward ──
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.reward == nil {
                        VStack(alignment: .trailing) {
                            TimeRemainingText(state: context.state)
                                .font(.system(size: 24, weight: .medium, design: .monospaced))
                                .foregroundColor(context.state.isRunning ? activeColor : .gray)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                    }
                }

                // ── CENTER: solo cuando HAY reward ──
                // (más espacio que .bottom para el panel completo)
                DynamicIslandExpandedRegion(.center) {
                    if let reward = context.state.reward {
                        SessionRewardPanel(reward: reward, theme: theme)
                            .padding(.horizontal, 12)
                    }
                }

                // ── BOTTOM: dos variantes según estado ──
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.reward == nil {
                        // Controles normales
                        HStack(spacing: 24) {
                            Button(intent: StopTimerIntent()) {
                                Image(systemName: "stop.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.red.opacity(0.2)))
                            }
                            .buttonStyle(.plain)

                            Button(intent: ToggleTimerIntent()) {
                                Image(systemName: context.state.isRunning ? "pause.fill" : "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.black)
                                    .padding(16)
                                    .background(Circle().fill(activeColor))
                            }
                            .buttonStyle(.plain)

                            Button(intent: SkipTimerIntent()) {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    } else {
                        // Cuando hay reward: botón DONE para cerrar la LA explícitamente.
                        Button(intent: DismissRewardIntent()) {
                            Text("DONE")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.yellow)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                if context.state.reward != nil {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.yellow)
                } else {
                    Text(context.state.isBreak ? "B" : "F")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(compactTint(isBreak: context.state.isBreak))
                        .padding(.leading, 4)
                }
            } compactTrailing: {
                if let reward = context.state.reward {
                    Text("+\(reward.totalEarned)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.yellow)
                } else if !context.state.isRunning, let pausedSecs = context.state.pausedSeconds {
                    Text(formatPaused(pausedSecs))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 45)
                } else if context.isStale {
                    Text("--:--")
                        .monospacedDigit()
                        .foregroundColor(.gray)
                        .frame(width: 45)
                } else {
                    TimeRemainingText(state: context.state)
                        .monospacedDigit()
                        .foregroundColor(compactTint(isBreak: context.state.isBreak))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 45)
                }
            } minimal: {
                if context.state.reward != nil {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                } else if !context.state.isRunning {
                    Text("II")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.gray)
                } else if context.isStale {
                    Image(systemName: "checkmark")
                        .foregroundColor(.gray)
                } else {
                    Text(context.state.isBreak ? "B" : "F")
                        .foregroundColor(compactTint(isBreak: context.state.isBreak))
                }
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    func lockScreenView(context: ActivityViewContext<PomodoroAttributes>) -> some View {
        let theme = ThemeManager.getTheme(for: context.state.noiseId)
        let activeColor = context.state.isBreak ? theme.breakAccent : theme.workAccent

        if let reward = context.state.reward {
            VStack(spacing: 0) {
                SessionRewardPanel(reward: reward, theme: theme)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)

                // Botón DONE para cerrar la LA del reward explícitamente.
                Button(intent: DismissRewardIntent()) {
                    Text("DONE")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2)
                        .foregroundColor(theme.workBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(activeColor)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
            .background(theme.workBackground)
        } else {
            timerLockScreen(context: context, theme: theme, activeColor: activeColor)
        }
    }

    @ViewBuilder
    func timerLockScreen(
        context: ActivityViewContext<PomodoroAttributes>,
        theme: PomodoroTheme,
        activeColor: Color
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(headerLabel(context: context))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(headerColor(context: context, activeColor: activeColor))

                        if context.state.isRunning {
                            Text("\(context.state.currentSession)/\(context.state.totalSessions)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(theme.workBackground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(activeColor)
                                .clipShape(Capsule())
                        }
                    }

                    Text(context.attributes.presetName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                TimeRemainingText(state: context.state)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(context.state.isRunning ? .white : .gray)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            // Controles
            HStack(spacing: 35) {
                Button(intent: StopTimerIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(intent: ToggleTimerIntent()) {
                    Image(systemName: context.state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(theme.workBackground)
                        .frame(width: 56, height: 56)
                        .background(activeColor)
                        .clipShape(Circle())
                        .id(context.state.isRunning)
                }
                .buttonStyle(.plain)

                Button(intent: SkipTimerIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)
        }
        .background(theme.workBackground)
    }

    // MARK: - Helpers de lock screen

    func headerLabel(context: ActivityViewContext<PomodoroAttributes>) -> String {
        if !context.state.isRunning { return "PAUSED" }
        return context.state.isBreak ? "BREAK TIME" : "FOCUS TIME"
    }

    func headerColor(
        context: ActivityViewContext<PomodoroAttributes>,
        activeColor: Color
    ) -> Color {
        context.state.isRunning ? activeColor : .gray
    }
}
