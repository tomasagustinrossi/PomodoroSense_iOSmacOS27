//
//  ScoreCalculatorCurveTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  ScoreCalculatorTests.swift
//  PomodoroSenseTests
//
//  Tests de la lógica pura de ScoreCalculator.
//  Sin dependencias de SwiftUI, sin Date(), sin UUID(), sin I/O.
//

import Testing
import Foundation
@testable import PomodoroSense

// MARK: - Helpers

/// Crea un record de prueba con valores controlados.
private func makeRecord(
    focusMinutes: Int,
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
    wasSkipped: Bool = false,
    wasInterrupted: Bool = false
) -> PomodoroSessionRecord {
    PomodoroSessionRecord(
        id: UUID(),
        ownerDeviceId: UUID(),
        dayStart: Calendar.current.startOfDay(for: timestamp),
        timestamp: timestamp,
        presetName: "TEST",
        focusMinutes: focusMinutes,
        sessionNumber: 1,
        totalSessions: 5,
        wasSkipped: wasSkipped,
        wasInterrupted: wasInterrupted
    )
}

/// Comparación de dobles con tolerancia.
private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.0001) -> Bool {
    abs(a - b) < tolerance
}

// MARK: - Suite

@Suite("ScoreCalculator — curvas base")
struct ScoreCalculatorCurveTests {

    // MARK: sessionChips (curva por duración)

    @Test("Sesiones < 30 min dan 0 chips")
    func sessionChipsBelowThresholdIsZero() {
        #expect(ScoreCalculator.sessionChips(forMinutes: 0) == 0)
        #expect(ScoreCalculator.sessionChips(forMinutes: 15) == 0)
        #expect(ScoreCalculator.sessionChips(forMinutes: 29) == 0)
    }

    @Test("Valores conocidos de la curva (30 → 2, 60 → 20)")
    func sessionChipsKnownAnchors() {
        #expect(ScoreCalculator.sessionChips(forMinutes: 30) == 2)
        #expect(ScoreCalculator.sessionChips(forMinutes: 60) == 20)
    }

    @Test("La curva es monótona creciente")
    func sessionChipsIsMonotonic() {
        var previous = ScoreCalculator.sessionChips(forMinutes: 30)
        for minutes in 31...60 {
            let current = ScoreCalculator.sessionChips(forMinutes: minutes)
            #expect(current >= previous, "Decreció en \(minutes) min")
            previous = current
        }
    }

    @Test("Minutos > 60 se clampan a 60")
    func sessionChipsClampsAboveMax() {
        #expect(ScoreCalculator.sessionChips(forMinutes: 120)
                == ScoreCalculator.sessionChips(forMinutes: 60))
    }

    // MARK: dayDecay

    @Test("Las primeras 4 sesiones del día no decaen")
    func dayDecayFirstFourNoDecay() {
        for i in 1...4 {
            #expect(isClose(ScoreCalculator.dayDecay(sessionIndex: i), 1.0))
        }
    }

    @Test("A partir de la 5ta, decae 10% por sesión")
    func dayDecayAfterFourth() {
        #expect(isClose(ScoreCalculator.dayDecay(sessionIndex: 5), 0.9))
        #expect(isClose(ScoreCalculator.dayDecay(sessionIndex: 6), 0.81))
        #expect(isClose(ScoreCalculator.dayDecay(sessionIndex: 7), 0.729))
    }

    // MARK: streakMultiplier

    @Test("Racha 0 o 1 → multiplicador 1.0")
    func streakMultiplierBaseCase() {
        #expect(isClose(ScoreCalculator.streakMultiplier(consecutiveDays: 0), 1.0))
        #expect(isClose(ScoreCalculator.streakMultiplier(consecutiveDays: 1), 1.0))
    }

    @Test("Racha 26 → cap 10x exacto")
    func streakMultiplierCapsAt10() {
        let m26 = ScoreCalculator.streakMultiplier(consecutiveDays: 26)
        #expect(isClose(m26, 10.0, tolerance: 0.01))

        let m100 = ScoreCalculator.streakMultiplier(consecutiveDays: 100)
        #expect(isClose(m100, 10.0), "Debe quedar capado en 10x")
    }

    // MARK: comboLabel

    @Test("Combo labels según sesiones y total del preset")
    func comboLabelVariants() {
        #expect(ScoreCalculator.comboLabel(sessionsToday: 0, totalInPreset: 5) == "")
        #expect(ScoreCalculator.comboLabel(sessionsToday: 1, totalInPreset: 5) == "WARM UP")
        #expect(ScoreCalculator.comboLabel(sessionsToday: 2, totalInPreset: 5) == "COMBO x2")
        #expect(ScoreCalculator.comboLabel(sessionsToday: 3, totalInPreset: 5) == "HOT STREAK")
        #expect(ScoreCalculator.comboLabel(sessionsToday: 5, totalInPreset: 5) == "JACKPOT")
        #expect(ScoreCalculator.comboLabel(sessionsToday: 6, totalInPreset: 5) == "JACKPOT")
    }
}

// MARK: - Suite de multiplicadores por tier

@Suite("ScoreCalculator — multiplicadores por tier")
struct ScoreCalculatorTierMultiplierTests {

    @Test("Bronze: cap 10x en día 26")
    func bronzeCaps() {
        #expect(isClose(ScoreCalculator.bronzeMultiplier(streakDays: 1), 1.0))
        #expect(isClose(ScoreCalculator.bronzeMultiplier(streakDays: 26), 10.0, tolerance: 0.01))
        #expect(isClose(ScoreCalculator.bronzeMultiplier(streakDays: 100), 10.0))
    }

    @Test("Silver: 0 hasta día 25")
    func silverZeroBeforeUnlock() {
        for day in 0...25 {
            #expect(ScoreCalculator.silverMultiplier(streakDays: day) == 0,
                    "Silver debe ser 0 en día \(day)")
        }
    }

    @Test("Silver: acredita desde el día 26 (día del unlock)")
    func silverCreditsFromUnlockDay() {
        // Verifica que el multiplicador sea > 0 el día exacto del unlock.
        // Antes del fix, devolvía 0 → el usuario desbloqueaba silver pero
        // no ganaba nada ese día.
        let silverAt26 = ScoreCalculator.silverMultiplier(streakDays: 26)
        #expect(silverAt26 > 0, "Silver debe acreditar en día 26 (día del unlock)")

        // Y también el día 25 (justo antes del unlock) debe ser 0.
        #expect(ScoreCalculator.silverMultiplier(streakDays: 25) == 0,
                "Silver no debe acreditar antes del día 26")
    }

    @Test("Silver: cap 5.0x")
    func silverCaps() {
        let veryHigh = ScoreCalculator.silverMultiplier(streakDays: 500)
        #expect(isClose(veryHigh, 5.0, tolerance: 0.01))
    }

    @Test("Silver: crece monotónicamente")
    func silverMonotonic() {
        var previous = ScoreCalculator.silverMultiplier(streakDays: 26)
        for day in 27...120 {
            let current = ScoreCalculator.silverMultiplier(streakDays: day)
            #expect(current >= previous, "Silver decreció en día \(day)")
            previous = current
        }
    }

    @Test("Gold: placeholder 1x")
    func goldPlaceholder() {
        // Documenta el estado actual: gold siempre da 1x (placeholder).
        #expect(isClose(ScoreCalculator.goldMultiplier(streakDays: 30), 1.0))
        #expect(isClose(ScoreCalculator.goldMultiplier(streakDays: 365), 1.0))
    }
}

// MARK: - Suite de tierEarnings

@Suite("ScoreCalculator — tierEarnings")
struct ScoreCalculatorTierEarningsTests {

    @Test("Bronze siempre acredita para sesiones >= 30 min")
    func bronzeAlwaysCredits() {
        let record = makeRecord(focusMinutes: 30)
        let wallet = CurrencyWallet()  // solo bronze unlock
        let earnings = ScoreCalculator.tierEarnings(
            for: record,
            streakDays: 1,
            wallet: wallet
        )
        #expect((earnings[.bronze] ?? 0) > 0)
        #expect(earnings[.silver] == nil, "Silver no debe acreditar si no está unlockeado")
        #expect(earnings[.gold] == nil, "Gold no debe acreditar si no está unlockeado")
    }

    @Test("Sesión corta (< 30 min) no genera earnings")
    func shortSessionNoEarnings() {
        let record = makeRecord(focusMinutes: 20)
        let wallet = CurrencyWallet()
        let earnings = ScoreCalculator.tierEarnings(
            for: record,
            streakDays: 1,
            wallet: wallet
        )
        #expect(earnings.isEmpty, "Sesiones < 30 min no dan chips")
    }

    @Test("Silver acredita con streak alto y sesiones largas")
    func silverCreditsWithHighStreakAndLongSession() {
        // Uso streak 60 (multiplicador 2.83x) y sesión de 60 min (base 20).
        // silverRaw = 20 × 2.83 / 10 = 5.66 → redondea 6.
        // Verificamos que la integración complete funcione end-to-end.
        let record = makeRecord(focusMinutes: 60)
        var wallet = CurrencyWallet()
        wallet.unlockedTiers.insert(.silver)

        let earnings = ScoreCalculator.tierEarnings(
            for: record,
            streakDays: 60,
            wallet: wallet
        )
        #expect((earnings[.bronze] ?? 0) > 0, "Bronze debe acreditar")
        #expect((earnings[.silver] ?? 0) > 0, "Silver debe acreditar con streak 60 + sesión 60 min")
    }

    
    @Test("Documenta: silver tarda en acreditar con sesiones medianas")
    func silverSlowStartIsDocumented() {
        // Esto NO es un bug: es el comportamiento actual de la curva.
        // Con sesiones de 45 min, silver no aparece hasta aproximadamente
        // el día 36-37. Si en algún momento cambiamos la curva y este
        // test falla, es una señal de que hay que revisar el balance.
        let record = makeRecord(focusMinutes: 45)
        var wallet = CurrencyWallet()
        wallet.unlockedTiers.insert(.silver)

        let earnings = ScoreCalculator.tierEarnings(
            for: record,
            streakDays: 30,
            wallet: wallet
        )
        #expect((earnings[.silver] ?? 0) == 0,
                "Con streak 30 y 45 min, silver sigue en 0 (curva actual)")
    }

    @Test("Gold acredita si está unlockeado")
    func goldCreditsWhenUnlocked() {
        let record = makeRecord(focusMinutes: 60)
        var wallet = CurrencyWallet()
        wallet.unlockedTiers.insert(.silver)
        wallet.unlockedTiers.insert(.gold)

        let earnings = ScoreCalculator.tierEarnings(
            for: record,
            streakDays: 30,
            wallet: wallet
        )
        #expect((earnings[.gold] ?? 0) >= 0)
        // Gold es placeholder 1x, con base 20 → 20 / 50 = 0.4 → redondea 0.
        // Documenta el comportamiento actual.
        #expect((earnings[.gold] ?? 0) == 0, "Con base 20 y multiplier 1, gold = 0 (placeholder)")
    }
}

// MARK: - Suite de isLucky (determinismo)

@Suite("ScoreCalculator — isLucky determinístico")
struct ScoreCalculatorLuckyTests {

    @Test("El mismo seed siempre da el mismo resultado")
    func luckyIsDeterministic() {
        let seed = 1_700_000_000
        let result1 = ScoreCalculator.rewards(
            records: [makeRecord(focusMinutes: 60, timestamp: Date(timeIntervalSince1970: TimeInterval(seed)))],
            streakDays: 1
        ).first?.isLucky

        let result2 = ScoreCalculator.rewards(
            records: [makeRecord(focusMinutes: 60, timestamp: Date(timeIntervalSince1970: TimeInterval(seed)))],
            streakDays: 1
        ).first?.isLucky

        #expect(result1 == result2, "isLucky debe ser determinístico para el mismo timestamp")
    }
}
