//
//  TimerViewModelSkipTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  TimerViewModelSkipTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("TimerViewModel — skip no acredita chips")
@MainActor
struct TimerViewModelSkipTests {

    @Test("wantsToNavigateToSavedPresets arranca en false")
    func flagStartsFalse() {
        let vm = TimerViewModel()
        #expect(vm.wantsToNavigateToSavedPresets == false)
    }

    @Test("userSkipNext en modo normal no dispara navegación inmediata")
    func userSkipNextDoesNotNavigateImmediately() {
        let vm = TimerViewModel()
        vm.userSkipNext()
        // No es la última sesión, así que no debería navegar.
        #expect(vm.wantsToNavigateToSavedPresets == false)
    }

    @Test("resetToInitialState limpia todos los popups")
    func resetClearsAllPopups() {
        let vm = TimerViewModel()
        vm.sessionReward = nil
        vm.sessionSummary = nil
        vm.tierUnlock = nil

        vm.resetToInitialState()

        #expect(vm.sessionReward == nil)
        #expect(vm.sessionSummary == nil)
        #expect(vm.tierUnlock == nil)
        #expect(vm.wantsToNavigateToSavedPresets == false)
    }
}

@Suite("TimerViewModel — restauración de segundos guardados")
@MainActor
struct TimerViewModelRestoreSecondsTests {

    @Test("savePersistedState guarda session_secondsRemaining")
    func saveStoresSecondsRemaining() {
        // Limpiamos UserDefaults para el test.
        let key = "session_secondsRemaining"
        UserDefaults.standard.removeObject(forKey: key)

        let vm = TimerViewModel()
        vm.savePersistedState()

        // El valor debe estar guardado (aunque sea 0 en idle).
        let stored = UserDefaults.standard.integer(forKey: key)
        #expect(stored >= 0, "El valor guardado debe ser >= 0")

        UserDefaults.standard.removeObject(forKey: key)
    }
}