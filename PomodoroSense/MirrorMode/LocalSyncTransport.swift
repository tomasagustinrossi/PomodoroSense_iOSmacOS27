//
//  LocalSyncTransport.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 15/10/2026.
//


import Foundation
import Network
import CryptoKit

/// Define la configuración de seguridad y transporte para la red P2P local.
enum LocalSyncTransport {
    
    /// El identificador del servicio Bonjour. Debe coincidir exactamente en ambos dispositivos.
    static let serviceType = "_pomodorosense._tcp"
    
    /// Genera los parámetros de red con TLS 1.3 y PSK (Pre-Shared Key) obligatorio.
    /// - Parameter passcode: El código de emparejamiento acordado entre los dispositivos.
    static func secureParameters(passcode: String) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2 // Detecta caídas de red rápidamente
        
        let tlsOptions = NWProtocolTLS.Options()
        
        // 1. Derivar una clave criptográfica fuerte a partir del passcode del usuario
        let psk = deriveKey(from: passcode)
        
        // 2. Configurar el Pre-Shared Key en las opciones de TLS de bajo nivel (sec_protocol)
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            DispatchData(data: psk) as __DispatchData,
            DispatchData(data: Data("PomodoroSense_PSK".utf8)) as __DispatchData
        )
        
        // 3. Forzar TLS 1.3 para máxima seguridad y eficiencia con PSK
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_AES_128_GCM_SHA256)!
        )
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
        
        // 4. Crear los parámetros combinando TLS y TCP
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        
        // Habilitamos soporte para redes locales peer-to-peer
        parameters.includePeerToPeer = true
        
        return parameters
    }
    
    /// Expande un simple código de texto en una clave simétrica robusta de 256 bits usando HKDF.
    private static func deriveKey(from passcode: String) -> Data {
        let inputKeyMaterial = SymmetricKey(data: Data(passcode.utf8))
        // El 'salt' añade entropía estática, y el 'info' vincula la clave a este contexto específico.
        let salt = Data("PomodoroSense_Salt_v1".utf8)
        let info = Data("PomodoroSense_TLS_Key".utf8)
        
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: info,
            outputByteCount: 32 // 256 bits
        )
        
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
