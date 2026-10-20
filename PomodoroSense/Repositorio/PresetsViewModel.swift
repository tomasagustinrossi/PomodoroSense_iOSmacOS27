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
    
    // Inyección de la dependencia
    private let repository: PomodoroRepositoryProtocol
    
    private let defaultPresets: [PomodoroConfigDTO] = [
        PomodoroConfigDTO(name: "MORNING CODING", focus: 52, breakTime: 17, sessions: 4, audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1)),
        PomodoroConfigDTO(name: "QUICK READ", focus: 25, breakTime: 5, sessions: 2, audio: AudioConfigDTO(presetId: 2, noiseId: 2, freqId: 3)),
        PomodoroConfigDTO(name: "HEAVY DEBUGGING", focus: 90, breakTime: 20, sessions: 3, audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1))
    ]
    
    // El init exige un objeto que cumpla con el protocolo
    init(repository: PomodoroRepositoryProtocol) {
        self.repository = repository
        self.loadPresets()
    }
    
    // MARK: - Operaciones de Presentación (Business Logic pura)
    
    func loadPresets() {
        let loaded = repository.loadConfigs()
        if loaded.isEmpty {
            self.savedConfigs = defaultPresets
            persist()
        } else {
            self.savedConfigs = loaded
        }
    }
    
    func savePreset(_ newConfig: PomodoroConfigDTO) {
        if let index = savedConfigs.firstIndex(where: { $0.id == newConfig.id }) {
            savedConfigs[index] = newConfig
        } else {
            savedConfigs.append(newConfig)
        }
        persist()
    }
    
    func deletePreset(id: UUID) {
        savedConfigs.removeAll { $0.id == id }
        if savedConfigs.isEmpty {
            savedConfigs = defaultPresets
        }
        persist()
    }
    
    // Llama a la infraestructura de manera agnóstica
    private func persist() {
        repository.saveConfigs(savedConfigs)
    }
}
