//
//  SyncPersistenceTogglesTests.swift
//  PomodoroSenseTests
//

import Testing
import Foundation
@testable import PomodoroSense

@Suite("SyncPersistence — perillas M3/M4")
struct SyncPersistenceTogglesTests {

    // ⚠️ Todos los tests de esta suite tocan la MISMA key de UserDefaults.
    // Swift Testing corre en paralelo, así que sin el lock hay race
    // conditions (un test remueve la key mientras otro la lee).

    @Test("M3 default es true")
    func m3DefaultIsTrue() {
        withDefaultsLock {
            UserDefaults.standard.removeObject(forKey: "sync_resume_session_on_relaunch")
            #expect(SyncPersistence.shared.resumeSessionOnRelaunch == true)
        }
    }

    @Test("M4 default es true")
    func m4DefaultIsTrue() {
        withDefaultsLock {
            UserDefaults.standard.removeObject(forKey: "sync_resume_pre_mirror_session")
            #expect(SyncPersistence.shared.resumePreMirrorSession == true)
        }
    }

    @Test("M3 persiste false")
    func m3PersistsFalse() {
        withDefaultsLock {
            SyncPersistence.shared.resumeSessionOnRelaunch = false
            #expect(SyncPersistence.shared.resumeSessionOnRelaunch == false)
            // Cleanup
            SyncPersistence.shared.resumeSessionOnRelaunch = true
        }
    }

    @Test("M4 persiste false")
    func m4PersistsFalse() {
        withDefaultsLock {
            SyncPersistence.shared.resumePreMirrorSession = false
            #expect(SyncPersistence.shared.resumePreMirrorSession == false)
            // Cleanup
            SyncPersistence.shared.resumePreMirrorSession = true
        }
    }

    @Test("M3 vuelve a true tras setearlo")
    func m3RoundTrip() {
        withDefaultsLock {
            SyncPersistence.shared.resumeSessionOnRelaunch = false
            #expect(SyncPersistence.shared.resumeSessionOnRelaunch == false)
            SyncPersistence.shared.resumeSessionOnRelaunch = true
            #expect(SyncPersistence.shared.resumeSessionOnRelaunch == true)
        }
    }
}
