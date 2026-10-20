//
//  SyncPersistence.swift
//  PomodoroSense
//

import Foundation
import Security

/// Persistencia de identidad (peerId en Keychain) y preferencias
/// de recuperación de sesión.
///
/// ⚠️ Este archivo NO maneja el estado del Mirror Mode. El sistema de
/// sync P2P vive en `LocalSyncTransport` (Keychain propio) y
/// `LocalSyncEngine` (UserDefaults.standard con prefijo `localsync_`).
final class SyncPersistence {
    static let shared = SyncPersistence()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let resumeSessionOnRelaunch = "sync_resume_session_on_relaunch"
        static let resumePreMirrorSession  = "sync_resume_pre_mirror_session"
        // Migración v2: fuerza regeneración de peerId en cada device la
        // primera vez que corra esta versión. Necesario porque el bug de
        // IDs duplicados entre devices por backup/restore dejó a varios
        // pares con el mismo `myPeerId`.
        static let peerIdMigratedV2        = "sync_my_peer_id_v2_migrated"
        // Key legacy del peerId en UserDefaults (antes de Keychain).
        // Solo se usa en la migración v2 para saber si había datos viejos.
        static let legacyMyPeerId          = "sync_my_peer_id"
    }

    // MARK: - Keychain (peerId)

    private static let keychainService = "com.tomiirossi.PomodoroSense"
    private static let keychainAccount = "peerId"

    /// Cacheado en memoria para evitar hits al Keychain en cada acceso.
    private let _myPeerId: UUID

    private init() {
        if !defaults.bool(forKey: Keys.peerIdMigratedV2) {
            let hadOld = defaults.string(forKey: Keys.legacyMyPeerId) != nil
            defaults.removeObject(forKey: Keys.legacyMyPeerId)
            defaults.set(true, forKey: Keys.peerIdMigratedV2)
            if hadOld {
                print("🔧 [SyncPersistence] Reset de peerId (migración v2). Se generará uno nuevo en Keychain.")
            }
        }

        _myPeerId = Self.loadOrCreatePeerIdInKeychain()

        print("🔑 [SyncPersistence] myPeerId=\(_myPeerId.uuidString)")
    }

    // MARK: - Identidad

    var myPeerId: UUID { _myPeerId }

    // MARK: - Keychain helpers

    private static func loadOrCreatePeerIdInKeychain() -> UUID {
        if let existing = readPeerIdFromKeychain() { return existing }
        let new = UUID()
        savePeerIdToKeychain(new)
        return new
    }

    private static func readPeerIdFromKeychain() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              let id = UUID(uuidString: str) else {
            return nil
        }
        return id
    }

    private static func savePeerIdToKeychain(_ id: UUID) {
        let data = Data(id.uuidString.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    keychainAccount,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ [SyncPersistence] No se pudo guardar peerId en Keychain: \(status)")
        }
    }

    // MARK: - Recuperación de sesión

    var resumeSessionOnRelaunch: Bool {
        get {
            if defaults.object(forKey: Keys.resumeSessionOnRelaunch) == nil { return true }
            return defaults.bool(forKey: Keys.resumeSessionOnRelaunch)
        }
        set { defaults.set(newValue, forKey: Keys.resumeSessionOnRelaunch) }
    }

    var resumePreMirrorSession: Bool {
        get {
            if defaults.object(forKey: Keys.resumePreMirrorSession) == nil { return true }
            return defaults.bool(forKey: Keys.resumePreMirrorSession)
        }
        set { defaults.set(newValue, forKey: Keys.resumePreMirrorSession) }
    }

    // MARK: - Reset

    /// Limpia preferencias de recuperación. NO toca el peerId (Keychain)
    /// ni la key del pairing (`LocalSyncTransport` maneja su propia clave).
    func resetPreferences() {
        defaults.removeObject(forKey: knownPeersKey)
        defaults.removeObject(forKey: Keys.resumeSessionOnRelaunch)
        defaults.removeObject(forKey: Keys.resumePreMirrorSession)
    }
    
    private let knownPeersKey = "sync_known_peers"

    // MARK: - Peers conocidos

    var knownPeers: [KnownPeer] {
        get {
            guard let data = defaults.data(forKey: knownPeersKey),
                  let decoded = try? JSONDecoder().decode([KnownPeer].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: knownPeersKey)
            }
        }
    }

    func addOrUpdateKnownPeer(_ peer: KnownPeer) {
        var peers = knownPeers
        if let idx = peers.firstIndex(where: { $0.id == peer.id }) {
            // Preservar el nombre existente: si el usuario lo editó a mano,
            // no queremos pisarlo con el nombre que publica Bonjour.
            var updated = peer
            updated.name = peers[idx].name
            peers[idx] = updated
        } else {
            peers.append(peer)
        }
        knownPeers = peers
    }

    /// Renombra un peer existente. No toca el resto de sus campos.
    func renameKnownPeer(id: String, newName: String) {
        var peers = knownPeers
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        peers[idx].name = trimmed
        knownPeers = peers
    }

    func removeKnownPeer(id: String) {
        knownPeers = knownPeers.filter { $0.id != id }
    }
}
