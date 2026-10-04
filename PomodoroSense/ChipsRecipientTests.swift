//
//  ChipsRecipientTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("SyncPersistence — chipsRecipientDeviceId")
struct ChipsRecipientTests {

    @Test("Default es nil (master recibe)")
    func defaultIsNil() {
        SyncPersistence.shared.chipsRecipientDeviceId = nil
        #expect(SyncPersistence.shared.chipsRecipientDeviceId == nil)
    }

    @Test("Persiste un UUID")
    func persistsUUID() {
        let id = UUID()
        SyncPersistence.shared.chipsRecipientDeviceId = id
        #expect(SyncPersistence.shared.chipsRecipientDeviceId == id)
        // Cleanup
        SyncPersistence.shared.chipsRecipientDeviceId = nil
    }

    @Test("Setear nil limpia la persistencia")
    func nilClears() {
        SyncPersistence.shared.chipsRecipientDeviceId = UUID()
        SyncPersistence.shared.chipsRecipientDeviceId = nil
        #expect(SyncPersistence.shared.chipsRecipientDeviceId == nil)
    }
}