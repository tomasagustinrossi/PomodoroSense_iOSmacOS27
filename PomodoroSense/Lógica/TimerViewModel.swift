//
//  TimerViewModel.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//


import Foundation
import Combine
import SwiftUI

// El ViewModel es responsable EXCLUSIVO de la mutación de estado.
// Se adhiere a ObservableObject para que SwiftUI pueda reaccionar a @Published.
class TimerViewModel: ObservableObject {
    
    // MARK: - Estado Público (Solo lectura para la View)
    @Published var isRunning: Bool = false
    @Published var isBreak: Bool = false
    @Published var progress: CGFloat = 0.0
    @Published var currentSession: Int = 1
    @Published var totalSessions: Int = 1
    
    // El texto formateado se procesa aquí, no en la View, aislando la lógica de formato.
    @Published var timeRemainingString: String = "00:00" 
    
    // MARK: - Estado Privado (Core Engine)
    private var activeConfig: PomodoroConfigDTO?
    private var totalSecondsForCurrentPhase: Int = 0
    private var secondsRemaining: Int = 0
    
    // Referencia al Timer de Foundation
    private var timerCancellable: AnyCancellable?
    
    // MARK: - Intenciones (Intents de la UI)
    
    /// Se llama cuando el usuario selecciona un Preset y navega a la pantalla principal.
    func loadConfiguration(_ config: PomodoroConfigDTO) {
        self.activeConfig = config
        self.totalSessions = config.sessions
        self.currentSession = 1
        self.isBreak = false
        
        setupPhase()
    }
    
    /// Alterna el estado de ejecución (Play/Pause)
    func toggleTimer() {
        isRunning.toggle()
        if isRunning {
            startTicking()
        } else {
            stopTicking()
        }
    }
    
    /// Avanza a la siguiente fase (Focus -> Break o Break -> Next Focus)
    func skipToNextPhase() {
        stopTicking()
        
        if isBreak {
            // Estaba en descanso, pasa a trabajo (si no terminó todo)
            if currentSession < totalSessions {
                currentSession += 1
                isBreak = false
            } else {
                // Fin del ciclo Pomodoro
                isRunning = false
                return
            }
        } else {
            // Estaba trabajando, pasa a descanso
            isBreak = true
        }
        
        setupPhase()
        if isRunning { startTicking() } // Auto-reanudar si estaba corriendo
    }
    
    func skipToPreviousPhase() {
        // Lógica de retroceso a implementar (evaluar si retrocede la fase o reinicia el contador actual)
    }
    
    // MARK: - Motor Interno
    
    private func setupPhase() {
        guard let config = activeConfig else { return }
        
        // Convertimos los minutos del DTO a segundos (multiplicamos por 60 en producción, por 1 o 2 para testing rápido)
        totalSecondsForCurrentPhase = (isBreak ? config.breakTime : config.focus) * 60
        secondsRemaining = totalSecondsForCurrentPhase
        
        updateUIState()
    }
    
    private func startTicking() {
        // Evitamos múltiples subscripciones
        timerCancellable?.cancel()
        
        // Un timer de precisión acoplado al RunLoop principal
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTick()
            }
    }
    
    private func stopTicking() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func handleTick() {
        if secondsRemaining > 0 {
            secondsRemaining -= 1
            updateUIState()
        } else {
            skipToNextPhase()
        }
    }
    
    private func updateUIState() {
        // Cálculo del progreso circular invertido (1.0 a 0.0)
        progress = totalSecondsForCurrentPhase > 0 
            ? CGFloat(secondsRemaining) / CGFloat(totalSecondsForCurrentPhase) 
            : 0.0
        
        // Formateo de String (Ej: "28:06")
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        timeRemainingString = String(format: "%02d:%02d", minutes, seconds)
    }
}