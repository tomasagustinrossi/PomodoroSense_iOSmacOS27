//
//  CalendarColorTier.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 13/10/2026.
//


//
//  CalendarColorCalculator.swift
//  PomodoroSense
//
//  Calcula el tier de color (1-5) para cada día del calendario.
//
//  Modo dinámico: percentiles de los últimos 30 días. Se auto-calibra
//  al ritmo del usuario.
//  Modo fallback: umbrales absolutos cuando hay pocos datos.
//

import Foundation

// MARK: - Tier

enum CalendarColorTier: Equatable, Comparable {
    case empty       // sin records
    case noFocus     // con records pero sin focus completado (todos skip/interrupt)
    case level1
    case level2
    case level3
    case level4
    case level5

    /// Orden interno para comparaciones. Cuanto más alto, "mejor" el día.
    private var sortOrder: Int {
        switch self {
        case .empty:   return 0
        case .noFocus: return 1
        case .level1:  return 2
        case .level2:  return 3
        case .level3:  return 4
        case .level4:  return 5
        case .level5:  return 6
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
// MARK: - Thresholds

struct CalendarColorThresholds: Equatable {
    let p25: Int
    let p50: Int
    let p75: Int
    let p90: Int

    static let fallback = CalendarColorThresholds(
        p25: 99,
        p50: 249,
        p75: 499,
        p90: 999
    )
}

// MARK: - Calculator

enum CalendarColorCalculator {

    /// Mínimo de días con actividad para activar el modo dinámico.
    static let minDaysForDynamic = 7

    /// Ventana de días para calcular percentiles (excluye hoy).
    static let windowDays = 30

    /// Calcula los thresholds según la ventana reciente.
    /// Si hay pocos días con actividad → fallback absoluto.
    static func calculateThresholds(from recentScores: [Int]) -> CalendarColorThresholds {
        let nonZero = recentScores.filter { $0 > 0 }
        guard nonZero.count >= minDaysForDynamic else {
            return .fallback
        }

        let sorted = nonZero.sorted()
        return CalendarColorThresholds(
            p25: percentile(sorted, 0.25),
            p50: percentile(sorted, 0.50),
            p75: percentile(sorted, 0.75),
            p90: percentile(sorted, 0.90)
        )
    }

    /// Devuelve el tier para un score, dado un set de thresholds.
    /// El caller decide si el día tiene actividad (con records) o no.
    static func tier(for score: Int, thresholds: CalendarColorThresholds) -> CalendarColorTier {
        guard score > 0 else { return .noFocus }
        if score <= thresholds.p25 { return .level1 }
        if score <= thresholds.p50 { return .level2 }
        if score <= thresholds.p75 { return .level3 }
        if score <= thresholds.p90 { return .level4 }
        return .level5
    }

    // MARK: - Helpers

    private static func percentile(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int(Double(sorted.count) * p)
        let clamped = min(max(idx, 0), sorted.count - 1)
        return sorted[clamped]
    }
}
