//
//  SavedPresetsKeyboardTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("SavedPresetsKeyboard — cycle (Tab)")
struct SavedPresetsCycleTests {

    @Test("Desde nil, forward arranca en presetList")
    func nilForwardStartsAtList() {
        let next = SavedPresetsKeyboard.cycle(from: nil, forward: true)
        #expect(next == .presetList)
    }

    @Test("Desde nil, backward arranca en navPlus")
    func nilBackwardStartsAtPlus() {
        let next = SavedPresetsKeyboard.cycle(from: nil, forward: false)
        #expect(next == .navPlus)
    }

    @Test("Ciclo completo hacia adelante")
    func forwardCycle() {
        var current: SavedPresetsFocus? = .presetList
        current = SavedPresetsKeyboard.cycle(from: current, forward: true)
        #expect(current == .navSearch)
        current = SavedPresetsKeyboard.cycle(from: current, forward: true)
        #expect(current == .navStats)
        current = SavedPresetsKeyboard.cycle(from: current, forward: true)
        #expect(current == .navSync)
        current = SavedPresetsKeyboard.cycle(from: current, forward: true)
        #expect(current == .navPlus)
        current = SavedPresetsKeyboard.cycle(from: current, forward: true)
        #expect(current == .presetList, "Vuelve al inicio")
    }

    @Test("Ciclo hacia atrás")
    func backwardCycle() {
        var current: SavedPresetsFocus? = .presetList
        current = SavedPresetsKeyboard.cycle(from: current, forward: false)
        #expect(current == .navPlus, "Desde el primero va al último")
        current = SavedPresetsKeyboard.cycle(from: current, forward: false)
        #expect(current == .navSync)
    }

    @Test("Tab desde cada zona no se traba")
    func everyZoneHasNext() {
        for zone in SavedPresetsFocus.cycleOrder {
            let next = SavedPresetsKeyboard.cycle(from: zone, forward: true)
            #expect(next != zone, "El ciclo desde \(zone) no puede devolver lo mismo")
        }
    }
}

@Suite("SavedPresetsKeyboard — enterAction")
struct SavedPresetsEnterTests {

    @Test("Enter en cada zona dispara la acción correcta")
    func enterRoutesCorrectly() {
        #expect(SavedPresetsKeyboard.enterAction(for: .navSearch) == .toggleSearch)
        #expect(SavedPresetsKeyboard.enterAction(for: .navStats) == .showStats)
        #expect(SavedPresetsKeyboard.enterAction(for: .navSync) == .showSync)
        #expect(SavedPresetsKeyboard.enterAction(for: .navPlus) == .newPreset)
    }

    @Test("Enter en la lista arranca el preset")
    func enterOnListStartsPreset() {
        #expect(SavedPresetsKeyboard.enterAction(for: .presetList) == .startSelectedPreset)
    }

    @Test("Enter sin foco explícito arranca el preset")
    func enterNilStartsPreset() {
        #expect(SavedPresetsKeyboard.enterAction(for: nil) == .startSelectedPreset)
    }
}

@Suite("SavedPresetsKeyboard — spaceAction")
struct SavedPresetsSpaceTests {

    @Test("Con timer activo, Space togglea el timer (sin importar foco)")
    func activeTimerAlwaysToggles() {
        for zone in SavedPresetsFocus.cycleOrder {
            let action = SavedPresetsKeyboard.spaceAction(
                isTimerActive: true,
                focusedZone: zone
            )
            #expect(action == .toggleTimer,
                    "Con timer activo y foco en \(zone), debe togglear")
        }
    }

    @Test("Sin timer, Space en la lista arranca el preset")
    func idleSpaceOnListStartsPreset() {
        let action = SavedPresetsKeyboard.spaceAction(
            isTimerActive: false,
            focusedZone: .presetList
        )
        #expect(action == .startSelectedPreset)
    }

    @Test("Sin timer, Space en la navbar no hace nada")
    func idleSpaceOnNavbarDoesNothing() {
        for zone in [SavedPresetsFocus.navSearch, .navStats, .navSync, .navPlus] {
            let action = SavedPresetsKeyboard.spaceAction(
                isTimerActive: false,
                focusedZone: zone
            )
            #expect(action == .none,
                    "Sin timer y foco en \(zone), Space debe ser no-op")
        }
    }
}

@Suite("SavedPresetsKeyboard — movePresetIndex")
struct SavedPresetsMoveTests {

    @Test("Avanza de 0 a 1")
    func advanceFromZero() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 0, count: 3, offset: 1) == 1)
    }

    @Test("Retrocede de 1 a 0")
    func backFromOne() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 1, count: 3, offset: -1) == 0)
    }

    @Test("Wrap adelante: del último al primero")
    func wrapForward() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 2, count: 3, offset: 1) == 0)
    }

    @Test("Wrap atrás: del primero al último")
    func wrapBackward() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 0, count: 3, offset: -1) == 2)
    }

    @Test("Desde nil, +1 va al primero")
    func nilForwardStartsFirst() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: nil, count: 3, offset: 1) == 0)
    }

    @Test("Desde nil, -1 va al último")
    func nilBackwardStartsLast() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: nil, count: 3, offset: -1) == 2)
    }

    @Test("Count 0 → nil (no crashea)")
    func emptyReturnsNil() {
        #expect(SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 0, count: 0, offset: 1) == nil)
    }

    @Test("Index fuera de rango se trata como nil")
    func outOfRangeTreatedAsNil() {
        let forward = SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 99, count: 3, offset: 1)
        #expect(forward == 0, "99 no es válido: se comporta como nil (arranca en 0)")

        let backward = SavedPresetsKeyboard.movePresetIndex(
            currentIndex: 99, count: 3, offset: -1)
        #expect(backward == 2, "99 no es válido con -1: arranca en el último")
    }

    @Test("Ciclo completo con count 5")
    func fullCycle() {
        var idx: Int? = 0
        for _ in 0..<5 {
            idx = SavedPresetsKeyboard.movePresetIndex(
                currentIndex: idx, count: 5, offset: 1)
        }
        #expect(idx == 0, "Después de 5 saltos vuelve al inicio")
    }
}