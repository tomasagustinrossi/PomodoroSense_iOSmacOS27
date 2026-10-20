//
//  TestLock.swift
//  PomodoroSenseTests
//
//  Lock global para serializar tests que acceden a UserDefaults.standard.
//  Necesario porque varias suites escriben/leen las mismas keys y corren
//  en paralelo. Reemplaza a `.serialized` (no soportado en esta versión de
//  Swift Testing).
//

import Foundation

/// Lock compartido por todas las suites que tocan UserDefaults.standard.
nonisolated let testDefaultsLock = NSLock()

/// Ejecuta un bloque con el lock tomado. Helper para no repetir
/// `lock()/defer { unlock() }` en cada test.
nonisolated func withDefaultsLock<T>(_ body: () throws -> T) rethrows -> T {
    testDefaultsLock.lock()
    defer { testDefaultsLock.unlock() }
    return try body()
}
