//
//  TimerSetupKeyboardTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("TimerSetupKeyboard — cycle")
struct TimerSetupCycleTests {

    @Test("Ciclo completo hacia adelante desde name")
    func fullForwardCycle() {
        var zone: TimerSetupZone = .name
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .focus)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .breakTime)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .sessions)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .preset)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .sound)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .waves)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .save)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: true)
        #expect(zone == .name, "Vuelve al inicio después de save")
    }

    @Test("Ciclo hacia atrás desde name va a save")
    func backwardFromNameGoesToSave() {
        let zone = TimerSetupKeyboard.cycle(from: .name, forward: false)
        #expect(zone == .save)
    }

    @Test("Ciclo hacia atrás completo")
    func fullBackwardCycle() {
        var zone: TimerSetupZone = .save
        zone = TimerSetupKeyboard.cycle(from: zone, forward: false)
        #expect(zone == .waves)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: false)
        #expect(zone == .sound)
        zone = TimerSetupKeyboard.cycle(from: zone, forward: false)
        #expect(zone == .preset)
    }

    @Test("Ninguna zona se traba al ciclar forward")
    func noZoneStallsForward() {
        for z in TimerSetupZone.cycleOrder {
            let next = TimerSetupKeyboard.cycle(from: z, forward: true)
            #expect(next != z, "Ciclo desde \(z) devolvió lo mismo")
        }
    }

    @Test("Ninguna zona se traba al ciclar backward")
    func noZoneStallsBackward() {
        for z in TimerSetupZone.cycleOrder {
            let prev = TimerSetupKeyboard.cycle(from: z, forward: false)
            #expect(prev != z, "Ciclo backward desde \(z) devolvió lo mismo")
        }
    }

    @Test("Forward seguido de backward vuelve al inicio")
    func forwardBackwardRoundTrip() {
        for z in TimerSetupZone.cycleOrder {
            let forward = TimerSetupKeyboard.cycle(from: z, forward: true)
            let back = TimerSetupKeyboard.cycle(from: forward, forward: false)
            #expect(back == z, "Round-trip falló en \(z)")
        }
    }
}

@Suite("TimerSetupKeyboard — movePickerIndex")
struct TimerSetupPickerTests {

    @Test("Avanza dentro del rango")
    func advanceWithinRange() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 3, offset: 1) == 1)
        #expect(TimerSetupKeyboard.movePickerIndex(current: 1, count: 3, offset: 1) == 2)
    }

    @Test("Wrap hacia adelante: del último al primero")
    func wrapForward() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 2, count: 3, offset: 1) == 0)
    }

    @Test("Wrap hacia atrás: del primero al último")
    func wrapBackward() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 3, offset: -1) == 2)
    }

    @Test("Count 0 devuelve 0 sin crashear")
    func emptyReturnsZero() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 0, offset: 1) == 0)
        #expect(TimerSetupKeyboard.movePickerIndex(current: 5, count: 0, offset: -1) == 0)
    }

    @Test("Count 1 siempre devuelve 0")
    func singleItemStaysAtZero() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 1, offset: 1) == 0)
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 1, offset: -1) == 0)
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 1, offset: 5) == 0)
    }

    @Test("Offset 0 no mueve")
    func zeroOffsetNoMove() {
        #expect(TimerSetupKeyboard.movePickerIndex(current: 2, count: 5, offset: 0) == 2)
    }

    @Test("Ciclo completo con count 4")
    func fullCycle() {
        var idx = 0
        for _ in 0..<4 {
            idx = TimerSetupKeyboard.movePickerIndex(current: idx, count: 4, offset: 1)
        }
        #expect(idx == 0)
    }

    @Test("Offset grande envuelve bien")
    func largeOffsetWraps() {
        // 7 movimientos en count 3 → 7 % 3 = 1
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 3, offset: 7) == 1)
        // -7 en count 3 → -7 % 3 = -1 → 2
        #expect(TimerSetupKeyboard.movePickerIndex(current: 0, count: 3, offset: -7) == 2)
    }
}

@Suite("TimerSetupKeyboard — clampNumeric")
struct TimerSetupClampTests {

    @Test("Suma dentro del rango")
    func increaseInRange() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 30, offset: 1, range: 1...60) == 31)
    }

    @Test("Resta dentro del rango")
    func decreaseInRange() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 30, offset: -1, range: 1...60) == 29)
    }

    @Test("Clampea al tope superior")
    func clampsUpper() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 60, offset: 1, range: 1...60) == 60)
        #expect(TimerSetupKeyboard.clampNumeric(value: 59, offset: 5, range: 1...60) == 60)
    }

    @Test("Clampea al tope inferior")
    func clampsLower() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 1, offset: -1, range: 1...60) == 1)
        #expect(TimerSetupKeyboard.clampNumeric(value: 3, offset: -10, range: 1...60) == 1)
    }

    @Test("Offset 0 no cambia")
    func zeroOffsetNoChange() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 30, offset: 0, range: 1...60) == 30)
    }

    @Test("Rango 1...40 respeta sus topes")
    func sessionsRange() {
        #expect(TimerSetupKeyboard.clampNumeric(value: 40, offset: 1, range: 1...40) == 40)
        #expect(TimerSetupKeyboard.clampNumeric(value: 1, offset: -1, range: 1...40) == 1)
        #expect(TimerSetupKeyboard.clampNumeric(value: 20, offset: 1, range: 1...40) == 21)
    }

    @Test("Value fuera de rango se clampea al primer offset")
    func outOfRangeValueClamps() {
        // Value 0 fuera de rango: con +1 queda 1 (dentro).
        #expect(TimerSetupKeyboard.clampNumeric(value: 0, offset: 1, range: 1...60) == 1)
        // Value 100 fuera: con -1 → 99 → clamp a 60.
        #expect(TimerSetupKeyboard.clampNumeric(value: 100, offset: -1, range: 1...60) == 60)
    }
}