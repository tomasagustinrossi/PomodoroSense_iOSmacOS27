//
//  PomodoroStatsView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 08/10/2026.
//


import SwiftUI

struct PomodoroStatsView: View {
    @ObservedObject var store: SessionStore = .shared

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color

    var onDismiss: (() -> Void)? = nil

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ZStack {
            backgroundColor

            VStack(spacing: 18) {
                header
                statsStrip
                monthNavigator
                weekdayHeader
                calendarGrid
                legend
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        #if os(macOS)
        .onExitCommand { onDismiss?() }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("STATS")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(dimmedColor)
            Spacer()
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Strip de totales

    private var statsStrip: some View {
        HStack(spacing: 14) {

            statBadge(icon: "flame.fill",
                      value: "\(store.currentStreak)",
                      label: store.currentStreak == 1 ? "DAY" : "DAYS",
                      tint: .orange)
        }
    }

    private func statBadge(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(dimmedColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Navegador de mes

    private var monthNavigator: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundColor(.white)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: visibleMonth).uppercased()
    }

    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
        }
    }
    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
        }
    }

    // MARK: - Días de la semana

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(dimmedColor.opacity(0.7))
                    .frame(height: 14)
            }
        }
    }

    // MARK: - Grilla

    private var calendarGrid: some View {
        let days = daysInMonthGrid()
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days, id: \.self) { day in
                if let day = day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let minutes = store.totalFocusMinutes(on: day)
        let tier = colorTier(for: minutes)
        let hasSessions = minutes > 0
        let isToday = cal.isDateInToday(day)

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tier.fill)

            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(hasSessions ? .white : dimmedColor.opacity(0.55))

            // Rayita inferior si hay sesiones ese día
            if hasSessions {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(tier.border)
                        .frame(width: 12, height: 2)
                        .cornerRadius(1)
                        .padding(.bottom, 4)
                }
            }

            if isToday {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accentColor, lineWidth: 1)
            }
        }
        .frame(height: 34)
    }

    // MARK: - Escala de color

    private struct Tier {
        let fill: Color
        let border: Color
    }

    private func colorTier(for minutes: Int) -> Tier {
        switch minutes {
        case 0:          return Tier(fill: Color.white.opacity(0.03), border: .clear)
        case 1..<60:     return Tier(fill: accentColor.opacity(0.18), border: accentColor.opacity(0.5))
        case 60..<150:   return Tier(fill: accentColor.opacity(0.38), border: accentColor.opacity(0.75))
        case 150..<300:  return Tier(fill: accentColor.opacity(0.65), border: accentColor)
        default:         return Tier(fill: accentColor,            border: .white.opacity(0.9))
        }
    }

    // MARK: - Leyenda

    private var legend: some View {
        HStack(spacing: 6) {
            Text("LESS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(dimmedColor.opacity(0.7))

            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity([0.18, 0.38, 0.65, 1.0][i]))
                    .frame(width: 12, height: 12)
            }

            Text("MORE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(dimmedColor.opacity(0.7))
        }
    }

    // MARK: - Cálculo de días

    private func daysInMonthGrid() -> [Date?] {
        guard let monthInterval = cal.dateInterval(of: .month, for: visibleMonth),
              let firstWeekday = cal.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }

        let days = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        // weekday: 1 = domingo en calendario gregoriano; queremos S=domingo
        let leading = firstWeekday - 1

        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days {
            if let d = cal.date(byAdding: .day, value: offset, to: monthInterval.start) {
                result.append(d)
            }
        }
        // Rellenar hasta múltiplo de 7
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }
}
