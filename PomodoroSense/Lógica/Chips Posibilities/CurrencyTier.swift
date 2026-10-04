//
//  CurrencyTier.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 09/10/2026.
//


import Foundation

/// Los tres niveles de moneda del sistema.
/// El sistema es "prestige": cada tier se desbloquea al maximizar el anterior.
/// Los valores de `softCap` y `difficultyMultiplier` son los que se ajustan
/// cuando se agregan items a la tienda (para que el total jugable alcance).
enum CurrencyTier: String, Codable, CaseIterable, Identifiable {
    case bronze
    case silver
    case gold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bronze: return "CHIPS"
        case .silver: return "SILVER"
        case .gold:   return "GOLD"
        }
    }

    var symbolName: String {
        switch self {
        case .bronze: return "circle.hexagongrid.fill"
        case .silver: return "circle.hexagongrid.circle.fill"
        case .gold:   return "crown.fill"
        }
    }

    /// Cap máximo alcanzable por juego normal (sin contar drops de tienda).
    /// ⚠️ AJUSTAR cuando agregues items: debe ser ≥ a la suma de costos
    /// de todos los items del tier en la tienda.
    var softCap: Int {
        switch self {
        case .bronze: return 1000
        case .silver: return 500
        case .gold:   return 200
        }
    }

    /// Multiplicador de dificultad relativo al tier base.
    /// Cuanto más alto, más lento se acumula este tier.
    /// - Silver tarda ~2 meses de racha mantenida.
    /// - Gold tarda mucho más y es el techo final.
    var difficultyMultiplier: Double {
        switch self {
        case .bronze: return 1.0
        case .silver: return 10.0
        case .gold:   return 50.0
        }
    }

    /// Condición de desbloqueo de este tier.
    var unlockCondition: UnlockCondition {
        switch self {
        case .bronze: return .always
        case .silver: return .streak(minimum: 26)
        case .gold:   return .previousTierMaxed(.silver)
        }
    }

    enum UnlockCondition {
        case always
        case streak(minimum: Int)
        case previousTierMaxed(CurrencyTier)
    }

    /// Orden jerárquico para iterar (bronze < silver < gold).
    static var ordered: [CurrencyTier] { [.bronze, .silver, .gold] }
}