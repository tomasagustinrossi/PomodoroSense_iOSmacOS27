//
//  TimerViewModelSessionSelectBaseTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


import Testing
import Foundation
@testable import PomodoroSense

// MARK: - Helpers

@MainActor
private func makeVM() -> TimerViewModel {
    SessionStore.shared.clearAllForTesting()
    // `clearAllForTesting()` solo limpia records/wallet/user/reports.
    // Las claves `session_*` en UserDefaults.standard persisten entre
    // tests y `restorePersistedState()` las rehidrata en el próximo init.
    // Sin esto, un test previo que terminó en break deja `isBreak = true`
    // y el siguiente test ve `userSelectSession` como no-op.
    TimerViewModel.clearPersistedSessionKeys()
    return TimerViewModel()
}

// MARK: - Sección A: cambio de sesión (comportamiento base)

@Suite("TimerViewModel — userSelectSession (base)")
@MainActor
struct TimerViewModelSessionSelectBaseTests {

    @Test("Forward invalida toda la corrida")
    func forwardInvalidatesAll() {
        let vm = makeVM()
        // Setup: sesión 1 completada, en sesión 2.
        let runId = vm.debugPresetRunIdForTest()
        SessionStore.shared.recordCompletedSession(
            presetName: vm.activeConfig.name,
            focusMinutes: vm.activeConfig.focus,
            sessionNumber: 1,
            totalSessions: vm.totalSessions,
            presetRunId: runId
        )

        vm.userSelectSession(4)

        #expect(vm.currentSession == 4)
        #expect(vm.debugPresetRunIdForTest() != runId, "forward debe regenerar presetRunId")
        #expect(vm.debugPendingPresetRecordIdsForTest().isEmpty)

        let oldRecords = SessionStore.shared.records(forPresetRunId: runId)
        #expect(oldRecords.allSatisfy { $0.presetInvalidated })
    }

    @Test("Backward invalida solo sesiones >= target")
    func backwardInvalidatesFromTarget() {
        let vm = makeVM()
        let runId = vm.debugPresetRunIdForTest()
        // Sesiones 1, 2, 3 completadas.
        for n in 1...3 {
            SessionStore.shared.recordCompletedSession(
                presetName: vm.activeConfig.name,
                focusMinutes: vm.activeConfig.focus,
                sessionNumber: n,
                totalSessions: vm.totalSessions,
                presetRunId: runId
            )
        }
        vm.debugSetCurrentSessionForTest(4)

        vm.userSelectSession(2)

        #expect(vm.currentSession == 2)
        #expect(vm.debugPresetRunIdForTest() == runId, "backward NO regenera presetRunId")

        let all = SessionStore.shared.records(forPresetRunId: runId)
        let s1 = all.first { $0.sessionNumber == 1 }
        let s2 = all.first { $0.sessionNumber == 2 }
        let s3 = all.first { $0.sessionNumber == 3 }
        #expect(s1?.qualifiesForChips == true)
        #expect(s2?.qualifiesForChips == false)
        #expect(s3?.qualifiesForChips == false)

        // Pending solo tiene el de sesión 1.
        let pending = vm.debugPendingPresetRecordIdsForTest()
        #expect(pending.count == 1)
        #expect(pending.first == s1?.id)
    }

    @Test("Misma sesión es no-op")
    func sameSessionNoop() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(3)
        vm.userSelectSession(3)
        #expect(vm.currentSession == 3)
    }

    @Test("Durante break es no-op")
    func duringBreakNoop() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(3)
        vm.debugSetIsBreakForTest(true)
        vm.userSelectSession(5)
        #expect(vm.currentSession == 3)
        #expect(vm.isBreak == true)
    }

    @Test("En mirror es no-op")
    func inMirrorNoop() {
        let vm = makeVM()
        vm.debugSetIsMirrorForTest(true)
        vm.debugSetCurrentSessionForTest(2)
        vm.userSelectSession(5)
        #expect(vm.currentSession == 2)
    }

    @Test("Fuera de rango es no-op")
    func outOfRangeNoop() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(2)
        vm.userSelectSession(0)
        vm.userSelectSession(vm.totalSessions + 1)
        #expect(vm.currentSession == 2)
    }

    @Test("Forward con timer corriendo sigue corriendo")
    func forwardWhileRunning() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(2)

        vm.userSelectSession(5)

        #expect(vm.isRunning == true)
        #expect(vm.currentSession == 5)
        #expect(Int(vm.debugSecondsRemainingForTest()) == vm.activeConfig.focus * 60)
    }

    @Test("Forward con timer pausado queda pausado")
    func forwardWhilePaused() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(false)
        vm.debugSetCurrentSessionForTest(2)
        vm.debugSetActiveForTest(true)

        vm.userSelectSession(5)

        #expect(vm.isRunning == false)
        #expect(vm.isActive == true)
        #expect(vm.currentSession == 5)
    }

    @Test("Forward con timer idle sigue idle (no arranca)")
    func forwardWhileIdle() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(2)
        // Sin tocar isRunning ni targetDate: idle.

        vm.userSelectSession(5)

        #expect(vm.isRunning == false)
        #expect(vm.isActive == false, "idle se mantiene idle")
        #expect(vm.currentSession == 5)
    }

    @Test("Backward con timer corriendo arranca corriendo")
    func backwardWhileRunning() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(4)

        vm.userSelectSession(2)

        #expect(vm.isRunning == true)
        #expect(vm.currentSession == 2)
    }

    @Test("Backward con timer pausado queda pausado")
    func backwardWhilePaused() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(false)
        vm.debugSetCurrentSessionForTest(4)
        vm.debugSetActiveForTest(true)

        vm.userSelectSession(2)

        #expect(vm.isRunning == false)
        #expect(vm.currentSession == 2)
    }
}

// MARK: - Sección B: skip después de cambio de sesión

@Suite("TimerViewModel — skip después de tap en barra")
@MainActor
struct TimerViewModelSkipAfterSelectTests {

    @Test("Tap forward 1→4 + skip natural → break de sesión 4")
    func forwardThenNaturalSkip() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(1)
        vm.userSelectSession(4)

        // Simula timer llegando a 0.
        let finished = vm.skipToNextPhase(wasCompleted: true)

        #expect(finished == false, "no debe cerrar el preset")
        #expect(vm.currentSession == 4)
        #expect(vm.isBreak == true, "debe estar en break de la sesión 4")
    }

    @Test("Tap forward 1→4 + skip manual → break de sesión 4 (marca presetHasSkip)")
    func forwardThenManualSkip() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(1)
        vm.userSelectSession(4)

        let finished = vm.skipToNextPhase(wasCompleted: false)

        #expect(finished == false)
        #expect(vm.currentSession == 4)
        #expect(vm.isBreak == true)
        #expect(vm.debugPresetHasSkipForTest() == true)
    }

    @Test("Tap backward 4→2 + skip natural → break de sesión 2")
    func backwardThenNaturalSkip() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(4)
        vm.userSelectSession(2)

        let finished = vm.skipToNextPhase(wasCompleted: true)

        #expect(finished == false)
        #expect(vm.currentSession == 2)
        #expect(vm.isBreak == true)
    }

    @Test("Tap forward a última sesión + skip natural → cierra preset con record válido")
    func forwardToLastThenNaturalSkipFinishes() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(1)
        vm.userSelectSession(vm.totalSessions)  // forward a la 5

        let finished = vm.skipToNextPhase(wasCompleted: true)

        #expect(finished == true, "última sesión completada debe cerrar")
        // La sesión 5 completada naturalmente debe tener record válido.
        let runId = vm.debugPresetRunIdForTest()
        let records = SessionStore.shared.records(forPresetRunId: runId)
        let s5 = records.first { $0.sessionNumber == vm.totalSessions }
        #expect(s5?.qualifiesForChips == true)
        // OJO: al terminar el preset, `currentSession` NO vuelve a 1
        // inmediatamente. Queda en la última sesión mientras se muestran
        // los popups (reward + summary). El reset a 1 ocurre 15s después
        // (rewardCleanupTask) o al dismiss de la recompensa.
        #expect(vm.currentSession == vm.totalSessions)
    }


    @Test("Tap forward a última sesión + skip manual → cierra sin acreditar")
        func forwardToLastThenManualSkipFinishesWithoutCredit() {
            let vm = makeVM()
            vm.debugSetCurrentSessionForTest(1)
            vm.userSelectSession(vm.totalSessions)
            // Capturar el runId ANTES del skip: un skip manual con
            // presetHasSkip = true ejecuta `resetToInitialState()`, que
            // regenera `currentPresetRunId`. Necesitamos el viejo para
            // verificar que sus records quedaron invalidadas.
            let runB = vm.debugPresetRunIdForTest()

            let finished = vm.skipToNextPhase(wasCompleted: false)

            #expect(finished == true)

            // A diferencia del skip natural, un skip manual SÍ dispara
            // `resetToInitialState()` de forma síncrona (vía
            // `markPresetInvalidated`). Así que currentSession vuelve a 1.
            #expect(vm.currentSession == 1, "skip manual resetea currentSession")

            // El run del forward debe estar totalmente invalidado.
            let bRecords = SessionStore.shared.records(forPresetRunId: runB)
            #expect(!bRecords.isEmpty)
            #expect(bRecords.allSatisfy { $0.presetInvalidated },
                    "todos los records del run inválido deben quedar marcados")
        }
}

// MARK: - Sección C: secuencias con múltiples taps + skip

@Suite("TimerViewModel — múltiples taps + skip")
@MainActor
struct TimerViewModelMultiSelectTests {

    @Test("Forward 1→4 + backward 4→2 (run nuevo) → skip va a 3")
    func forwardThenBackwardThenSkip() {
        let vm = makeVM()
        vm.debugSetCurrentSessionForTest(1)
        vm.userSelectSession(4)   // forward: nuevo run
        let newRunId = vm.debugPresetRunIdForTest()

        vm.userSelectSession(2)   // backward dentro del run nuevo
        #expect(vm.debugPresetRunIdForTest() == newRunId)

        let finished = vm.skipToNextPhase(wasCompleted: true)
        #expect(!finished)
        #expect(vm.currentSession == 2, "skip respeta la sesión 2 recién elegida")
        #expect(vm.isBreak)
    }

    @Test("Dos forward seguidos: cada uno regenera presetRunId")
    func twoForwardsRegenerate() {
        let vm = makeVM()
        let run0 = vm.debugPresetRunIdForTest()
        vm.userSelectSession(3)
        let run1 = vm.debugPresetRunIdForTest()
        #expect(run1 != run0)

        vm.userSelectSession(5)
        let run2 = vm.debugPresetRunIdForTest()
        #expect(run2 != run1)
    }

    @Test("Forward 1→3 + backward 3→2 + skip natural hasta última: acredita la corrida nueva")
    func mixedPathCredits() {
        let vm = makeVM()
        vm.userSelectSession(3)
        let runId = vm.debugPresetRunIdForTest()

        vm.userSelectSession(2)

        // Completar 2, 3, 4, 5 naturalmente.
        for _ in 1...4 {
            _ = vm.skipToNextPhase(wasCompleted: true)  // focus → break
            _ = vm.skipToNextPhase(wasCompleted: true)  // break → focus
        }
        let finished = vm.skipToNextPhase(wasCompleted: true)
        #expect(finished)

        let records = SessionStore.shared.records(forPresetRunId: runId)
        let valid = records.filter { $0.qualifiesForChips }
        // Sesiones 2, 3, 4, 5 completadas naturalmente en el run nuevo.
        #expect(Set(valid.map(\.sessionNumber)) == [2, 3, 4, 5])
    }

    @Test("Forward 1→3 + skip manual → invalida todo el run")
    func forwardThenManualSkipInvalidatesAll() {
        let vm = makeVM()
        // Completar sesión 1 (dentro del run actual).
        let originalRunId = vm.debugPresetRunIdForTest()
        SessionStore.shared.recordCompletedSession(
            presetName: vm.activeConfig.name,
            focusMinutes: vm.activeConfig.focus,
            sessionNumber: 1,
            totalSessions: vm.totalSessions,
            presetRunId: originalRunId
        )

        vm.userSelectSession(3)   // forward: nuevo run
        _ = vm.skipToNextPhase(wasCompleted: false)

        // Ir hasta el final saltando.
        while !vm.skipToNextPhase(wasCompleted: true) { /* avanza */ }

        // Ningún run acreditó nada.
        let oldRecords = SessionStore.shared.records(forPresetRunId: originalRunId)
        #expect(oldRecords.allSatisfy { $0.presetInvalidated })
    }
}

// MARK: - Sección D: interacción con reloj en funcionamiento

@Suite("TimerViewModel — select + skip con timer running")
@MainActor
struct TimerViewModelRunningTests {

    @Test("Tap forward con timer running: targetDate y isRunning se mantienen")
    func forwardRunningKeepsTimer() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(2)

        let beforeRunning = vm.isRunning
        vm.userSelectSession(4)
        let afterRunning = vm.isRunning

        #expect(beforeRunning == true)
        #expect(afterRunning == true)
        #expect(vm.currentSession == 4)
        #expect(vm.debugTargetDateForTest() != nil || !vm.isRunning, "targetDate debe setearse por startTicking")
    }

    @Test("Tap backward con timer running: targetDate y isRunning se mantienen")
    func backwardRunningKeepsTimer() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(4)

        vm.userSelectSession(2)

        #expect(vm.isRunning == true)
        #expect(vm.currentSession == 2)
    }

    @Test("Tap forward con timer running + skip natural: avanza al break de la nueva sesión")
    func forwardRunningThenSkip() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(2)
        vm.userSelectSession(4)

        let finished = vm.skipToNextPhase(wasCompleted: true)

        #expect(!finished)
        #expect(vm.currentSession == 4)
        #expect(vm.isBreak == true)
    }

    @Test("Tap backward con timer running + skip natural: avanza al break de la nueva sesión")
    func backwardRunningThenSkip() {
        let vm = makeVM()
        vm.debugSetIsRunningForTest(true)
        vm.debugSetCurrentSessionForTest(4)
        vm.userSelectSession(2)

        let finished = vm.skipToNextPhase(wasCompleted: true)

        #expect(!finished)
        #expect(vm.currentSession == 2)
        #expect(vm.isBreak == true)
    }
}
