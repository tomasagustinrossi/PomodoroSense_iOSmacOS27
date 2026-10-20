//
//  ScoreBalanceTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  BalanceContractTests.swift
//  PomodoroSenseTests
//
//  Verifica que los valores de balance son los esperados.
//  Actúa como documentación viva + guard contra cambios accidentales.
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("Balance — SyncBalance")
struct SyncBalanceTests {

    @Test("Comandos del widget")
    func widgetCommands() {
        #expect(SyncBalance.widgetCommandTTL == 15)
    }
}
