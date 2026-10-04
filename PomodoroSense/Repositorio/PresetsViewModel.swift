//
//  PresetsViewModel.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//


import Foundation
import Combine

class PresetsViewModel: ObservableObject {
    @Published var savedConfigs: [PomodoroConfigDTO] = []
    
    private let storageKey = "Pomodoro_Saved_Presets"
    
    // Presets inmutables de fábrica
    private let defaultPresets: [PomodoroConfigDTO] = [
        PomodoroConfigDTO(
            name: "MORNING CODING", focus: 52, breakTime: 17, sessions: 4,
            audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1)
        ),
        PomodoroConfigDTO(
            name: "QUICK READ", focus: 25, breakTime: 5, sessions: 2,
            audio: AudioConfigDTO(presetId: 2, noiseId: 2, freqId: 3)
        ),
        PomodoroConfigDTO(
            name: "HEAVY DEBUGGING", focus: 90, breakTime: 20, sessions: 3,
            audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1)
        )
    ]
    
    init() {
        loadPresets()
    }
    
    // MARK: - Operaciones CRUD
    
    func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PomodoroConfigDTO].self, from: data) else {
            // Si no hay datos (primer inicio), cargamos los defaults
            self.savedConfigs = defaultPresets
            return
        }
        self.savedConfigs = decoded
    }
    
    func savePreset(_ newConfig: PomodoroConfigDTO) {
        // Si el preset ya existe (por ID), lo actualiza. Si no, lo agrega.
        if let index = savedConfigs.firstIndex(where: { $0.id == newConfig.id }) {
            savedConfigs[index] = newConfig
        } else {
            savedConfigs.append(newConfig)
        }
        persistToDisk()
    }
    
    func deletePreset(id: UUID) {
        savedConfigs.removeAll { $0.id == id }
        
        // Evitamos que el usuario se quede sin presets por accidente
        if savedConfigs.isEmpty {
            savedConfigs = defaultPresets
        }
        persistToDisk()
    }
    
    // MARK: - Motor de Guardado
    
    private func persistToDisk() {
        if let encoded = try? JSONEncoder().encode(savedConfigs) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}