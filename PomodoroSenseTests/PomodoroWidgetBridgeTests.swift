//
//  PomodoroWidgetBridgeTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("PomodoroWidgetBridge — contrato de claves")
struct PomodoroWidgetBridgeTests {

    @Test("Las claves no cambiaron (evita regresiones silenciosas)")
    func keysAreStable() {
        // Si alguien cambia estas strings, se rompe la comunicación entre
        // el widget (que las escribe) y la app (que las lee). Este test
        // actúa como contrato.
        #expect(PomodoroWidgetBridge.commandKey == "WidgetCommand")
        #expect(PomodoroWidgetBridge.commandDateKey == "WidgetCommandDate")
    }

    @Test("El App Group ID es el correcto")
    func appGroupIdIsCorrect() {
        #expect(PomodoroSessionStore.appGroupId == "group.com.tomiirossi.PomodoroSense")
    }

    @Test("El TTL de comandos es 15 segundos")
    func commandTTL() {
        #expect(PomodoroWidgetBridge.commandTTL == 15)
    }
}