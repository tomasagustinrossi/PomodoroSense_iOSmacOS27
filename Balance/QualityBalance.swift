//
//  QualityBalance.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  QualityBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: SessionQuality, ScoreCalculator.
//     La UI NUNCA accede directo.
//
//  Sistema de calidad de sesión (0–5) y bonus de chips por calidad.
//

import Foundation

nonisolated enum QualityBalance {

    // MARK: - Cortes de duración (minutos)

    /// Cortes que definen la calidad de una sesión según su duración.
    /// Formato: (minutosMínimos, calidad).
    ///
    /// Reglas:
    ///   - < 15 min            → calidad 0 (no cuenta)
    ///   - 15–29 min           → calidad 1 (MINIMAL)
    ///   - 30–44 min           → calidad 2 (SHORT)
    ///   - 45–59 min           → calidad 3 (STANDARD)
    ///   - 60–89 min           → calidad 4 (DEEP)
    ///   - 90+ min             → calidad 5 (INTENSE)
    ///
    /// Ej: sesión de 45 min → calidad 3.
    /// Ej: sesión de 90 min → calidad 5.
    static let thresholds: [(minMinutes: Int, quality: Int)] = [
        (90, 5),
        (60, 4),
        (45, 3),
        (30, 2),
        (15, 1)
    ]

    /// Etiquetas para display. Índice = calidad.
    static let labels: [Int: String] = [
        0: "—",
        1: "MINIMAL",
        2: "SHORT",
        3: "STANDARD",
        4: "DEEP",
        5: "INTENSE"
    ]

    // MARK: - Bonus de chips por calidad

    /// Multiplicador aplicado al `sessionChips` base, según calidad.
    /// Diseño: extra suave para no desbalancear la economía.
    ///
    /// Ej: sesión de 60 min → 20 chips base.
    ///     Calidad 5 (90+) → 20 * 1.10 = 22 chips.
    ///     Calidad 2 (30–44) → 20 * 1.02 = 20.4 → 20 chips (redondeo).
    static let chipMultiplier: [Int: Double] = [
        0: 0.0,   // no gana (no aplica)
        1: 1.00,  // +0%
        2: 1.02,  // +2%
        3: 1.04,  // +4%
        4: 1.07,  // +7%
        5: 1.10   // +10% (máximo)
    ]
}