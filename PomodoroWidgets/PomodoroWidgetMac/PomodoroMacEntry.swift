//
//  PomodoroMacEntry.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  PomodoroMacWidget.swift
//  PomodoroMacWidget
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct PomodoroMacEntry: TimelineEntry {
    let date: Date
    let timer: WidgetTimerState
    let economy: WidgetEconomyState

    static let placeholder = PomodoroMacEntry(
        date: Date(),
        timer: WidgetTimerState(
            isRunning: true,
            isBreak: false,
            currentSession: 2,
            totalSessions: 5,
            targetDate: Date().addingTimeInterval(15 * 60),
            pausedSeconds: nil,
            noiseId: 1,
            presetName: "MORNING CODING"
        ),
        economy: WidgetEconomyState(
            bronze: 1234,
            silver: 45,
            gold: 7,
            streak: 12,
            hasRecordsToday: true
        )
    )
}

// MARK: - Provider

struct PomodoroMacProvider: TimelineProvider {

    func placeholder(in context: Context) -> PomodoroMacEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PomodoroMacEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PomodoroMacEntry>) -> Void) {
        let entry = loadEntry()
        // Refresco de respaldo: pedimos nueva timeline en 15 min.
        // La app fuerza reload en transiciones reales (fase, pause, reset).
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> PomodoroMacEntry {
        PomodoroMacEntry(
            date: Date(),
            timer: WidgetShared.readTimerState(),
            economy: WidgetShared.readEconomyState()
        )
    }
}

// MARK: - Widget

struct PomodoroMacWidget: Widget {
    let kind: String = "PomodoroMacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PomodoroMacProvider()) { entry in
            PomodoroMacWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.11, green: 0.12, blue: 0.13)
                }
        }
        .configurationDisplayName("PomodoroSense")
        .description("Your focus session, chips and streak at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Vista

struct PomodoroMacWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PomodoroMacEntry

    private var theme: PomodoroTheme {
        ThemeManager.getTheme(for: entry.timer.noiseId)
    }

    private var activeColor: Color {
        entry.timer.isBreak ? theme.breakAccent : theme.workAccent
    }

    private var background: Color {
        entry.timer.isBreak ? theme.breakBackground : theme.workBackground
    }

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // MARK: - Small: anillo grande + timer + fase

    private var smallView: some View {
        VStack(spacing: 8) {
            ZStack {
                // Anillo base
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)

                // Anillo de progreso con cuenta atrás automática.
                // `ProgressView(timerInterval:)` se auto-actualiza aunque
                // el widget no reciba reload: mantiene el conteo en vivo.
                if let target = entry.timer.targetDate, target > Date() {
                    ProgressView(timerInterval: Date()...target, countsDown: true, label: { EmptyView() })
                        .progressViewStyle(.circular)
                        .tint(activeColor)
                        .labelsHidden()
                        .scaleEffect(1.6)
                } else {
                    // Pausado o idle: anillo estático.
                    Circle()
                        .trim(from: 0, to: 1.0)
                        .stroke(activeColor.opacity(0.4),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                // Contenido central
                VStack(spacing: 2) {
                    Text(phaseLabel)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(activeColor)

                    Text(timerText)
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(entry.timer.isRunning ? .white : .gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 90, height: 90)

            // Sesión + streak al pie
            HStack(spacing: 10) {
                Text("\(entry.timer.currentSession)/\(entry.timer.totalSessions)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.7))

                if entry.economy.streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                        Text("\(entry.economy.streak)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
        .padding(10)
    }

    // MARK: - Medium: anillo + timer a la izquierda, economía a la derecha

    private var mediumView: some View {
        HStack(spacing: 18) {
            // ── Columna izquierda: timer circular ──
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)

                if let target = entry.timer.targetDate, target > Date() {
                    ProgressView(timerInterval: Date()...target, countsDown: true, label: { EmptyView() })
                        .progressViewStyle(.circular)
                        .tint(activeColor)
                        .labelsHidden()
                        .scaleEffect(2.0)
                } else {
                    Circle()
                        .trim(from: 0, to: 1.0)
                        .stroke(activeColor.opacity(0.4),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 3) {
                    Text(phaseLabel)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(activeColor)

                    Text(timerText)
                        .font(.system(size: 26, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(entry.timer.isRunning ? .white : .gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 110, height: 110)

            // ── Columna derecha: info + economía ──
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.timer.presetName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.55))

                Text("SESSION \(entry.timer.currentSession) OF \(entry.timer.totalSessions)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(activeColor)

                Spacer(minLength: 0)

                economyRow(label: "CHIPS",  amount: entry.economy.bronze, tint: theme.workAccent)

                if entry.economy.silver > 0 {
                    economyRow(label: "SILVER", amount: entry.economy.silver, tint: CurrencyTier.silver.tintColor)
                }
                if entry.economy.gold > 0 {
                    economyRow(label: "GOLD",   amount: entry.economy.gold,   tint: CurrencyTier.gold.tintColor)
                }

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(entry.economy.streak)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.85))
                    Text(entry.economy.streak == 1 ? "DAY" : "DAYS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    // MARK: - Helpers

    private var phaseLabel: String {
        if !entry.timer.isRunning && entry.timer.targetDate == nil { return "IDLE" }
        if !entry.timer.isRunning { return "PAUSED" }
        return entry.timer.isBreak ? "BREAK" : "FOCUS"
    }

    /// Texto del timer. Si corre, `ProgressView` ya muestra el conteo, pero
    /// igual ponemos un placeholder con la duración total para dar contexto.
    /// Si pausa, mostramos el valor pausado.
    private var timerText: String {
        if let paused = entry.timer.pausedSeconds {
            return String(format: "%02d:%02d", paused / 60, paused % 60)
        }
        if let target = entry.timer.targetDate, target > Date() {
            // Si está corriendo, el anillo ya muestra el conteo. Mostramos
            // un "--:--" para no duplicar el número (que se vería raro por
            // la diferencia de refresco entre el anillo y el Text).
            return "--:--"
        }
        return "--:--"
    }

    private func economyRow(label: String, amount: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tint)
            Text("\(amount)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundColor(tint.opacity(0.6))
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PomodoroMacWidget()
} timeline: {
    PomodoroMacEntry.placeholder
}
