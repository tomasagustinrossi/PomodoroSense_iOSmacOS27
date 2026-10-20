//
//  CurrencyWalletInitialTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  CurrencyWalletTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("CurrencyWallet — estado inicial")
struct CurrencyWalletInitialTests {

    @Test("Wallet default: bronze=0, silver=0, gold=0")
    func defaultWalletIsEmpty() {
        let w = CurrencyWallet()
        #expect(w.bronze == 0)
        #expect(w.silver == 0)
        #expect(w.gold == 0)
    }

    @Test("Wallet default: solo bronze desbloqueado")
    func defaultUnlocksOnlyBronze() {
        let w = CurrencyWallet()
        #expect(w.isUnlocked(.bronze) == true)
        #expect(w.isUnlocked(.silver) == false)
        #expect(w.isUnlocked(.gold) == false)
    }

    @Test("Wallet default: sin items comprados")
    func defaultNoPurchasedItems() {
        let w = CurrencyWallet()
        #expect(w.purchasedItemIds.isEmpty)
    }
}

@Suite("CurrencyWallet — subscript y add")
struct CurrencyWalletAddTests {

    @Test("Subscript get/set redirige al campo correcto")
    func subscriptRoutesToCorrectField() {
        var w = CurrencyWallet()
        w[.bronze] = 10
        w[.silver] = 20
        w[.gold] = 30

        #expect(w.bronze == 10)
        #expect(w.silver == 20)
        #expect(w.gold == 30)
        #expect(w[.bronze] == 10)
        #expect(w[.silver] == 20)
        #expect(w[.gold] == 30)
    }

    @Test("add suma correctamente por debajo del cap")
    func addBelowCap() {
        var w = CurrencyWallet()
        w.add(50, to: .bronze)
        #expect(w.bronze == 50)

        w.add(30, to: .bronze)
        #expect(w.bronze == 80)
    }

    @Test("add clampea al softCap")
    func addClampsToSoftCap() {
        var w = CurrencyWallet()
        w.bronze = 990

        w.add(50, to: .bronze)   // cap = 1000

        #expect(w.bronze == 1000, "add no debe superar el softCap")
    }

    @Test("add con amount 0 o negativo no hace nada")
    func addIgnoresNonPositive() {
        var w = CurrencyWallet()
        w.bronze = 100

        w.add(0, to: .bronze)
        w.add(-10, to: .bronze)

        #expect(w.bronze == 100)
    }

    @Test("add respeta los caps específicos de cada tier")
    func addRespectsPerTierCaps() {
        var w = CurrencyWallet()

        w.silver = 495
        w.add(10, to: .silver)   // cap = 500
        #expect(w.silver == 500)

        w.gold = 195
        w.add(10, to: .gold)     // cap = 200
        #expect(w.gold == 200)
    }
}

@Suite("CurrencyWallet — isMaxed y progress")
struct CurrencyWalletCapTests {

    @Test("isMaxed true exactamente en el cap")
    func isMaxedAtCap() {
        var w = CurrencyWallet()
        #expect(w.isMaxed(.bronze) == false)

        w.bronze = 999
        #expect(w.isMaxed(.bronze) == false)

        w.bronze = 1000
        #expect(w.isMaxed(.bronze) == true)

        w.bronze = 1500   // nunca debería pasar, pero por si acaso
        #expect(w.isMaxed(.bronze) == true)
    }

    @Test("progress devuelve 0..1")
    func progressRange() {
        var w = CurrencyWallet()
        #expect(w.progress(of: .bronze) == 0.0)

        w.bronze = 500
        #expect(w.progress(of: .bronze) == 0.5)

        w.bronze = 1000
        #expect(w.progress(of: .bronze) == 1.0)
    }

    @Test("progress nunca excede 1")
    func progressClampsAtOne() {
        var w = CurrencyWallet()
        w.bronze = 5000
        #expect(w.progress(of: .bronze) == 1.0)
    }
}

@Suite("CurrencyWallet — unlock conditions")
struct CurrencyWalletUnlockTests {

    @Test("Silver se desbloquea con streak >= 26")
    func silverUnlocksAt26() {
        var w = CurrencyWallet()

        w.reevaluateUnlocks(streakDays: 25)
        #expect(w.isUnlocked(.silver) == false)

        w.reevaluateUnlocks(streakDays: 26)
        #expect(w.isUnlocked(.silver) == true)
    }

    @Test("Gold se desbloquea cuando silver está maxeado")
    func goldUnlocksWhenSilverMaxed() {
        var w = CurrencyWallet()
        w.unlockedTiers.insert(.silver)

        // Con silver a 499, gold sigue bloqueado
        w.silver = 499
        w.reevaluateUnlocks(streakDays: 30)
        #expect(w.isUnlocked(.gold) == false)

        // Al llegar a 500, gold se desbloquea
        w.silver = 500
        w.reevaluateUnlocks(streakDays: 30)
        #expect(w.isUnlocked(.gold) == true)
    }

    @Test("Unlock es persistente aunque la racha baje")
    func unlocksAreSticky() {
        var w = CurrencyWallet()
        w.reevaluateUnlocks(streakDays: 26)
        #expect(w.isUnlocked(.silver) == true)

        // Simulamos que el usuario rompió la racha (streak = 0)
        w.reevaluateUnlocks(streakDays: 0)

        // Silver debe seguir desbloqueado
        #expect(w.isUnlocked(.silver) == true)
    }
}

@Suite("CurrencyWallet — activeTier")
struct CurrencyWalletActiveTierTests {

    @Test("activeTier es bronze en un wallet default")
    func activeTierDefaultIsBronze() {
        let w = CurrencyWallet()
        #expect(w.activeTier == .bronze)
    }

    @Test("activeTier salta a silver si bronze está maxeado y silver unlockeado")
    func activeTierAdvancesWhenBronzeMaxed() {
        var w = CurrencyWallet()
        w.unlockedTiers.insert(.silver)
        w.bronze = 1000   // maxeado
        #expect(w.activeTier == .silver)
    }

    @Test("activeTier no salta a silver si no está unlockeado")
    func activeTierStaysBronzeIfSilverLocked() {
        var w = CurrencyWallet()
        w.bronze = 1000
        // silver no unlockeado
        #expect(w.activeTier == .bronze)
    }

    @Test("activeTier devuelve gold si todo lo demás está maxeado")
    func activeTierEndsAtGold() {
        var w = CurrencyWallet()
        w.unlockedTiers = [.bronze, .silver, .gold]
        w.bronze = 1000
        w.silver = 500
        w.gold = 200   // maxeado
        #expect(w.activeTier == .gold)
    }
}

@Suite("CurrencyWallet — Codable round-trip")
struct CurrencyWalletCodingTests {

    @Test("Encode → Decode preserva todos los campos")
    func codableRoundTrip() throws {
        var original = CurrencyWallet()
        original.bronze = 42
        original.silver = 13
        original.gold = 7
        original.unlockedTiers = [.bronze, .silver]
        original.purchasedItemIds = ["item.a", "item.b"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CurrencyWallet.self, from: data)

        #expect(decoded == original)
    }

    @Test("Decode de JSON sin 'unlockedTiers' usa default")
    func decodeWithoutUnlockedTiersDefaults() throws {
        let json = """
        { "bronze": 10, "silver": 0, "gold": 0, "purchasedItemIds": [] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CurrencyWallet.self, from: json)

        #expect(decoded.bronze == 10)
        #expect(decoded.unlockedTiers == [.bronze],
                "Sin `unlockedTiers` en el JSON, debe usar el default")
    }
}