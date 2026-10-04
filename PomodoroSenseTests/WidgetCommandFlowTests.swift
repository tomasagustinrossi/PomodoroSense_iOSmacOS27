//
//  WidgetCommandFlowTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  WidgetCommandFlowTests.swift
//  PomodoroSenseTests
//
//  Tests de la lógica de "leer + limpiar + validar" un comando del widget.
//  No toca el ViewModel real: solo el flujo de UserDefaults que replica
//  lo que hace `handleWidgetCommand` en TimerViewModel.
//

import Testing
import Foundation
@testable import PomodoroSense

/// Helper que crea un UserDefaults aislado que simula el App Group.
private func makeIsolatedAppGroup() -> (UserDefaults, String) {
    let suiteName = "Test.AppGroup.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
}

/// Replica la lógica de lectura del comando para testear de forma aislada.
/// Si en el futuro cambia el orden en `handleWidgetCommand`, este helper
/// debe actualizarse.
private func readCommand(from defaults: UserDefaults) -> String? {
    guard let command = defaults.string(forKey: PomodoroWidgetBridge.commandKey) else {
        return nil
    }

    let sentAt = defaults.double(forKey: PomodoroWidgetBridge.commandDateKey)

    // Limpieza
    defaults.removeObject(forKey: PomodoroWidgetBridge.commandKey)
    defaults.removeObject(forKey: PomodoroWidgetBridge.commandDateKey)

    // Validación TTL
    guard sentAt > 0,
          Date().timeIntervalSince1970 - sentAt < PomodoroWidgetBridge.commandTTL else {
        return nil
    }

    return command
}

@Suite("Widget → App — flujo de comandos")
struct WidgetCommandFlowTests {

    @Test("Comando reciente se lee y limpia")
    func recentCommandIsReadAndCleared() {
        let (defaults, suite) = makeIsolatedAppGroup()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set("TOGGLE", forKey: PomodoroWidgetBridge.commandKey)
        defaults.set(Date().timeIntervalSince1970, forKey: PomodoroWidgetBridge.commandDateKey)

        let result = readCommand(from: defaults)

        #expect(result == "TOGGLE")
        #expect(defaults.string(forKey: PomodoroWidgetBridge.commandKey) == nil,
                "El comando debe limpiarse después de leerlo")
        #expect(defaults.double(forKey: PomodoroWidgetBridge.commandDateKey) == 0,
                "El timestamp también debe limpiarse")
    }

    @Test("Comando viejo (más de 15s) se descarta")
    func oldCommandIsDiscarded() {
        let (defaults, suite) = makeIsolatedAppGroup()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // Hace 30 segundos
        let oldTimestamp = Date().timeIntervalSince1970 - 30

        defaults.set("STOP", forKey: PomodoroWidgetBridge.commandKey)
        defaults.set(oldTimestamp, forKey: PomodoroWidgetBridge.commandDateKey)

        let result = readCommand(from: defaults)

        #expect(result == nil, "Comando viejo debe descartarse")
        #expect(defaults.string(forKey: PomodoroWidgetBridge.commandKey) == nil,
                "Igual debe limpiarse para no procesarlo más adelante")
    }

    @Test("Sin comando pendiente no pasa nada")
    func noCommandReturnsNil() {
        let (defaults, suite) = makeIsolatedAppGroup()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let result = readCommand(from: defaults)

        #expect(result == nil)
    }

    @Test("Leer dos veces seguidas solo procesa una vez")
    func commandIsConsumedOnce() {
        let (defaults, suite) = makeIsolatedAppGroup()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set("SKIP", forKey: PomodoroWidgetBridge.commandKey)
        defaults.set(Date().timeIntervalSince1970, forKey: PomodoroWidgetBridge.commandDateKey)

        let first  = readCommand(from: defaults)
        let second = readCommand(from: defaults)

        #expect(first == "SKIP")
        #expect(second == nil, "La segunda lectura debe ser nil")
    }

    @Test("Timestamp 0 o negativo descarta el comando (seguridad)")
    func zeroTimestampIsRejected() {
        let (defaults, suite) = makeIsolatedAppGroup()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set("TOGGLE", forKey: PomodoroWidgetBridge.commandKey)
        defaults.set(0.0, forKey: PomodoroWidgetBridge.commandDateKey)

        let result = readCommand(from: defaults)

        #expect(result == nil)
    }
}