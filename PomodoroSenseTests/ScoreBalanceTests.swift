//
//  BalanceContractTests.swift
//  PomodoroSenseTests
//
//  Verifica que los valores de balance son los esperados.
//  Actúa como documentación viva + guard contra cambios accidentales.
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("Balance — ScoreBalance")
struct ScoreBalanceTests {

    @Test("Valores de duración")
    func durationValues() {
        #expect(ScoreBalance.maxSessionMinutes == 60)
        #expect(ScoreBalance.minChipMinutes == 30)
        #expect(ScoreBalance.minConsolationMinutes == 15)
    }

    @Test("Decay y racha")
    func decayAndStreak() {
        #expect(ScoreBalance.freeSessionsPerDay == 4)
        #expect(ScoreBalance.decayPerExtraSession == 0.9)
        #expect(ScoreBalance.streakCap == 10.0)
        #expect(ScoreBalance.streakBaseMultiplier == 1.1)
    }

    @Test("Lucky")
    func luckyValues() {
        #expect(ScoreBalance.luckyPercent == 12)
        #expect(ScoreBalance.luckyBoost == 1.5)
    }

    @Test("Curva de chips")
    func chipCurve() {
        #expect(ScoreBalance.chipCurveBase == 2)
        #expect(ScoreBalance.chipCurveQuadratic == 18)
    }

    @Test("Tiers")
    func tierValues() {
        #expect(ScoreBalance.bronzeStreakCap == 10.0)
        #expect(ScoreBalance.silverUnlockDay == 26)
        #expect(ScoreBalance.silverCurveDivisor == 12.0)
        #expect(ScoreBalance.silverMultiplierCap == 5.0)
        #expect(ScoreBalance.goldMultiplier == 1.0)
    }
}

@Suite("Balance — CurrencyBalance")
struct CurrencyBalanceTests {

    @Test("Caps")
    func caps() {
        #expect(CurrencyBalance.bronzeSoftCap == 1000)
        #expect(CurrencyBalance.silverSoftCap == 500)
        #expect(CurrencyBalance.goldSoftCap == 200)
    }

    @Test("Dificultad relativa")
    func difficulty() {
        #expect(CurrencyBalance.bronzeDifficulty == 1.0)
        #expect(CurrencyBalance.silverDifficulty == 10.0)
        #expect(CurrencyBalance.goldDifficulty == 50.0)
    }

    @Test("Consistencia de unlock de silver")
    func silverUnlockConsistent() {
        #expect(CurrencyBalance.silverUnlockStreak == ScoreBalance.silverUnlockDay,
                "El unlock de silver debe coincidir entre CurrencyBalance y ScoreBalance")
    }
}

@Suite("Balance — QualityBalance")
struct QualityBalanceTests {

    @Test("Cortes de calidad")
    func thresholds() {
        #expect(QualityBalance.thresholds.count == 5)
        // Verificar orden descendente
        let mins = QualityBalance.thresholds.map(\.minMinutes)
        #expect(mins == mins.sorted(by: >))
    }

    @Test("Multiplicador de chips por calidad")
    func chipMultiplier() {
        #expect(QualityBalance.chipMultiplier[0] == 0.0)
        #expect(QualityBalance.chipMultiplier[1] == 1.00)
        #expect(QualityBalance.chipMultiplier[5] == 1.10)
    }

    @Test("Multiplicador es monótono creciente")
    func chipMultiplierMonotonic() {
        for q in 1..<5 {
            let current = QualityBalance.chipMultiplier[q] ?? 0
            let next    = QualityBalance.chipMultiplier[q + 1] ?? 0
            #expect(next >= current, "Multiplier debe crecer con calidad")
        }
    }
}

@Suite("Balance — SyncBalance")
struct SyncBalanceTests {

    @Test("Tolerancias")
    func tolerances() {
        #expect(SyncBalance.envelopeToleranceSeconds == 90)
        #expect(SyncBalance.nonceLifetimeSeconds == 120)
        #expect(SyncBalance.nonceCleanupIntervalSeconds == 60)
    }

    @Test("Comandos del widget")
    func widgetCommands() {
        #expect(SyncBalance.widgetCommandTTL == 15)
    }

    @Test("Framing TCP")
    func framing() {
        #expect(SyncBalance.frameLengthPrefixBytes == 4)
        #expect(SyncBalance.maxReceiveBufferBytes == 1_048_576)
        #expect(SyncBalance.maxReceiveChunkBytes == 65_536)
    }
}

@Suite("Balance — AudioBalance")
struct AudioBalanceTests {

    @Test("Ganancias máximas")
    func maxGains() {
        #expect(AudioBalance.maxToneGain == 0.11)
        #expect(AudioBalance.maxNoiseGain == 0.30)
    }

    @Test("Curvas")
    func curves() {
        #expect(AudioBalance.toneCurveExponent == 1.8)
        #expect(AudioBalance.noiseCurveExponent == 1.6)
    }

    @Test("Fades")
    func fades() {
        #expect(AudioBalance.fadeInDuration == 1.2)
        #expect(AudioBalance.pauseFadeDuration == 0.9)
        #expect(AudioBalance.stopFadeDuration == 1.6)
    }

    @Test("Frecuencia portadora")
    func carrier() {
        #expect(AudioBalance.carrierFrequency == 432)
    }
}