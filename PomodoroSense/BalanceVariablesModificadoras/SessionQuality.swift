//
//  SessionQuality.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  SessionQuality.swift
//  PomodoroSense
//
//  Cálculo de la calidad (0–5) de una sesión según su duración.
//  Consume los cortes definidos en `QualityBalance.swift`.
//

import Foundation

nonisolated enum SessionQuality {

    /// Devuelve la calidad (0–5) según minutos de foco.
    ///
    ///   - < 15 min  → 0 (no cuenta)
    ///   - 15–29     → 1
    ///   - 30–44     → 2
    ///   - 45–59     → 3
    ///   - 60–89     → 4
    ///   - 90+       → 5
    ///
    /// Los cortes exactos viven en `QualityBalance.thresholds`.
    /// Cambiar uno recalibra automáticamente toda la app.
    static func from(minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }

        // `thresholds` está ordenado descendente: el primer match gana.
        for entry in QualityBalance.thresholds {
            if minutes >= entry.minMinutes {
                return entry.quality
            }
        }
        return 0
    }

    /// Etiqueta para UI. Ej: 5 → "INTENSE", 0 → "—".
    static func label(for quality: Int) -> String {
        QualityBalance.labels[quality] ?? "—"
    }

    /// Multiplicador de chips según calidad. Ej: 5 → 1.10x.
    static func chipMultiplier(for quality: Int) -> Double {
        QualityBalance.chipMultiplier[quality] ?? 1.0
    }
}