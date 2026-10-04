//
//  ScoreBalance.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  ScoreBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: ScoreCalculator, SessionStore.
//     La UI NUNCA accede directo — siempre vía los servicios.
//
//  Aquí viven los parámetros del sistema de scoring y recompensas
//  por sesión. Cambiar un valor acá recalibra toda la economía.
//

import Foundation

nonisolated enum ScoreBalance {

    // MARK: - Duración

    /// Duración máxima reconocida de una sesión de foco.
    /// Sesiones más largas se clampan.
    /// Ej: 90 min de foco → se cuenta como 60 para el cálculo base.
    static let maxSessionMinutes = 60

    /// Duración mínima para ganar chips (sin bonus, sin consolación).
    /// Ej: 25 min → 0 chips. 30 min → 2 chips.
    static let minChipMinutes = 30

    /// Duración mínima para la "consolación" (1 chip simbólico).
    /// Aplica solo si es día 2+ de racha o no es la primera sesión del día.
    /// Ej: sesión de 20 min en día 3 de racha → 1 chip.
    static let minConsolationMinutes = 15

    // MARK: - Decay diario

    /// Cuántas sesiones del día valen 100% antes de empezar a decaer.
    /// Después, cada sesión vale 10% menos que la anterior.
    /// Ej: 4 sesiones a full, la 5ta vale 90%, la 6ta 81%, etc.
    static let freeSessionsPerDay = 4

    /// Factor de decaimiento por sesión extra (post-free).
    /// Ej: 0.9 → cada sesión post-4 pierde 10%.
    static let decayPerExtraSession = 0.9

    // MARK: - Racha

    /// Tope del multiplicador de racha (bronze).
    /// Ej: con curva 1.1^(days-1), se alcanza el cap en día 26.
    static let streakCap = 10.0

    /// Base del multiplicador de racha diaria.
    /// Ej: base 1.1 → día 1 = 1.0x, día 2 = 1.1x, día 3 = 1.21x...
    static let streakBaseMultiplier = 1.1

    // MARK: - Lucky

    /// Probabilidad (%) de que una sesión sea "lucky".
    /// Solo aplica a sesiones ≥ minChipMinutes.
    /// Ej: 12 → 12% de las sesiones largas dan bonus.
    static let luckyPercent: UInt64 = 12

    /// Multiplicador de chips si la sesión fue lucky.
    /// Ej: sesión de 30 min (2 chips base) * 1.5 = 3 chips.
    static let luckyBoost = 1.5

    // MARK: - Curva de chips por sesión

    /// Base de la curva (chips en la duración mínima).
    /// Ej: 2 → sesión de 30 min da 2 chips.
    static let chipCurveBase = 2

    /// Factor cuadrático de la curva (crecimiento hacia duración máxima).
    /// Ej: 18 → sesión de 60 min da 20 chips (2 + 18).
    static let chipCurveQuadratic = 18

    // MARK: - Multiplicadores por tier

    /// Multiplicador de racha para bronze (curva principal).
    /// Ej: día 1 → 1.0x, día 10 → 2.36x, día 26+ → 10x (cap).
    static let bronzeStreakCap = 10.0

    /// Día del unlock de silver (a partir de este día, silver acredita).
    /// Ej: 26 → con streak 26+, silver empieza a dar chips.
    static let silverUnlockDay = 26

    /// Divisor del multiplicador de silver.
    /// Días en silver / divisor = multiplicador. Más chico = más rápido.
    /// Ej: 12 → al día 12 en silver, multiplier = 1.0.
    static let silverCurveDivisor = 12.0

    /// Cap del multiplicador de silver.
    /// Ej: 5.0 → aunque tengas 500 días de racha, silver da máx 5x.
    static let silverMultiplierCap = 5.0

    /// Multiplicador de gold (placeholder hasta definir balanceo).
    /// Ej: 1.0 → gold acredita a la velocidad de silver / 50.
    static let goldMultiplier = 1.0
}