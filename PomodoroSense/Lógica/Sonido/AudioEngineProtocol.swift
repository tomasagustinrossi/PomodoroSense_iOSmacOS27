//
//  AudioEngineProtocol.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//


protocol AudioEngineProtocol {
    // Control de Ambiente
    func playBackground(noiseId: Int, freqId: Int)
    func stopBackground()
    func pauseBackground() // Cuando pausan el timer
    
    // Control de Efectos
    func playSoundEffect(_ effect: AudioEffectType)
}

enum AudioEffectType {
    case tap       // Clic sutil de UI
    case sessionEnd // Campana/Gong de fin de focus
    case breakEnd   // Sonido enérgico para volver al trabajo
    case allDone    // Melodía de éxito al terminar las 4 sesiones
}