//
//  MonthlyReportTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "Test.MonthlyReport.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
}

private func cleanupDefaults(_ suiteName: String) {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}

@Suite("MonthlyReport — Codable")
struct MonthlyReportCodingTests {

    @Test("Round-trip JSON preserva todos los campos")
    func roundTrip() throws {
        let report = MonthlyReport(
            year: 2025,
            month: 3,
            totalFocusMinutes: 1250,
            totalSessionsCompleted: 42,
            totalSessionsSkipped: 3,
            totalSessionsInterrupted: 2,
            bronzeEarned: 890,
            silverEarned: 12,
            goldEarned: 0,
            longestStreakInMonth: 18,
            activeDays: [1, 2, 5, 8, 12, 20]
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(MonthlyReport.self, from: data)

        #expect(decoded == report)
    }

    @Test("ID derivado es YYYY-MM con cero a la izquierda")
    func idFormat() {
        let r1 = MonthlyReport(year: 2025, month: 3, totalFocusMinutes: 0,
                               totalSessionsCompleted: 0, totalSessionsSkipped: 0,
                               totalSessionsInterrupted: 0, bronzeEarned: 0,
                               silverEarned: 0, goldEarned: 0,
                               longestStreakInMonth: 0, activeDays: [])
        #expect(r1.id == "2025-03")
    }

    @Test("totalSessions suma los 3 tipos")
    func totalSessions() {
        let r = MonthlyReport(year: 2025, month: 1, totalFocusMinutes: 0,
                              totalSessionsCompleted: 10, totalSessionsSkipped: 2,
                              totalSessionsInterrupted: 3, bronzeEarned: 0,
                              silverEarned: 0, goldEarned: 0,
                              longestStreakInMonth: 0, activeDays: [])
        #expect(r.totalSessions == 15)
    }
}

@Suite("SessionStore — compactación de records")
@MainActor
struct SessionStoreCompactionTests {

    /// Crea un record con fecha arbitraria en el pasado.
    private func makeRecord(daysAgo: Int) -> PomodoroSessionRecord {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        return PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: UUID(),
            dayStart: cal.startOfDay(for: date),
            timestamp: date,
            presetName: "T",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5,
            wasSkipped: false,
            wasInterrupted: false,
            quality: 2
        )
    }

    @Test("Records dentro de 90 días NO se compactan")
    func recentRecordsSurvive() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([
            makeRecord(daysAgo: 5),
            makeRecord(daysAgo: 30),
            makeRecord(daysAgo: 85)
        ])

        store.compactOldRecordsIfNeeded()

        #expect(store.records.count == 3)
        #expect(store.monthlyReports.isEmpty)
    }

    @Test("Records > 90 días se convierten en report y se borran")
    func oldRecordsCompact() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([
            makeRecord(daysAgo: 100),
            makeRecord(daysAgo: 101),
            makeRecord(daysAgo: 102)
        ])

        store.compactOldRecordsIfNeeded()

        #expect(store.records.isEmpty, "Los records viejos deben borrarse")
        #expect(!store.monthlyReports.isEmpty, "Debe haberse generado un report")
        #expect(store.monthlyReports.first?.totalSessionsCompleted == 3)
    }

    @Test("Mezcla: viejos se compactan, recientes se mantienen")
    func mixedRecords() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([
            makeRecord(daysAgo: 10),
            makeRecord(daysAgo: 50),
            makeRecord(daysAgo: 100),
            makeRecord(daysAgo: 150)
        ])

        store.compactOldRecordsIfNeeded()

        // Los 2 recientes sobreviven.
        #expect(store.records.count == 2)
        // Los 2 viejos generaron report(s).
        let totalReported = store.monthlyReports.reduce(0) { $0 + $1.totalSessionsCompleted }
        #expect(totalReported == 2)
    }

    @Test("Segunda corrida no duplica reports")
    func idempotent() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanupDefaults(suite) }

        let store = SessionStore(defaults: defaults)
        store.insertRecordsForTest([
            makeRecord(daysAgo: 100),
            makeRecord(daysAgo: 101)
        ])

        store.compactOldRecordsIfNeeded()
        let countAfterFirst = store.monthlyReports.count

        store.compactOldRecordsIfNeeded()
        let countAfterSecond = store.monthlyReports.count

        #expect(countAfterFirst == countAfterSecond,
                "Correr dos veces no debe duplicar reports")
    }
}