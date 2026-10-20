//
//  MirroredToDeviceIdsTests.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 13/10/2026.
//


//
//  MirroredRecordsTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

private func makeRecord(
    owner: UUID,
    mirroredTo: Set<UUID> = []
) -> PomodoroSessionRecord {
    PomodoroSessionRecord(
        id: UUID(),
        ownerDeviceId: owner,
        dayStart: Date(),
        timestamp: Date(),
        presetName: "T",
        focusMinutes: 30,
        sessionNumber: 1,
        totalSessions: 5,
        mirroredToDeviceIds: mirroredTo
    )
}

@Suite("PomodoroSessionRecord — mirroredToDeviceIds")
struct MirroredToDeviceIdsTests {

    @Test("Default es conjunto vacío")
    func defaultEmpty() {
        let me = UUID()
        let r = makeRecord(owner: me)
        #expect(r.mirroredToDeviceIds.isEmpty)
    }

    @Test("Codable round-trip preserva el set")
    func codableRoundTrip() throws {
        let peer = UUID()
        let r = makeRecord(owner: UUID(), mirroredTo: [peer])

        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(PomodoroSessionRecord.self, from: data)

        #expect(decoded.mirroredToDeviceIds == [peer])
    }

    @Test("Decode de JSON viejo (sin el campo) usa default vacío")
    func legacyJSONDefaultsToEmpty() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "ownerDeviceId": "00000000-0000-0000-0000-000000000002",
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
        #expect(record.mirroredToDeviceIds.isEmpty)
    }

    @Test("isRemoteOnly true cuando no es mío ni compartido")
    func isRemoteOnlyTrue() {
        let me = UUID()
        let other = UUID()
        let r = makeRecord(owner: other, mirroredTo: [])
        #expect(r.isRemoteOnly(forMyPeerId: me) == true)
    }

    @Test("isRemoteOnly false cuando es mío")
    func isRemoteOnlyFalseWhenMine() {
        let me = UUID()
        let r = makeRecord(owner: me, mirroredTo: [])
        #expect(r.isRemoteOnly(forMyPeerId: me) == false)
    }

    @Test("isRemoteOnly false cuando fui co-dueño (compartido)")
    func isRemoteOnlyFalseWhenShared() {
        let me = UUID()
        let other = UUID()
        let r = makeRecord(owner: other, mirroredTo: [me])
        #expect(r.isRemoteOnly(forMyPeerId: me) == false)
    }
}