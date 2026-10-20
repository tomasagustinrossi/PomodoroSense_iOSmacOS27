//
//  CurrencyBalance.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  CurrencyBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: CurrencyTier, CurrencyWallet.
//     La UI NUNCA accede directo.
//
//  Caps, dificultad relativa y condiciones de unlock por tier.
//

import Foundation

nonisolated enum CurrencyBalance {

    // MARK: - Soft caps

    /// Cap máximo alcanzable por juego normal para cada tier.
    /// El `add` clampea automáticamente.
    /// Ej: bronze 1000 → al llegar a 1000, deja de sumar.
    static let bronzeSoftCap = 1000
    static let silverSoftCap = 500
    static let goldSoftCap = 500
    
    // MARK: - Límites diarios (Anti-farmeo)
    /// Máximo de plata que se puede ganar en un solo día.
    static let silverDailyCap = 10
    
    /// Máximo de oro que se puede ganar en un solo día.
    static let goldDailyCap = 1

    // MARK: - Dificultad relativa

    /// Cuánto más difícil es ganar 1 unidad de este tier vs. bronze.
    /// Usado para dividir el multiplicador de racha.
    /// Ej: silver es 10x más difícil → base 20 de bronze equivale a 2 de silver.
    static let bronzeDifficulty = 1.0
    static let silverDifficulty = 40.0
    static let goldDifficulty = 50.0

    // MARK: - Condiciones de unlock

    /// Días de racha mínimos para desbloquear silver.
    /// Debe coincidir con `ScoreBalance.silverUnlockDay`.
    /// Días de racha mínimos para desbloquear silver.
    static let silverUnlockStreak = 26

    /// Días de racha mínimos para desbloquear gold.
    /// 60 días = 2 meses de constancia perfecta.
    static let goldUnlockStreak = 60

    // MARK: - Deprecations

    // ⚠️ El antiguo `ShopCatalog.totalCost` y su validación de softCap
    // se eliminaron del cálculo cuando la tienda quedó vacía.
    // Cuando se agreguen items, revisar que los caps sigan siendo ≥ al
    // total de costos.
}
