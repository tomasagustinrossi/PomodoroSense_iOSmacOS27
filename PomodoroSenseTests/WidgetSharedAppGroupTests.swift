//
//  WidgetSharedTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("WidgetShared — App Group y contrato")
struct WidgetSharedAppGroupTests {

    @Test("El App Group ID es el correcto (contrato entre targets)")
    func appGroupIdIsCorrect() {
        #expect(WidgetShared.appGroupId == "group.com.tomiirossi.PomodoroSense")
    }
}

@Suite("WidgetShared — round-trip de estado del timer")
struct WidgetSharedTimerStateTests {

    @Test("WidgetTimerState hace round-trip JSON exacto")
    func timerStateRoundTrip() throws {
        let original = WidgetTimerState(
            isRunning: true,
            isBreak: false,
            currentSession: 3,
            totalSessions: 5,
            targetDate: Date(timeIntervalSince1970: 1_700_000_000),
            pausedSeconds: nil,
            noiseId: 2,
            presetName: "DEEP WORK"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetTimerState.self, from: data)

        #expect(decoded == original)
    }

    @Test("WidgetTimerState.idle tiene valores coherentes")
    func idleStateIsSane() {
        let idle = WidgetTimerState.idle
        #expect(idle.isRunning == false)
        #expect(idle.targetDate == nil)
        #expect(idle.pausedSeconds == nil)
        #expect(idle.currentSession == 1)
        #expect(idle.totalSessions >= 1)
    }
}

@Suite("WidgetShared — round-trip de economía")
struct WidgetSharedEconomyStateTests {

    @Test("WidgetEconomyState hace round-trip JSON exacto")
    func economyStateRoundTrip() throws {
        let original = WidgetEconomyState(
            bronze: 1234,
            silver: 56,
            gold: 7,
            streak: 42,
            hasRecordsToday: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetEconomyState.self, from: data)

        #expect(decoded == original)
    }

    @Test("WidgetEconomyState.empty está en ceros")
    func emptyStateIsZeroed() {
        let empty = WidgetEconomyState.empty
        #expect(empty.bronze == 0)
        #expect(empty.silver == 0)
        #expect(empty.gold == 0)
        #expect(empty.streak == 0)
        #expect(empty.hasRecordsToday == false)
    }
}