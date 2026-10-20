//
//  PomodoroRepositoryProtocol.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//


import Foundation

// 1. El Contrato (Inversión de Control)
protocol PomodoroRepositoryProtocol {
    func loadConfigs() -> [PomodoroConfigDTO]
    func saveConfigs(_ configs: [PomodoroConfigDTO])
}

// 2. La Implementación Concreta (Infraestructura)
class UserDefaultsPomodoroRepository: PomodoroRepositoryProtocol {
    private let storageKey = "Pomodoro_Saved_Presets"
    
    func loadConfigs() -> [PomodoroConfigDTO] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("💾 [Repo] 0 bytes encontrados (Primer inicio).")
            return []
        }
        
        do {
            let decoded = try JSONDecoder().decode([PomodoroConfigDTO].self, from: data)
            print("💾 [Repo] CARGA EXITOSA: \(decoded.count) presets leídos.")
            return decoded
        } catch {
            // AQUÍ SALTARÁ EL ERROR SI TUS DTOs NO SON 100% CODABLE
            print("🚨 [Repo ERROR CRÍTICO DE LECTURA]: \(error)")
            return []
        }
    }
    
    func saveConfigs(_ configs: [PomodoroConfigDTO]) {
        do {
            let encoded = try JSONEncoder().encode(configs)
            UserDefaults.standard.set(encoded, forKey: storageKey)
            print("💾 [Repo] GUARDADO EXITOSO: \(configs.count) presets escritos en disco.")
        } catch {
            // AQUÍ SALTARÁ EL ERROR SI HAY ALGÚN TIPO INCOMPATIBLE EN TUS STRUCTS
            print("🚨 [Repo ERROR CRÍTICO DE ESCRITURA]: \(error)")
        }
    }
}
