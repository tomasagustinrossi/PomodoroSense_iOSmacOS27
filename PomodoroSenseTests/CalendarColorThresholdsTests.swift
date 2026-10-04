//
//  CalendarColorCalculatorTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("CalendarColorCalculator — thresholds")
struct CalendarColorThresholdsTests {

    @Test("Con < 7 días usa fallback absoluto")
    func fallbackWhenFewDays() {
        let scores = [10, 20, 30, 40, 50, 60]  // 6 días
        let t = CalendarColorCalculator.calculateThresholds(from: scores)
        #expect(t == .fallback)
    }

    @Test("Con 0 días usa fallback")
    func fallbackWhenNoData() {
        let t = CalendarColorCalculator.calculateThresholds(from: [])
        #expect(t == .fallback)
    }

    @Test("Con >= 7 días usa percentiles")
    func dynamicWhenEnoughDays() {
        let scores = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        let t = CalendarColorCalculator.calculateThresholds(from: scores)
        // p25 de 10 items → índice 2 → 30
        // p50 → índice 5 → 60
        // p75 → índice 7 → 80
        // p90 → índice 9 → 100
        #expect(t.p25 == 30)
        #expect(t.p50 == 60)
        #expect(t.p75 == 80)
        #expect(t.p90 == 100)
    }

    @Test("Días en 0 no cuentan para el cálculo")
    func zerosIgnoredInThreshold() {
        // Solo 3 días con score real → fallback
        let scores = [0, 0, 0, 0, 100, 200, 300, 0, 0, 0]
        let t = CalendarColorCalculator.calculateThresholds(from: scores)
        #expect(t == .fallback, "Solo 3 días con score > 0 → fallback")
    }
}

@Suite("CalendarColorCalculator — tiers")
struct CalendarColorTierTests {

    @Test("Score 0 devuelve noFocus")
    func zeroScore() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 0, thresholds: t) == .noFocus)
    }

    @Test("Score negativo devuelve noFocus")
    func negativeScore() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: -10, thresholds: t) == .noFocus)
    }

    @Test("Score <= p25 → level1")
    func level1() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 50, thresholds: t) == .level1)
        #expect(CalendarColorCalculator.tier(for: 99, thresholds: t) == .level1)
    }

    @Test("Score <= p50 → level2")
    func level2() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 100, thresholds: t) == .level2)
        #expect(CalendarColorCalculator.tier(for: 249, thresholds: t) == .level2)
    }

    @Test("Score <= p75 → level3")
    func level3() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 250, thresholds: t) == .level3)
        #expect(CalendarColorCalculator.tier(for: 499, thresholds: t) == .level3)
    }

    @Test("Score <= p90 → level4")
    func level4() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 500, thresholds: t) == .level4)
        #expect(CalendarColorCalculator.tier(for: 999, thresholds: t) == .level4)
    }

    @Test("Score > p90 → level5")
    func level5() {
        let t = CalendarColorThresholds.fallback
        #expect(CalendarColorCalculator.tier(for: 1000, thresholds: t) == .level5)
        #expect(CalendarColorCalculator.tier(for: 10000, thresholds: t) == .level5)
    }
}