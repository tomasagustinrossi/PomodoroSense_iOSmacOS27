//
//  CurrencyTier.swift
//  PomodoroSense
//

import Foundation
import SwiftUI

/// Los tres niveles de moneda del sistema.
/// Prestige: cada tier se desbloquea al maximizar el anterior.
nonisolated enum CurrencyTier: String, Codable, CaseIterable, Identifiable {
    case bronze
    case silver
    case gold

    var id: String { rawValue }

    // MARK: - Modelo

    var displayName: String {
        switch self {
        case .bronze: return "CHIPS"
        case .silver: return "SILVER"
        case .gold:   return "CROWN"
        }
    }

    var symbolName: String {
        switch self {
        case .bronze: return "circle.hexagongrid.fill"
        case .silver: return "circle.hexagongrid.circle.fill"
        case .gold:   return "crown.fill"
        }
    }

    /// Cap máximo alcanzable por juego normal.
    /// Los valores viven en `CurrencyBalance.swift`.
    var softCap: Int {
        switch self {
        case .bronze: return CurrencyBalance.bronzeSoftCap
        case .silver: return CurrencyBalance.silverSoftCap
        case .gold:   return CurrencyBalance.goldSoftCap
        }
    }

    /// Multiplicador de dificultad relativo al tier base.
    /// Los valores viven en `CurrencyBalance.swift`.
    var difficultyMultiplier: Double {
        switch self {
        case .bronze: return CurrencyBalance.bronzeDifficulty
        case .silver: return CurrencyBalance.silverDifficulty
        case .gold:   return CurrencyBalance.goldDifficulty
        }
    }

    /// Condición de desbloqueo.
    var unlockCondition: UnlockCondition {
        switch self {
        case .bronze: return .always
        case .silver: return .streak(minimum: CurrencyBalance.silverUnlockStreak)
        case .gold:   return .streak(minimum: CurrencyBalance.goldUnlockStreak) // <-- NUEVA REGLA
        }
    }

    enum UnlockCondition {
        case always
        case streak(minimum: Int)
        case previousTierMaxed(CurrencyTier)
    }

    static var ordered: [CurrencyTier] { [.bronze, .silver, .gold] }

    // MARK: - UI

    /// Color principal del tier.
    var tintColor: Color {
        switch self {
        case .bronze: return Color(red: 0.95, green: 0.65, blue: 0.40)
        case .silver: return Color(red: 0.78, green: 0.82, blue: 0.88)
        case .gold:   return Color(red: 1.00, green: 0.82, blue: 0.30)
        }
    }

    /// Color secundario para gradientes.
    var tintColorSecondary: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.25)
        case .silver: return Color(red: 0.55, green: 0.60, blue: 0.68)
        case .gold:   return Color(red: 0.90, green: 0.62, blue: 0.15)
        }
    }

    /// Ícono para la insignia del tier.
    var iconName: String {
        switch self {
        case .bronze: return "circle.hexagongrid.fill"
        case .silver: return "circle.hexagongrid.circle.fill"
        case .gold:   return "crown.fill"
        }
    }

    /// Texto de desbloqueo para el popup especial.
    var unlockHeadline: String {
        switch self {
        case .bronze: return "SILVER TIER REACHED"
        case .silver: return "GOLD TIER REACHED"
        case .gold:   return "MAX TIER REACHED"
        }
    }
}
