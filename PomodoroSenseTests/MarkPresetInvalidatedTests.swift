//
//  MarkPresetInvalidatedTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 14/10/2026.
//


//
//  PresetRunTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

// MARK: - Helpers

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "Test.PresetRun.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
}

private func cleanupDefaults(_ suiteName: String) {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}

private func makeRecord(
    runId: UUID?,
    day: Date = Date(),
    minutes: Int = 30,
    quality: Int = 2,
    skipped: Bool = false,
    interrupted: Bool = false,
    owner: UUID = UUID()
) -> PomodoroSessionRecord {
    let cal = Calendar.current
    return PomodoroSessionRecord(
        id: UUID(),
        ownerDeviceId: owner,
        dayStart: cal.startOfDay(for: day),
        timestamp: day,
        presetName: "T",
        focusMinutes: minutes,
        sessionNumber: 1,
        totalSessions: 5,
        wasSkipped: skipped,
        wasInterrupted: interrupted,
        quality: quality,
        presetRunId: runId
    )
}

// MARK: - Suites

@Suite("SessionStore — markPresetInvalidated")
@MainActor
struct MarkPresetInvalidatedTests {

    @Test("Marca todos los records de la corrida")
    func marksAllRecordsInRun() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        store.insertRecordsForTest([
            makeRecord(runId: runId, minutes: 30),
            makeRecord(runId: runId, minutes: 45),
            makeRecord(runId: runId, minutes: 60)
        ])

        let affected = store.markPresetInvalidated(runId)

        #expect(affected == 3)
        #expect(store.records.allSatisfy { $0.presetInvalidated == true })
    }

    @Test("No toca records de otras corridas")
    func doesntTouchOtherRuns() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runA = UUID()
        let runB = UUID()
        store.insertRecordsForTest([
            makeRecord(runId: runA, minutes: 30),
            makeRecord(runId: runA, minutes: 45),
            makeRecord(runId: runB, minutes: 60),
            makeRecord(runId: runB, minutes: 30)
        ])

        let affected = store.markPresetInvalidated(runA)

        #expect(affected == 2)
        let runARecords = store.records(forPresetRunId: runA)
        let runBRecords = store.records(forPresetRunId: runB)
        #expect(runARecords.allSatisfy { $0.presetInvalidated })
        #expect(runBRecords.allSatisfy { !$0.presetInvalidated })
    }

    @Test("Corrida inexistente devuelve 0 y no crashea")
    func unknownRunIsNoOp() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([makeRecord(runId: UUID())])

        let affected = store.markPresetInvalidated(UUID())

        #expect(affected == 0)
        #expect(store.records.allSatisfy { !$0.presetInvalidated })
    }

    @Test("Records con presetRunId nil NO se tocan por accidente")
    func nilRunIdRecordsAreSafe() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        store.insertRecordsForTest([
            makeRecord(runId: nil, minutes: 30),
            makeRecord(runId: runId, minutes: 60)
        ])

        _ = store.markPresetInvalidated(runId)

        let nilRecord = store.records.first { $0.presetRunId == nil }
        #expect(nilRecord?.presetInvalidated == false)
    }

    @Test("Idempotente: llamar dos veces no rompe nada")
    func idempotent() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        store.insertRecordsForTest([
            makeRecord(runId: runId),
            makeRecord(runId: runId)
        ])

        let first = store.markPresetInvalidated(runId)
        let second = store.markPresetInvalidated(runId)

        #expect(first == 2)
        #expect(second == 2) // sigue contando los que "ya estaban" — es informativo
        #expect(store.records.allSatisfy { $0.presetInvalidated })
    }
}

@Suite("SessionStore — reassignPresetToDate")
@MainActor
struct ReassignPresetToDateTests {

    @Test("Mueve el dayStart de todos los records de la corrida")
    func movesAllRecords() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let today = Date()

        store.insertRecordsForTest([
            makeRecord(runId: runId, day: yesterday),
            makeRecord(runId: runId, day: yesterday)
        ])

        let affected = store.reassignPresetToDate(runId, to: today)

        #expect(affected == 2)
        let expectedDayStart = cal.startOfDay(for: today)
        let records = store.records(forPresetRunId: runId)
        #expect(records.allSatisfy { $0.dayStart == expectedDayStart })
    }

    @Test("Normaliza el `day` a startOfDay")
    func normalizesToStartOfDay() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let arbitrary = Date(timeIntervalSince1970: 1_700_000_000)

        store.insertRecordsForTest([makeRecord(runId: runId)])
        _ = store.reassignPresetToDate(runId, to: arbitrary)

        let expected = Calendar.current.startOfDay(for: arbitrary)
        #expect(store.records[0].dayStart == expected)
    }

    @Test("NO toca el timestamp (preserva el orden real)")
    func preservesTimestamp() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let originalDate = Date(timeIntervalSince1970: 1_600_000_000)

        store.insertRecordsForTest([makeRecord(runId: runId, day: originalDate)])
        let originalTimestamp = store.records[0].timestamp

        _ = store.reassignPresetToDate(runId, to: Date())

        #expect(store.records[0].timestamp == originalTimestamp)
    }

    @Test("No toca records de otras corridas")
    func doesntTouchOtherRuns() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runA = UUID()
        let runB = UUID()
        let cal = Calendar.current
        let dayA = cal.date(byAdding: .day, value: -5, to: Date())!
        let dayB = Date()

        store.insertRecordsForTest([
            makeRecord(runId: runA, day: dayA),
            makeRecord(runId: runB, day: dayA)
        ])

        _ = store.reassignPresetToDate(runA, to: dayB)

        let runBRecord = store.records(forPresetRunId: runB).first
        #expect(runBRecord?.dayStart == cal.startOfDay(for: dayA))
    }

    @Test("Corrida inexistente devuelve 0")
    func unknownRunIsNoOp() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([makeRecord(runId: UUID())])

        let affected = store.reassignPresetToDate(UUID(), to: Date())

        #expect(affected == 0)
    }
}

@Suite("SessionStore — records(forPresetRunId:)")
@MainActor
struct RecordsForPresetRunTests {

    @Test("Devuelve solo los records del run pedido, ordenados por timestamp")
    func returnsSortedRecordsForRun() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let other = UUID()

        // Insertamos en orden no-secuencial para verificar el sort.
        store.insertRecordsForTest([
            makeRecord(runId: runId, day: Date(timeIntervalSince1970: 300)),
            makeRecord(runId: other, day: Date(timeIntervalSince1970: 400)),
            makeRecord(runId: runId, day: Date(timeIntervalSince1970: 100)),
            makeRecord(runId: runId, day: Date(timeIntervalSince1970: 200))
        ])

        let records = store.records(forPresetRunId: runId)

        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.presetRunId == runId })
        #expect(records[0].timestamp < records[1].timestamp)
        #expect(records[1].timestamp < records[2].timestamp)
    }

    @Test("Run inexistente devuelve vacío")
    func unknownRunReturnsEmpty() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([makeRecord(runId: UUID())])

        let records = store.records(forPresetRunId: UUID())
        #expect(records.isEmpty)
    }
}

@Suite("SessionStore — integración Fase 1 (skip / calendario / racha)")
@MainActor
struct PresetRunIntegrationTests {

    @Test("Skip invalida la corrida: no cuenta para chips ni calendario")
    func skipInvalidatesChipsAndCalendar() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let today = Date()

        // 3 focus completados + 1 skip, todos de la misma corrida.
        store.insertRecordsForTest([
            makeRecord(runId: runId, day: today, minutes: 30),
            makeRecord(runId: runId, day: today, minutes: 30),
            makeRecord(runId: runId, day: today, minutes: 30),
            makeRecord(runId: runId, day: today, skipped: true)
        ])

        // Antes de invalidar: 3 records califican.
        #expect(store.records.filter { $0.qualifiesForChips }.count == 3)
        #expect(store.hasAnyRecord(on: today) == true)

        _ = store.markPresetInvalidated(runId)

        // Después de invalidar: 0 califican, y el día "está vacío".
        #expect(store.records.filter { $0.qualifiesForChips }.isEmpty)
        #expect(store.hasAnyRecord(on: today) == false)
        #expect(store.calendarScore(on: today) == 0)
        #expect(store.totalFocusMinutes(on: today) == 0)
    }

    @Test("Corrida válida: acredita todas las sesiones del preset")
    func validRunCreditsAllSessions() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let runId = UUID()
        let today = Date()

        store.insertRecordsForTest([
            makeRecord(runId: runId, day: today, minutes: 30, quality: 2),
            makeRecord(runId: runId, day: today, minutes: 45, quality: 3),
            makeRecord(runId: runId, day: today, minutes: 60, quality: 4)
        ])

        let valid = store.records(forPresetRunId: runId)
            .filter { $0.qualifiesForChips }

        #expect(valid.count == 3)
        #expect(store.totalFocusMinutes(on: today) == 135)
        #expect(store.hasAnyRecord(on: today) == true)
    }

    @Test("Racha: día con corrida invalidada no suma ni rompe")
    func invalidatedDayDoesNotBreakStreak() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Día -2 y -1 con corrida válida. Hoy con corrida invalidada.
        let run1 = UUID(), run2 = UUID(), run3 = UUID()
        let day1 = cal.date(byAdding: .day, value: -2, to: today)!
        let day2 = cal.date(byAdding: .day, value: -1, to: today)!

        store.insertRecordsForTest([
            makeRecord(runId: run1, day: day1, minutes: 30),
            makeRecord(runId: run2, day: day2, minutes: 30),
            makeRecord(runId: run3, day: today, minutes: 30)
        ])
        _ = store.markPresetInvalidated(run3)

        // La racha desde hoy es 0 (hoy no cuenta porque su única corrida
        // está invalidada).
        #expect(store.currentStreak == 0)

        // Racha desde ayer sí cuenta los 2 días previos.
        let streakFromYesterday = store.streakEnding(on: day2)
        #expect(streakFromYesterday == 2)
    }

    @Test("Cruce de medianoche: todos los records caen en el día del cierre")
    func midnightCrossingMovesAllToClosingDay() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let cal = Calendar.current
        let runId = UUID()

        // Simulamos: preset arranca a las 23:30 de ayer, termina 00:15 hoy.
        let startDay = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date())!)
        let endDay = cal.startOfDay(for: Date())

        // Los records se crean con `dayStart = startDay` (así se guardaron
        // al completarse los focus).
        store.insertRecordsForTest([
            makeRecord(runId: runId, day: startDay, minutes: 30),
            makeRecord(runId: runId, day: startDay, minutes: 30)
        ])

        // Antes de reasignar: el score está en el día de ayer.
        #expect(store.totalFocusMinutes(on: startDay) == 60)
        #expect(store.totalFocusMinutes(on: endDay) == 0)

        // El cierre del preset dispara la reasignación.
        _ = store.reassignPresetToDate(runId, to: endDay)

        // Después: todo cuenta para el día del cierre.
        #expect(store.totalFocusMinutes(on: startDay) == 0)
        #expect(store.totalFocusMinutes(on: endDay) == 60)
    }

    @Test("Presets distintos en el mismo día no se pisan")
    func differentRunsSameDayAreIndependent() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        let today = Date()
        let runA = UUID()
        let runB = UUID()

        store.insertRecordsForTest([
            makeRecord(runId: runA, day: today, minutes: 30),
            makeRecord(runId: runA, day: today, minutes: 30),
            makeRecord(runId: runB, day: today, minutes: 45)
        ])

        // Invalidamos runA. runB debe seguir válido.
        _ = store.markPresetInvalidated(runA)

        let valid = store.records.filter { $0.qualifiesForChips }
        #expect(valid.count == 1)
        #expect(valid.first?.presetRunId == runB)
        #expect(store.totalFocusMinutes(on: today) == 45)
    }
}
