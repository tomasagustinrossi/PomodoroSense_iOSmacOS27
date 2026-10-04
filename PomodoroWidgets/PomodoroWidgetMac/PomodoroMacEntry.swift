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

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(phaseLabel)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(activeColor)

                Spacer()

                if !entry.timer.isRunning && entry.timer.targetDate != nil {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                }
            }

            Spacer(minLength: 0)

            timeText
                .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.timer.isRunning ? .white : .gray)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("SESSION \(entry.timer.currentSession) OF \(entry.timer.totalSessions)")
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                chipBadge(amount: entry.economy.bronze, tint: theme.workAccent)
                if entry.economy.streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("\(entry.economy.streak)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(alignment: .center, spacing: 16) {
            // Columna izquierda: fase + tiempo
            VStack(alignment: .leading, spacing: 6) {
                Text(phaseLabel)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(activeColor)

                Spacer(minLength: 0)

                timeText
                    .font(.system(size: 38, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(entry.timer.isRunning ? .white : .gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("SESSION \(entry.timer.currentSession) OF \(entry.timer.totalSessions)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: 0)

                Text(entry.timer.presetName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Separador vertical
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            // Columna derecha: economía
            VStack(alignment: .leading, spacing: 10) {
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
                        .foregroundStyle(.orange)
                    Text("\(entry.economy.streak)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(entry.economy.streak == 1 ? "DAY" : "DAYS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private var phaseLabel: String {
        if !entry.timer.isRunning && entry.timer.targetDate == nil {
            return "IDLE"
        }
        if !entry.timer.isRunning {
            return "PAUSED"
        }
        return entry.timer.isBreak ? "BREAK" : "FOCUS"
    }

    @ViewBuilder
    private var timeText: some View {
        if let paused = entry.timer.pausedSeconds {
            Text(String(format: "%02d:%02d", paused / 60, paused % 60))
        } else if let target = entry.timer.targetDate, target > Date() {
            Text(timerInterval: Date()...target, countsDown: true, showsHours: false)
        } else {
            Text("--:--")
        }
    }

    private func chipBadge(amount: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text("\(amount)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func economyRow(label: String, amount: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text("\(amount)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundStyle(tint.opacity(0.6))
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PomodoroMacWidget()
} timeline: {
    PomodoroMacEntry.placeholder
}