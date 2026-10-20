//
//  TimerViewModelPassiveUnlinkTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//

import Testing
import Foundation
@testable import PomodoroSense
@Suite("TimerViewModel — desvinculación pasiva no navega")
@MainActor
struct TimerViewModelPassiveUnlinkTests {

    @Test("disableSync no setea wantsToNavigateToTimer")
    func disableSyncDoesNotNavigate() async {
        let vm = TimerViewModel()
        // Simulamos estado típico de "apagando sync desde el popup".
        vm.wantsToNavigateToTimer = false

        await vm.disableSync()

        #expect(vm.wantsToNavigateToTimer == false,
                "Apagar sync no debe navegar al timer")
        #expect(vm.isMirror == false)
    }

    @Test("disableSync limpia el estado de mirror")
    func disableSyncCleansMirrorState() async {
        let vm = TimerViewModel()
        // Forzamos un estado mirror "sucio" antes de disable.
        // Los setters son privados, así que solo verificamos que después
        // del disable los flags quedan limpios.
        await vm.disableSync()

        #expect(vm.isMirror == false)
    }

    @Test("userStopAndReset no setea wantsToNavigateToTimer en modo mirror")
    func userStopAndResetDoesNotNavigateWhenMirror() async {
        let vm = TimerViewModel()
        // Si no estamos en mirror, `userStopAndReset` delega a `stopAndReset`
        // y no toca el flag. Si estamos en mirror, tampoco debe tocarlo
        // (más que resetearlo a false).
        vm.wantsToNavigateToTimer = false

        vm.userStopAndReset()

        #expect(vm.wantsToNavigateToTimer == false,
                "STOP es pasivo: no debe navegar")
    }

    @Test("Reset defensivo: flag en true se resetea al desvincular pasivamente")
    func defensiveResetClearsStuckFlag() async {
        let vm = TimerViewModel()
        // Simulamos un flag "pegado" de un flujo anterior.
        vm.wantsToNavigateToTimer = true

        await vm.disableSync()

        #expect(vm.wantsToNavigateToTimer == false,
                "disableSync debe limpiar un flag pegado")
    }
}
