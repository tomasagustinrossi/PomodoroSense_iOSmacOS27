//
//  TimerViewModelLifecycleTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("TimerViewModel — ciclo de vida")
@MainActor
struct TimerViewModelLifecycleTests {

    @Test("sceneMovedToBackground no crashea en idle")
    func backgroundIdleIsSafe() {
        UserDefaults.standard.removeObject(forKey: "session_isRunning")
        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")

        let vm = TimerViewModel()
        vm.sceneMovedToBackground()
        #expect(vm.isRunning == false)

        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
    }

    @Test("sceneMovedToForeground no crashea en idle")
    func foregroundIdleIsSafe() {
        UserDefaults.standard.removeObject(forKey: "session_isRunning")
        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")

        let vm = TimerViewModel()
        vm.sceneMovedToForeground()
        #expect(vm.isRunning == false)
    }

    @Test("Ciclo background → foreground mantiene estado consistente")
    func backgroundForegroundCycle() {
        UserDefaults.standard.removeObject(forKey: "session_isRunning")
        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")

        let vm = TimerViewModel()
        vm.sceneMovedToBackground()
        vm.sceneMovedToForeground()

        #expect(vm.isRunning == false)
        #expect(vm.currentSession == 1)

        UserDefaults.standard.removeObject(forKey: "session_lastSaveTimestamp")
    }

    @Test("clearPersistedSessionKeys limpia lastSaveTimestamp")
    func clearRemovesTimestamp() {
        UserDefaults.standard.set(1.0, forKey: "session_lastSaveTimestamp")
        TimerViewModel.clearPersistedSessionKeys()
        let value = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        #expect(value == 0, "Debe haberse limpiado")
    }
}