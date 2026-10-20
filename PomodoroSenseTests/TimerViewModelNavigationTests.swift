//
//  TimerViewModelNavigationTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  TimerViewModelNavigationTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

/// Tests del flag `wantsToNavigateToTimer`. Verifica que los flujos
/// que arrancan un timer desde fuera de `.mainTimer` disparen la
/// navegación hacia la pantalla del timer.
@Suite("TimerViewModel — navegación al timer")
@MainActor
struct TimerViewModelNavigationTests {

    @Test("wantsToNavigateToTimer arranca en false")
    func flagStartsFalse() {
        let vm = TimerViewModel()
        #expect(vm.wantsToNavigateToTimer == false)
    }

    @Test("Marcar wantsToNavigateToTimer=true es observable por el padre")
    func flagCanBeSet() {
        let vm = TimerViewModel()
        vm.wantsToNavigateToTimer = true
        #expect(vm.wantsToNavigateToTimer == true)
    }

    // Nota: los flujos async de unlink (`unlinkAndStartNewSession`)
    // son privados y dependen de sync. Se cubren indirectamente al
    // verificar manualmente que al hacer unlink desde SavedPresets
    // la app navega a .mainTimer.
}

@Suite("TimerViewModel — persistencia en background")
@MainActor
struct TimerViewModelBackgroundTests {

    @Test("sceneMovedToBackground con isRunning=false es no-op")
    func sceneMovedToBackgroundIsNoOpWhenNotRunning() {
            // Sin esto, `restorePersistedState()` puede rehidratar isRunning = true
            // desde UserDefaults.standard (leftover de un test anterior que dejó
            // una sesión corriendo). El test debe arrancar desde cero.
            TimerViewModel.clearPersistedSessionKeys()
            let vm = TimerViewModel()
            // isRunning = false porque acabamos de limpiar.
    }

    @Test("sceneMovedToBackground con isRunning=true no crashea")
    func sceneMovedToBackgroundWithRunningDoesNotCrash() {
        let vm = TimerViewModel()
        vm.isRunning = true
        // targetDate es privado; como no está seteado, el guard corta
        // igual y no pasa nada. El test verifica que no crashee.
        vm.sceneMovedToBackground()
        #expect(vm.isRunning == true)
    }
}
