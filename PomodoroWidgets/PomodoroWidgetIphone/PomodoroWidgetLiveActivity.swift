//
//  PomodoroWidgetLiveActivity.swift
//  PomodoroWidget
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Helpers

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

/// Color de acento según la fase actual (trabajo / descanso).
private func accentColor(for state: PomodoroAttributes.ContentState, theme: PomodoroTheme) -> Color {
    state.isBreak ? theme.breakAccent : theme.workAccent
}

/// Formatea segundos como mm:ss (o hh:mm:ss si hay al menos una hora).
private func formatPaused(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%02ld:%02ld:%02ld", h, m, s)
    }
    return String(format: "%02ld:%02ld", m, s)
}

// MARK: - Texto de tiempo

struct TimeRemainingText: View {
    let state: PomodoroAttributes.ContentState

    var body: some View {
        Group {
            if !state.isRunning, state.isFreeMode {
                // Free Mode en pausa: SIEMPRE texto congelado. Si no hubiera pausedSeconds
                // caería en el Text(timerInterval:) de abajo y seguiría contando solo.
                Text(formatPaused(state.pausedSeconds ?? 0))
            } else if !state.isRunning, let p = state.pausedSeconds {
                // En pausa, mostramos el tiempo congelado con formato correcto
                Text(formatPaused(p))
            } else if state.isFreeMode {
                // Free Mode corriendo: cuenta hacia adelante desde el inicio real
                // (targetDate - freeModeSpan), no desde "ahora", así al reanudar no vuelve a 0.
                let start = state.targetDate.addingTimeInterval(-PomodoroLiveActivity.freeModeSpan)
                Text(timerInterval: start...state.targetDate, countsDown: false, showsHours: true)
            } else {
                // Pomodoro corriendo: cuenta hacia atrás
                Text(timerInterval: safeTimerRange(to: state.targetDate),
                     countsDown: true,
                     showsHours: false)
            }
        }
        // CLAVE: Fuerza a SwiftUI a destruir y recrear la vista de texto cuando
        // cambia de estado (corriendo a pausado y viceversa). Sin esto,
        // Text(timerInterval:) ignora las actualizaciones.
        .id("\(state.isRunning)-\(state.isFreeMode)-\(state.isBreak)-\(state.pausedSeconds ?? 0)-\(state.targetDate.timeIntervalSince1970)")
    }
}

// MARK: - Botones reutilizables

/// Botón circular chico (44×44) de la lock screen y de la isla expandida (stop, skip).
private struct CircleSecondaryButton<I: AppIntent>: View {
    let intent: I
    let systemName: String

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Botón play/pause grande (56×56) de la lock screen.
private struct LockScreenPlayPauseButton<I: AppIntent>: View {
    let intent: I
    let isRunning: Bool
    let theme: PomodoroTheme
    let activeColor: Color

    var body: some View {
        Button(intent: intent) {
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(theme.workBackground)
                .frame(width: 56, height: 56)
                .background(activeColor)
                .clipShape(Circle())
                .id(isRunning)
        }
        .buttonStyle(.plain)
    }
}

/// Botón stop (rojo translúcido) de la Dynamic Island expandida.
private struct IslandStopButton<I: AppIntent>: View {
    let intent: I

    var body: some View {
        Button(intent: intent) {
            Image(systemName: "stop.fill")
                .font(.title3)
                .foregroundColor(.white)
                .padding(12)
                .background(Circle().fill(Color.red.opacity(0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Botón play/pause de la Dynamic Island expandida.
private struct IslandPlayPauseButton<I: AppIntent>: View {
    let intent: I
    let isRunning: Bool
    let activeColor: Color

    var body: some View {
        Button(intent: intent) {
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(.black)
                .contentTransition(.symbolEffect(.replace))
                .padding(16)
                .background(Circle().fill(activeColor))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Reloj grande del header de la lock screen.
private struct LockScreenClock: View {
    let state: PomodoroAttributes.ContentState

    var body: some View {
        TimeRemainingText(state: state)
            .font(.system(size: 34, weight: .light, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .foregroundColor(state.isRunning ? .white : .gray)
    }
}

// MARK: - Panel de Reward

struct SessionRewardPanel: View {
    let reward: SessionRewardPayload
    let theme: PomodoroTheme

    /// `true` cuando la sesión terminó pero no dio chips. En ese caso
    /// mostramos un panel gris minimalista en vez del dorado de rewards.
    private var isCompletionOnly: Bool {
        reward.totalEarned == 0 && reward.newlyUnlockedTier == nil
    }

    var body: some View {
        if isCompletionOnly {
            completionView
        } else {
            rewardView
        }
    }

    // MARK: Variante minimalista (sin chips)

    private var completionView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            Text("COMPLETED")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }

    // MARK: Variante con chips (dorada)

    private var rewardView: some View {
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
                rewardBadge(amount: reward.bronzeEarned,
                            label: "CHIPS",
                            tint: theme.workAccent)

                if reward.silverEarned > 0 {
                    rewardBadge(amount: reward.silverEarned,
                                label: "SILVER",
                                tint: CurrencyTier.silver.tintColor)
                }

                if reward.goldEarned > 0 {
                    rewardBadge(amount: reward.goldEarned,
                                label: "GOLD",
                                tint: CurrencyTier.gold.tintColor)
                }

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

    // MARK: Badge de reward reutilizable

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
            makeDynamicIsland(context: context)
        }
    }

    // MARK: - Dynamic Island

    private func makeDynamicIsland(context: ActivityViewContext<PomodoroAttributes>) -> DynamicIsland {
        let theme = ThemeManager.getTheme(for: context.state.noiseId)
        let activeColor = accentColor(for: context.state, theme: theme)

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                expandedLeading(context: context, activeColor: activeColor)
            }
            DynamicIslandExpandedRegion(.trailing) {
                expandedTrailing(context: context, activeColor: activeColor)
            }
            DynamicIslandExpandedRegion(.center) {
                expandedCenter(context: context, theme: theme)
            }
            DynamicIslandExpandedRegion(.bottom) {
                expandedBottom(context: context, activeColor: activeColor)
            }
        } compactLeading: {
            compactLeadingView(context: context, activeColor: activeColor)
        } compactTrailing: {
            compactTrailingView(context: context, activeColor: activeColor)
        } minimal: {
            minimalView(context: context, activeColor: activeColor)
        }
    }

    // MARK: Regiones expandidas

    /// LEADING: Free Mode o estado normal.
    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode {
            VStack(alignment: .leading, spacing: 2) {
                Text("FREE MODE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(activeColor)

                if !context.state.isRunning {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 8)
        } else if context.state.reward == nil {
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

    /// TRAILING: tiempo.
    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode || context.state.reward == nil {
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

    /// CENTER: panel de reward.
    @ViewBuilder
    private func expandedCenter(context: ActivityViewContext<PomodoroAttributes>, theme: PomodoroTheme) -> some View {
        if !context.state.isFreeMode, let reward = context.state.reward {
            SessionRewardPanel(reward: reward, theme: theme)
        }
    }

    /// BOTTOM: controles (Free Mode / Pomodoro / reward).
    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode {
            HStack(spacing: 24) {
                IslandStopButton(intent: StopFreeModeIntent())
                IslandPlayPauseButton(intent: PauseFreeModeIntent(),
                                      isRunning: context.state.isRunning,
                                      activeColor: activeColor)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        } else if context.state.reward == nil {
            HStack(spacing: 24) {
                IslandStopButton(intent: StopTimerIntent())
                IslandPlayPauseButton(intent: ToggleTimerIntent(),
                                      isRunning: context.state.isRunning,
                                      activeColor: activeColor)
                CircleSecondaryButton(intent: SkipTimerIntent(), systemName: "forward.end.fill")
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        } else {
            Button(intent: DismissRewardIntent()) {
                Text("DONE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.yellow)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: Compacta y minimal

    @ViewBuilder
    private func compactLeadingView(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode {
            Image(systemName: "infinity")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(activeColor)
                .padding(.leading, 4)
        } else if context.state.reward != nil {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.yellow)
        } else {
            Text(context.state.isBreak ? "B" : "F")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(compactTint(isBreak: context.state.isBreak))
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func compactTrailingView(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode {
            TimeRemainingText(state: context.state)
                .monospacedDigit()
                .foregroundColor(activeColor)
                .multilineTextAlignment(.trailing)
                .frame(width: 45)
        } else if let reward = context.state.reward {
            if reward.totalEarned > 0 {
                Text("+\(reward.totalEarned)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.gray)
            }
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
    }

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<PomodoroAttributes>, activeColor: Color) -> some View {
        if context.state.isFreeMode {
            Image(systemName: "infinity")
                .foregroundColor(activeColor)
        } else if context.state.reward != nil {
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

    // MARK: - Lock Screen

    @ViewBuilder
    func lockScreenView(context: ActivityViewContext<PomodoroAttributes>) -> some View {
        let theme = ThemeManager.getTheme(for: context.state.noiseId)
        let activeColor = accentColor(for: context.state, theme: theme)

        if context.state.isFreeMode {
            freeModeLockScreen(context: context, theme: theme, activeColor: activeColor)
        } else if let reward = context.state.reward {
            rewardLockScreen(reward: reward, theme: theme)
        } else {
            timerLockScreen(context: context, theme: theme, activeColor: activeColor)
        }
    }

    @ViewBuilder
    func rewardLockScreen(reward: SessionRewardPayload, theme: PomodoroTheme) -> some View {
        VStack(spacing: 0) {
            SessionRewardPanel(reward: reward, theme: theme)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)

            Button(intent: DismissRewardIntent()) {
                Text("DONE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 60)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(theme.workBackground)
    }

    @ViewBuilder
    func freeModeLockScreen(
        context: ActivityViewContext<PomodoroAttributes>,
        theme: PomodoroTheme,
        activeColor: Color
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("FREE MODE")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(activeColor)

                        if !context.state.isRunning {
                            Text("PAUSED")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.gray)
                        }
                    }
                }

                Spacer()

                LockScreenClock(state: context.state)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(spacing: 35) {
                CircleSecondaryButton(intent: StopFreeModeIntent(), systemName: "stop.fill")

                LockScreenPlayPauseButton(intent: PauseFreeModeIntent(),
                                          isRunning: context.state.isRunning,
                                          theme: theme,
                                          activeColor: activeColor)
            }
            .padding(.bottom, 22)
        }
        .background(theme.workBackground)
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

                LockScreenClock(state: context.state)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(spacing: 35) {
                CircleSecondaryButton(intent: StopTimerIntent(), systemName: "stop.fill")

                LockScreenPlayPauseButton(intent: ToggleTimerIntent(),
                                          isRunning: context.state.isRunning,
                                          theme: theme,
                                          activeColor: activeColor)

                CircleSecondaryButton(intent: SkipTimerIntent(), systemName: "forward.end.fill")
            }
            .padding(.bottom, 22)
        }
        .background(theme.workBackground)
    }

    // MARK: Helpers de lock screen

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
