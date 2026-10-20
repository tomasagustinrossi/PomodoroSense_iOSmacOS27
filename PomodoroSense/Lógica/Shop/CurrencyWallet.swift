//
//  CurrencyWallet.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 09/10/2026.
//

import Foundation

/// Estado completo del "monedero" del usuario.
/// Se persiste en `SessionStore` junto con los records de sesión.
nonisolated struct CurrencyWallet: Codable, Hashable {

    // MARK: - Balances por tier

    var bronze: Int = 0
    var silver: Int = 0
    var gold: Int = 0

    /// Tiers ya desbloqueados (persistidos, no se pierden al bajar la racha).
    var unlockedTiers: Set<CurrencyTier> = [.bronze]

    // MARK: - Tienda (preparado para escalabilidad)

    /// IDs de items ya comprados.
    var purchasedItemIds: Set<String> = []
    
    /// `true` la primera vez que se acredita cualquier moneda (de cualquier tier).
    /// Se queda en `true` para siempre, aunque el usuario gaste todo. Se usa
    /// para decidir si la tienda "existe" para el usuario.
    var hasEverReceivedCurrency: Bool = false

    // MARK: - Inicializadores

    init() {}

    // MARK: - CodingKeys + Decodificación tolerante

    enum CodingKeys: String, CodingKey {
        case bronze, silver, gold, unlockedTiers, purchasedItemIds, hasEverReceivedCurrency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bronze           = try c.decodeIfPresent(Int.self,                  forKey: .bronze)           ?? 0
        silver           = try c.decodeIfPresent(Int.self,                  forKey: .silver)           ?? 0
        gold             = try c.decodeIfPresent(Int.self,                  forKey: .gold)             ?? 0
        unlockedTiers    = try c.decodeIfPresent(Set<CurrencyTier>.self,    forKey: .unlockedTiers)    ?? [.bronze]
        purchasedItemIds = try c.decodeIfPresent(Set<String>.self,          forKey: .purchasedItemIds) ?? []
        hasEverReceivedCurrency = try c.decodeIfPresent(Bool.self, forKey: .hasEverReceivedCurrency) ?? false
    }

    // MARK: - Acceso por tier

    subscript(tier: CurrencyTier) -> Int {
        get {
            switch tier {
            case .bronze: return bronze
            case .silver: return silver
            case .gold:   return gold
            }
        }
        set {
            switch tier {
            case .bronze: bronze = newValue
            case .silver: silver = newValue
            case .gold:   gold = newValue
            }
        }
    }

    func isUnlocked(_ tier: CurrencyTier) -> Bool {
        unlockedTiers.contains(tier)
    }

    func isMaxed(_ tier: CurrencyTier) -> Bool {
        self[tier] >= tier.softCap
    }

    // MARK: - Mutaciones

    mutating func add(_ amount: Int, to tier: CurrencyTier) {
        guard amount > 0 else { return }
        let newValue = min(self[tier] + amount, tier.softCap)
        self[tier] = newValue
        hasEverReceivedCurrency = true
    }

    mutating func reevaluateUnlocks(streakDays: Int) {
        // Silver: se desbloquea por racha
        if case .streak(let min) = CurrencyTier.silver.unlockCondition,
            streakDays >= min,
            !unlockedTiers.contains(.silver) {
            unlockedTiers.insert(.silver)
        }
        
        // Gold: se desbloquea por racha (60 días), NO por llegar al tope de plata
        if case .streak(let min) = CurrencyTier.gold.unlockCondition,
            streakDays >= min,
            !unlockedTiers.contains(.gold) {
            unlockedTiers.insert(.gold)
        }
    }
    
    // MARK: - Helpers para la UI

    var activeTier: CurrencyTier {
        for tier in CurrencyTier.ordered.reversed() {
            if isUnlocked(tier) && !isMaxed(tier) { return tier }
        }
        for tier in CurrencyTier.ordered.reversed() {
            if isUnlocked(tier) { return tier }
        }
        return .bronze
    }

    func progress(of tier: CurrencyTier) -> Double {
        guard tier.softCap > 0 else { return 0 }
        return min(1.0, Double(self[tier]) / Double(tier.softCap))
    }
}
