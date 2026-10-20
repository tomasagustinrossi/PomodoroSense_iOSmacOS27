//
//  DebugUserData.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 19/10/2026.
//


//
//  DebugUserData.swift
//  PomodoroSense
//
//  ⚠️ SOLO DEBUG. Este archivo existe para inyectar datos de prueba
//  sin tocar el código de producción ni la lógica real.
//
//  Flujo de trabajo:
//    1. Editás los valores de acá.
//    2. Compilás y corrés.
//    3. `SessionStore.load()` aplica estas overrides EN MEMORIA
//       (no se persisten a disco: cada launch vuelve al estado de acá).
//
//  Para "ver como usuario nuevo": poné isEnabled = false.
//  Para "ver como usuario con plata": seteá bronze/silver/gold.
//

#if DEBUG
import Foundation

enum DebugUserData {

    /// Master switch. `false` → se usan los datos reales persistidos.
    static let isEnabled: Bool = true

    // MARK: - Wallet

    /// nil = no toca el valor persistido.
    static let bronze: Int? = 1
    static let silver: Int? = nil
    static let gold:   Int? = nil

    /// Tiers desbloqueados. nil = no toca.
    static let unlockedTiers: Set<CurrencyTier>? = nil //[.bronze, .silver, .gold]
    
    /// ⚠️ NUEVO: Si es true, borra TODOS los datos guardados en UserDefaults
    /// (wallet, records, objetivos, items comprados, sesión en curso) antes de
    /// inyectar los datos de acá. Hace que cada "Play" en Xcode sea un lienzo en blanco.
    static let resetOnLaunch: Bool = true


    /// Fuerza el flag que hace visible la tienda.
    /// nil → se deriva: true si bronze+silver+gold > 0.
    static let hasEverReceivedCurrency: Bool? = nil

    // MARK: - Tienda

    /// IDs de items comprados.
    /// nil = no toca. `[]` = ningún item.
    static let purchasedItemIds: Set<String>? = [] // Ej. "bronze.bolt", "silver.eye"

    /// Atajo: si true, compra TODOS los items del catálogo (ignora purchasedItemIds).
    static let purchaseAllItems: Bool = false

    // MARK: - Records de sesiones

    /// Si true, borra los records existentes e inyecta sesiones de prueba.
    static let injectRecords: Bool = true

    /// Días hacia atrás a cubrir.
    static let recordsDaysBack: Int = 30

    /// Sesiones por día.
    static let recordsPerDay: Int = 2

    /// Minutos de cada sesión de prueba.
    static let recordFocusMinutes: Int = 30
}
#endif


/*
 EJEMPLO 1 Usuario nuevo (shop oculto, colección vacía)
 
 static let isEnabled = true
 static let bronze: Int? = 0
 static let silver: Int? = nil
 static let gold: Int? = nil
 static let unlockedTiers: Set<CurrencyTier>? = [.bronze]
 static let purchasedItemIds: Set<String>? = []
 static let injectRecords: Bool = false
 */
/*
 EJEMPLO 2 Usuario rico con todo comprado
 
 static let bronze: Int? = 999
 static let silver: Int? = 499
 static let gold: Int? = 199
 static let purchaseAllItems: Bool = true
 static let injectRecords: Bool = true
 static let recordsDaysBack: Int = 60
 */

/*
 Apagar todo el modo debug
 
 static let isEnabled = false
 */
