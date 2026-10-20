//
//  LiveActivityFilterReusableTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 20/10/2026.
//


//
//  LiveActivityFilterTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

// MARK: - Reusabilidad de la isla de Pomodoro (bug A1)

@Suite("LiveActivityFilter — isReusablePomodoro")
struct LiveActivityFilterReusableTests {

    @Test("Activity activa de Pomodoro → reusable")
    func activePomodoroIsReusable() {
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: true, isStale: false, isFreeMode: false
        ) == true)
    }

    @Test("Activity STALE de Pomodoro → reusable (este era el bug A1)")
    func stalePomodoroIsReusable() {
        // Antes del fix: (isActive || isStale) no existía; solo .active.
        // El reward público pasa a .stale a los 15s y creaba isla nueva.
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: false, isStale: true, isFreeMode: false
        ) == true)
    }

    @Test("Activity activa de Free Mode → NO reusable por Pomodoro")
    func activeFreeModeNotReusable() {
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: true, isStale: false, isFreeMode: true
        ) == false)
    }

    @Test("Activity stale de Free Mode → NO reusable por Pomodoro")
    func staleFreeModeNotReusable() {
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: false, isStale: true, isFreeMode: true
        ) == false)
    }

    @Test("Activity dismissed (ni active ni stale) → NO reusable")
    func dismissedNotReusable() {
        // activityState == .dismissed o .ended. Hay que crear una nueva.
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: false, isStale: false, isFreeMode: false
        ) == false)
    }

    @Test("Combinación imposible (dismissed + Free Mode) → NO reusable")
    func dismissedFreeModeNotReusable() {
        #expect(LiveActivityFilter.isReusablePomodoro(
            isActive: false, isStale: false, isFreeMode: true
        ) == false)
    }
}

// MARK: - Cierre selectivo (bugs A2, A3)

@Suite("LiveActivityFilter — shouldEndAll")
struct LiveActivityFilterShouldEndTests {

    // ── filter == nil → cerrar TODAS ──

    @Test("filter nil → cierra Pomodoro")
    func nilFilterEndsPomodoro() {
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: nil) == true)
    }

    @Test("filter nil → cierra Free Mode")
    func nilFilterEndsFreeMode() {
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: nil) == true)
    }

    // ── filter == false → solo Pomodoro ──

    @Test("filter false → cierra Pomodoro (es el default para StopTimer)")
    func falseFilterEndsPomodoro() {
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: false) == true)
    }

    @Test("filter false → NO cierra Free Mode (bug A2)")
    func falseFilterKeepsFreeMode() {
        // Antes: stopLiveActivity/stopTimerIntent cerraban TODAS las islas.
        // Con el fix, cerrar Pomodoro deja intacta la de Free Mode.
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: false) == false)
    }

    // ── filter == true → solo Free Mode ──

    @Test("filter true → cierra Free Mode")
    func trueFilterEndsFreeMode() {
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: true) == true)
    }

    @Test("filter true → NO cierra Pomodoro")
    func trueFilterKeepsPomodoro() {
        #expect(LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: true) == false)
    }

    // ── Escenario end-to-end de bugs A2/A3 ──

    @Test("Escenario A2: DismissReward no mata isla de Free Mode")
    func dismissRewardKeepsFreeMode() {
        // DismissRewardIntent llama endAll(freeMode: false).
        // Simulamos: hay 1 isla de Pomodoro + 1 de Free Mode.
        let pomodoro = LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: false)
        let freeMode = LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: false)

        #expect(pomodoro == true, "la isla de Pomodoro SÍ se cierra")
        #expect(freeMode == false, "la isla de Free Mode NO se cierra")
    }

    @Test("Escenario A3: StopTimer no mata isla de Free Mode")
    func stopTimerKeepsFreeMode() {
        let pomodoro = LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: false)
        let freeMode = LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: false)

        #expect(pomodoro == true)
        #expect(freeMode == false)
    }

    @Test("Escenario: StopFreeMode no mata isla de Pomodoro")
    func stopFreeModeKeepsPomodoro() {
        // StopFreeModeIntent llama endAll(freeMode: true).
        let pomodoro = LiveActivityFilter.shouldEndAll(isFreeMode: false, filter: true)
        let freeMode = LiveActivityFilter.shouldEndAll(isFreeMode: true, filter: true)

        #expect(pomodoro == false, "la isla de Pomodoro NO se cierra")
        #expect(freeMode == true, "la isla de Free Mode SÍ se cierra")
    }
}