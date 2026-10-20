//
//  LocalSyncTransport.swift
//  PomodoroSense
//

import Foundation
import Network
import Security
import CryptoKit

enum LocalSyncTransport {

    static let serviceType = "_pomodorosense._tcp"

    /// Alfabeto del pairing code: sin 0/O/1/I/L para evitar confusión
    /// al copiar/pegar a mano.
    static let pairingAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    /// 16 chars de un alfabeto de 31 → ~79 bits de entropía.
    /// Formateado como XXXX-XXXX-XXXX-XXXX.
    static let pairingCodeLength = 16

    private static let pskIdentity = Data("PomodoroSense_PSK".utf8)
    private static let keychainService = "com.tomiirossi.PomodoroSense.localsync"
    private static let keychainAccount = "pairing-key"

    enum TransportError: Error {
        case keychain(OSStatus)
        case invalidPairingCode
        case randomGenerationFailed
    }

    // MARK: - Generación / canonicalización

    /// Genera un pairing code nuevo (solo lo usa el Master al iniciar
    /// una sesión de "SHARE THIS TIMER").
    static func generatePairingCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: pairingCodeLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw TransportError.randomGenerationFailed
        }
        let alphabet = Array(pairingAlphabet)
        let chars = bytes.map { alphabet[Int($0) % alphabet.count] }
        return format(String(chars))
    }

    /// Canonicaliza un código pegado por el usuario.
    /// Acepta con o sin guiones, mayúsculas o minúsculas.
    /// Devuelve `nil` si el resultado no tiene 16 chars válidos.
    static func canonicalize(_ raw: String) -> String? {
        let upper = raw.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let allowed = Set(pairingAlphabet)
        let filtered = upper.filter { allowed.contains($0) }
        guard filtered.count == pairingCodeLength else { return nil }
        return String(filtered)
    }

    private static func format(_ raw: String) -> String {
        var out = ""
        for (i, ch) in raw.enumerated() {
            if i > 0 && i % 4 == 0 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    // MARK: - Derivación de PSK

    /// Deriva la PSK desde el código YA canonicalizado (16 chars sin guiones).
    /// 10.000 iteraciones de SHA256 para encarecer el brute force offline
    /// (el código viaja por QR o por portapapeles, no es secreto per se).
    static func derivePSK(fromCanonical canonical: String) -> SymmetricKey {
        var current = Data(canonical.utf8)
        for _ in 0..<10_000 {
            current = Data(SHA256.hash(data: current))
        }
        // Log temporal para verificar que la clave es la misma en ambos dispositivos.
        #if DEBUG
        let hash = SHA256.hash(data: current)
        let hex = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        print("🔑 [Transport] PSK derivada (fingerprint): \(hex)")
        #endif
        return SymmetricKey(data: current)
    }

    /// Punto único de entrada: toma un código crudo (con o sin guiones,
    /// como lo escriba el usuario o lo lea el QR), lo canonicaliza, y
    /// devuelve la PSK. Lanza si el código es inválido.
    static func derivePSK(fromRaw raw: String) throws -> SymmetricKey {
        guard let canonical = canonicalize(raw) else {
            throw TransportError.invalidPairingCode
        }
        return derivePSK(fromCanonical: canonical)
    }

    // MARK: - Parámetros de red

    static func secureParameters(key: SymmetricKey) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3

        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions

        let pskData = key.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData }
        let identityData = pskIdentity.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData }
        sec_protocol_options_add_pre_shared_key(secOptions, pskData, identityData)

        // ✅ Cifrado correcto para PSK
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(secOptions, suite)
        }
        // En lugar de .TLSv13, probá con .TLSv12
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        return parameters
    }

    // MARK: - Persistencia de PSK (Keychain)

    static func savePSK(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TransportError.keychain(status) }
    }

    static func loadPSK() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw TransportError.keychain(status)
        }
    }

    static func resetPairing() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
