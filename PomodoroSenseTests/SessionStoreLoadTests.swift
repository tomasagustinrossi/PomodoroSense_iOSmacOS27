//
//  SessionStoreLoadTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  SessionStoreTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

/// Crea un UserDefaults aislado para el test, y lo limpia al final.
private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "Test.SessionStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
}

private func cleanupDefaults(suiteName: String) {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}

// MARK: - Suite

@Suite("SessionStore — carga inicial")
@MainActor
struct SessionStoreLoadTests {

    @Test("Store arranca con wallet default si no hay datos")
    func startsWithEmptyWallet() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)

        #expect(store.wallet.bronze == 0)
        #expect(store.wallet.silver == 0)
        #expect(store.wallet.gold == 0)
        #expect(store.records.isEmpty)
    }

    @Test("Store carga wallet desde defaults si existe")
    func loadsWalletFromDefaults() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        var savedWallet = CurrencyWallet()
        savedWallet.bronze = 42
        savedWallet.silver = 7
        let data = try JSONEncoder().encode(savedWallet)
        defaults.set(data, forKey: "Pomodoro_Currency_Wallet")

        let store = SessionStore(defaults: defaults)

        #expect(store.wallet.bronze == 42)
        #expect(store.wallet.silver == 7)
    }
}

@Suite("SessionStore — registro de sesiones")
@MainActor
struct SessionStoreRecordTests {

    @Test("recordCompletedSession agrega un record con wasSkipped=false, wasInterrupted=false")
    func recordsCompletedSession() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        store.recordCompletedSession(
            presetName: "TEST",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5
        )

        #expect(store.records.count == 1)
        let r = store.records[0]
        #expect(r.wasSkipped == false)
        #expect(r.wasInterrupted == false)
        #expect(r.focusMinutes == 30)
        #expect(r.qualifiesForChips == true)
    }

    @Test("recordSkippedSession marca wasSkipped=true")
    func recordsSkippedSession() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        store.recordSkippedSession(
            presetName: "TEST",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5
        )

        #expect(store.records.count == 1)
        let r = store.records[0]
        #expect(r.wasSkipped == true)
        #expect(r.wasInterrupted == false)
        #expect(r.qualifiesForChips == false)
    }

    @Test("recordInterruptedSession marca wasInterrupted=true")
    func recordsInterruptedSession() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        store.recordInterruptedSession(
            presetName: "TEST",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5
        )

        #expect(store.records.count == 1)
        let r = store.records[0]
        #expect(r.wasSkipped == false)
        #expect(r.wasInterrupted == true)
        #expect(r.qualifiesForChips == false)
    }
}

@Suite("SessionStore — consultas")
@MainActor
struct SessionStoreQueryTests {

    @Test("totalFocusMinutes ignora sesiones salteadas")
    func totalFocusIgnoresSkipped() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        store.recordCompletedSession(presetName: "T", focusMinutes: 30, sessionNumber: 1, totalSessions: 5)
        store.recordSkippedSession(presetName: "T", focusMinutes: 30, sessionNumber: 2, totalSessions: 5)
        store.recordCompletedSession(presetName: "T", focusMinutes: 30, sessionNumber: 3, totalSessions: 5)

        let total = store.totalFocusMinutes(on: Date())
        #expect(total == 60, "Solo deben contar las 2 completadas: 30 + 30 = 60")
    }

    @Test("streakEnding cuenta días consecutivos")
    func streakCountsConsecutiveDays() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Registramos sesiones en días -2, -1, 0
        for offset in [-2, -1, 0] {
            if let day = cal.date(byAdding: .day, value: offset, to: today) {
                store.recordCompletedSessionOn(day: day)
            }
        }

        let streak = store.streakEnding(on: today)
        #expect(streak == 3)
    }

    @Test("streakEnding corta con un día sin sesión")
    func streakBreaksOnGap() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Días -3, -2, y 0 (falta -1)
        for offset in [-3, -2, 0] {
            if let day = cal.date(byAdding: .day, value: offset, to: today) {
                store.recordCompletedSessionOn(day: day)
            }
        }

        let streak = store.streakEnding(on: today)
        #expect(streak == 1, "Debe cortar en el gap de -1")
    }
}

@Suite("SessionStore — creditSession")
@MainActor
struct SessionStoreCreditTests {

    @Test("creditSession suma al wallet")
    func creditsWallet() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        let store = SessionStore(defaults: defaults)
        let earned = store.creditSession([.bronze: 10], streakDays: 1)

        #expect(earned[.bronze] == 10)
        #expect(store.wallet.bronze == 10)
    }

    @Test("creditSession devuelve el monto REAL acreditado (post-cap)")
    func creditsRespectsSoftCap() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        var initial = CurrencyWallet()
        initial.bronze = 995
        let data = try! JSONEncoder().encode(initial)
        defaults.set(data, forKey: "Pomodoro_Currency_Wallet")

        let store = SessionStore(defaults: defaults)
        let earned = store.creditSession([.bronze: 50], streakDays: 1)

        #expect(store.wallet.bronze == 1000, "Debe clampear al cap")
        #expect(earned[.bronze] == 5, "Solo 5 se acreditaron realmente")
    }

    @Test("creditSession no devuelve tiers sin ganancia")
    func creditsSkipEmptyTiers() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suiteName: suite) }

        var initial = CurrencyWallet()
        initial.bronze = 1000   // ya en el cap
        let data = try! JSONEncoder().encode(initial)
        defaults.set(data, forKey: "Pomodoro_Currency_Wallet")

        let store = SessionStore(defaults: defaults)
        let earned = store.creditSession([.bronze: 10], streakDays: 1)

        #expect(earned.isEmpty, "No debe haber tiers acreditados")
    }
}