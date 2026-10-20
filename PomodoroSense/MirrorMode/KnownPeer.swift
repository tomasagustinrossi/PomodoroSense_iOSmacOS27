//
//  KnownPeer.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 15/10/2026.
//


//
//  KnownPeer.swift
//  PomodoroSense
//

import Foundation

/// Dispositivo emparejado alguna vez. Persistido en UserDefaults.
struct KnownPeer: Codable, Identifiable, Hashable {
    /// Identidad natural: el pairingCode canonicalizado (16 chars, sin guiones).
    /// Dos devices son el mismo peer si comparten código.
    var id: String { pairingCode }

    var name: String              // "MacBook de Tomás"
    var pairingCode: String       // canonicalizado, sin guiones
    var lastRole: LocalSyncRole   // NUESTRO rol la última vez que conectamos
    var lastConnected: Date

    var roleLabel: String {
        lastRole == .master ? "MASTER" : "MIRROR"
    }

    var lastConnectedLabel: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: lastConnected, relativeTo: Date())
    }
}