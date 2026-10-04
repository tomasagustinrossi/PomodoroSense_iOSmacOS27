//
//  MonthlyReport.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 13/10/2026.
//


//
//  MonthlyReport.swift
//  PomodoroSense
//
//  Resumen agregado de un mes completo. Los records individuales se borran
//  después de generar el reporte para mantener la app liviana.
//

import Foundation

struct MonthlyReport: Codable, Identifiable, Hashable {

    /// ID estable: `YYYY-MM`. Evita duplicados si dos threads generan a la vez.
    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    let year: Int
    let month: Int

    // MARK: - Totales

    var totalFocusMinutes: Int
    var totalSessionsCompleted: Int
    var totalSessionsSkipped: Int
    var totalSessionsInterrupted: Int

    // MARK: - Chips ganados

    var bronzeEarned: Int
    var silverEarned: Int
    var goldEarned: Int

    // MARK: - Racha

    /// Racha más larga registrada dentro del mes.
    var longestStreakInMonth: Int

    // MARK: - Días activos

    /// Días del mes (1-31) con al menos un record.
    var activeDays: Set<Int>

    // MARK: - Helpers

    var totalSessions: Int {
        totalSessionsCompleted + totalSessionsSkipped + totalSessionsInterrupted
    }

    var totalChips: Int {
        bronzeEarned + silverEarned + goldEarned
    }

    /// Etiqueta legible: "JANUARY 2025" / "ENERO 2025".
    var displayTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        return fmt.string(from: date).uppercased()
    }
}