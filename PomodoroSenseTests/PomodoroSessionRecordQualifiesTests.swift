//
//  PomodoroSessionRecordTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

private func make(
    minutes: Int,
    skipped: Bool = false,
    interrupted: Bool = false,
    quality: Int? = nil
) -> PomodoroSessionRecord {
    PomodoroSessionRecord(
        id: UUID(),
        ownerDeviceId: UUID(),
        dayStart: Date(),
        timestamp: Date(),
        presetName: "T",
        focusMinutes: minutes,
        sessionNumber: 1,
        totalSessions: 5,
        wasSkipped: skipped,
        wasInterrupted: interrupted,
        quality: quality
    )
}

@Suite("PomodoroSessionRecord — qualifiesForChips")
struct PomodoroSessionRecordQualifiesTests {

    @Test("Sesión completada califica para chips")
    func completedQualifies() {
        #expect(make(minutes: 30).qualifiesForChips == true)
    }

    @Test("Sesión salteada NO califica")
    func skippedDoesNotQualify() {
        #expect(make(minutes: 30, skipped: true).qualifiesForChips == false)
    }

    @Test("Sesión interrumpida NO califica")
    func interruptedDoesNotQualify() {
        #expect(make(minutes: 30, interrupted: true).qualifiesForChips == false)
    }

    @Test("skipped E interrupted tampoco califica")
    func skippedAndInterruptedDoesNotQualify() {
        #expect(make(minutes: 30, skipped: true, interrupted: true).qualifiesForChips == false)
    }
}

@Suite("PomodoroSessionRecord — effectiveQuality")
struct PomodoroSessionRecordQualityTests {

    @Test("Si quality está persistido, lo usa directo")
    func usesPersistedQuality() {
        let r = make(minutes: 60, quality: 3)
        #expect(r.effectiveQuality == 3)
    }

    @Test("Si quality es nil, lo calcula de los minutos")
    func computesQualityWhenNil() {
        // 60 min → quality 4 por los cortes de QualityBalance
        #expect(make(minutes: 60, quality: nil).effectiveQuality == 4)
        // 30 min → quality 2
        #expect(make(minutes: 30, quality: nil).effectiveQuality == 2)
        // 90 min → quality 5
        #expect(make(minutes: 90, quality: nil).effectiveQuality == 5)
        // 20 min → quality 1
        #expect(make(minutes: 20, quality: nil).effectiveQuality == 1)
        // 5 min → quality 0
        #expect(make(minutes: 5, quality: nil).effectiveQuality == 0)
    }
}

@Suite("PomodoroSessionRecord — Codable tolerante")
struct PomodoroSessionRecordCodingTests {

    @Test("Decode sin flags opcionales usa defaults")
    func decodeWithoutOptionalFlagsDefaults() throws {
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
        #expect(record.quality == nil)
        #expect(record.qualifiesForChips == true)
    }

    @Test("Decode sin ownerDeviceId asigna uno nuevo")
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
        #expect(record.presetName == "TEST")
    }

    @Test("Round-trip: quality persiste exacto")
    func qualityRoundTrip() throws {
        let original = make(minutes: 60, quality: 5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PomodoroSessionRecord.self, from: data)
        #expect(decoded.quality == 5)
        #expect(decoded.effectiveQuality == 5)
    }
}

@Suite("SessionQuality — cálculo de calidad")
struct SessionQualityTests {

    @Test("Cortes exactos del QualityBalance")
    func exactBoundaries() {
        // < 15 → 0
        #expect(SessionQuality.from(minutes: 0)  == 0)
        #expect(SessionQuality.from(minutes: 14) == 0)

        // 15–29 → 1
        #expect(SessionQuality.from(minutes: 15) == 1)
        #expect(SessionQuality.from(minutes: 29) == 1)

        // 30–44 → 2
        #expect(SessionQuality.from(minutes: 30) == 2)
        #expect(SessionQuality.from(minutes: 44) == 2)

        // 45–59 → 3
        #expect(SessionQuality.from(minutes: 45) == 3)
        #expect(SessionQuality.from(minutes: 59) == 3)

        // 60–89 → 4
        #expect(SessionQuality.from(minutes: 60) == 4)
        #expect(SessionQuality.from(minutes: 89) == 4)

        // 90+ → 5
        #expect(SessionQuality.from(minutes: 90)   == 5)
        #expect(SessionQuality.from(minutes: 5000) == 5)
    }

    @Test("Minutos negativos dan 0")
    func negativeMinutes() {
        #expect(SessionQuality.from(minutes: -5) == 0)
    }

    @Test("chipMultiplier por calidad")
    func chipMultiplierByQuality() {
        #expect(SessionQuality.chipMultiplier(for: 0) == 0.0)
        #expect(SessionQuality.chipMultiplier(for: 1) == 1.00)
        #expect(SessionQuality.chipMultiplier(for: 3) == 1.04)
        #expect(SessionQuality.chipMultiplier(for: 5) == 1.10)
    }

    @Test("label por calidad")
    func labels() {
        #expect(SessionQuality.label(for: 5) == "INTENSE")
        #expect(SessionQuality.label(for: 1) == "MINIMAL")
        #expect(SessionQuality.label(for: 0) == "—")
    }
}

@Suite("ScoreCalculator — sessionChipsWithQuality")
struct SessionChipsWithQualityTests {

    @Test("Calidad 1 no altera los chips base")
    func quality1NoChange() {
        // 60 min = 20 base; quality 1 → 1.00x → 20
        #expect(ScoreCalculator.sessionChipsWithQuality(forMinutes: 60, quality: 1) == 20)
    }

    @Test("Calidad 5 aplica 1.10x")
    func quality5AppliesBonus() {
        // 60 min = 20 base; quality 5 → 1.10x → 22
        #expect(ScoreCalculator.sessionChipsWithQuality(forMinutes: 60, quality: 5) == 22)
    }

    @Test("Sesión corta con calidad baja da 0")
    func shortLowQualityIsZero() {
        #expect(ScoreCalculator.sessionChipsWithQuality(forMinutes: 20, quality: 1) == 0)
    }
}

@Suite("DIAGNÓSTICO — valores reales de ScoreBalance")
struct ScoreBalanceDiagnostic {

    @Test("Ver qué valores están leyendo realmente")
    func diagnosticValues() {
        // Estos prints van a aparecer en la consola de tests.
        print("=== DIAGNÓSTICO ===")
        print("ScoreBalance.maxSessionMinutes: \(ScoreBalance.maxSessionMinutes)")
        print("ScoreBalance.minChipMinutes: \(ScoreBalance.minChipMinutes)")
        print("ScoreBalance.chipCurveBase: \(ScoreBalance.chipCurveBase)")
        print("ScoreBalance.chipCurveQuadratic: \(ScoreBalance.chipCurveQuadratic)")

        print("ScoreCalculator.maxSessionMinutes: \(ScoreCalculator.maxSessionMinutes)")
        print("ScoreCalculator.minChipMinutes: \(ScoreCalculator.minChipMinutes)")

        print("sessionChips(30): \(ScoreCalculator.sessionChips(forMinutes: 30))")
        print("sessionChips(60): \(ScoreCalculator.sessionChips(forMinutes: 60))")

        print("QualityBalance.chipMultiplier[1]: \(QualityBalance.chipMultiplier[1] ?? -999)")
        print("QualityBalance.chipMultiplier[5]: \(QualityBalance.chipMultiplier[5] ?? -999)")

        print("SessionQuality.chipMultiplier(for: 1): \(SessionQuality.chipMultiplier(for: 1))")
        print("SessionQuality.chipMultiplier(for: 5): \(SessionQuality.chipMultiplier(for: 5))")

        print("sessionChipsWithQuality(60, 1): \(ScoreCalculator.sessionChipsWithQuality(forMinutes: 60, quality: 1))")
        print("sessionChipsWithQuality(60, 5): \(ScoreCalculator.sessionChipsWithQuality(forMinutes: 60, quality: 5))")
        print("=== FIN DIAGNÓSTICO ===")
    }
}
