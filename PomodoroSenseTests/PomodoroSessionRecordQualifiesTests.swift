//
//  PomodoroSessionRecordQualifiesTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  PomodoroSessionRecordTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("PomodoroSessionRecord — qualifiesForChips")
struct PomodoroSessionRecordQualifiesTests {

    private func make(
        skipped: Bool = false,
        interrupted: Bool = false
    ) -> PomodoroSessionRecord {
        PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: UUID(),
            dayStart: Date(),
            timestamp: Date(),
            presetName: "T",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5,
            wasSkipped: skipped,
            wasInterrupted: interrupted
        )
    }

    @Test("Sesión completada califica para chips")
    func completedQualifies() {
        #expect(make().qualifiesForChips == true)
    }

    @Test("Sesión salteada NO califica")
    func skippedDoesNotQualify() {
        #expect(make(skipped: true).qualifiesForChips == false)
    }

    @Test("Sesión interrumpida NO califica")
    func interruptedDoesNotQualify() {
        #expect(make(interrupted: true).qualifiesForChips == false)
    }

    @Test("Sesión marcada como skipped E interrupted tampoco califica")
    func skippedAndInterruptedDoesNotQualify() {
        #expect(make(skipped: true, interrupted: true).qualifiesForChips == false)
    }
}

@Suite("PomodoroSessionRecord — Codable tolerante")
struct PomodoroSessionRecordCodingTests {

    @Test("Decode sin wasSkipped/wasInterrupted usa default false")
    func decodeWithoutOptionalFlagsDefaults() throws {
        // JSON con solo los campos mínimos. Los flags nuevos
        // (wasSkipped, wasInterrupted) faltan → deben defaultear.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "dayStart": 1700000000,
            "timestamp": 1700000000,
            "presetName": "TEST",
            "focusMinutes": 30,
            "sessionNumber": 1,
            "totalSessions": 5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let record = try decoder.decode(PomodoroSessionRecord.self, from: json)

        #expect(record.wasSkipped == false)
        #expect(record.wasInterrupted == false)
        #expect(record.qualifiesForChips == true)
    }

    @Test("Decode sin ownerDeviceId asigna uno nuevo (migración)")
    func decodeWithoutOwnerDeviceIdGeneratesOne() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "dayStart": 1700000000,
            "timestamp": 1700000000,
            "presetName": "TEST",
            "focusMinutes": 30,
            "sessionNumber": 1,
            "totalSessions": 5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let record = try decoder.decode(PomodoroSessionRecord.self, from: json)

        // No debe fallar; debe asignar un UUID nuevo.
        // No podemos comparar con un valor específico, solo verificar que no crashea.
        #expect(record.presetName == "TEST")
    }
}