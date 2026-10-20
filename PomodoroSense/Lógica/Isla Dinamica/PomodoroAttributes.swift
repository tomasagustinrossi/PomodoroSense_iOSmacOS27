//
//  PomodoroAttributes.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//

import Foundation
import SwiftUI

/// Payload del reward al terminar una sesión. Viaja dentro de `ContentState`
/// para que el widget lo muestre sin cálculos propios.
nonisolated struct SessionRewardPayload: Codable, Hashable {
    var chipsEarned: Int          // chips ganados por ESTA sesión
    var totalChipsToday: Int      // acumulado del día incluyendo esta
    var newStreak: Int            // racha resultante
    var isLucky: Bool             // si esta sesión fue "lucky"
    var isLastSession: Bool       // si fue la última del preset
    var isJackpot: Bool           // máxima recompensa alcanzada
    // ─── NUEVO: breakdown por tier ───
    var bronzeEarned: Int
    var silverEarned: Int
    var goldEarned: Int
    var newlyUnlockedTier: CurrencyTier?   // si esta sesión desbloqueó un tier nuevo

    var generatedAt: Date   // para auto-expirar el panel

        /// Total de currency ganada (todos los tiers).
    var totalEarned: Int { bronzeEarned + silverEarned + goldEarned }
}

#if os(iOS)
import ActivityKit

nonisolated struct PomodoroAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isBreak: Bool
        var currentSession: Int
        var totalSessions: Int
        var targetDate: Date
        var noiseId: Int
        public var isRunning: Bool
        var pausedSeconds: Int?
        var reward: SessionRewardPayload?
        var isFreeMode: Bool = false // <-- ÚNICO AGREGADO
    }
    var presetName: String
}
#endif
