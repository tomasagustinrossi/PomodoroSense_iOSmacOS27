//
//  TimerViewModelRestoreHeuristicTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("TimerViewModel — heurística de restauración")
@MainActor
struct TimerViewModelRestoreHeuristicTests {

    @Test("savePersistedState guarda session_lastSaveTimestamp")
    func saveStoresTimestamp() {
        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
        UserDefaults.standard.removeObject(forKey: "session_isRunning")

        let vm = TimerViewModel()
        vm.savePersistedState()

        let saved = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        #expect(saved > 0, "Debe haber guardado un timestamp")

        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
    }

    @Test("save reciente produce delta < 5s")
    func recentSaveHasSmallDelta() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970 - 1.0,
            forKey: "session_lastSaveTimestamp"
        )
        let lastSave = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        let delta = Date().timeIntervalSince1970 - lastSave
        #expect(delta < 5.0, "1s atrás debe considerarse app viva")

        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
    }

    @Test("save viejo produce delta > 5s (app muerta)")
    func oldSaveHasLargeDelta() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970 - 30.0,
            forKey: "session_lastSaveTimestamp"
        )
        let lastSave = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        let delta = Date().timeIntervalSince1970 - lastSave
        #expect(delta > 5.0, "30s atrás debe considerarse app muerta")

        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
    }

    @Test("Timestamp ausente significa app muerta")
    func missingTimestampMeansKilled() {
        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
        let lastSave = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        #expect(lastSave == 0)
    }
}
