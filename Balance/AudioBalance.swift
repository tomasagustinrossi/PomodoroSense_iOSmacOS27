//
//  AudioBalance.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  AudioBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: BinauralManager, AudioManager.
//     La UI NUNCA accede directo.
//
//  Curvas de volumen, duraciones de fade y ganancias máximas.
//

import Foundation

nonisolated enum AudioBalance {

    // MARK: - Ganancias máximas

    /// Ganancia máxima del tono binaural (con slider en 1.0).
    /// Ej: 0.11 → el binaural más fuerte está al 11% del volumen digital.
    static let maxToneGain: Float = 0.11

    /// Ganancia máxima del ruido de color (con slider en 1.0).
    /// Ej: 0.30 → el ruido más fuerte está al 30% del volumen digital.
    static let maxNoiseGain: Float = 0.30

    // MARK: - Curvas de respuesta (slider → ganancia)

    /// Exponente de la curva del tono. > 1 = más resolución cerca de 0.
    /// Ej: 1.8 → slider 0.5 da ganancia 0.28x (no 0.5x).
    static let toneCurveExponent: Float = 1.8

    /// Exponente de la curva del ruido.
    /// Ej: 1.6 → slider 0.5 da ganancia 0.33x.
    static let noiseCurveExponent: Float = 1.6

    // MARK: - Duraciones de fade

    /// Fade-in al arrancar audio.
    /// Ej: 1.2s de fade-in perceptible.
    static let fadeInDuration: Float = 1.2

    /// Fade-out al pausar.
    /// Ej: 0.9s al pausar.
    static let pauseFadeDuration: Float = 0.9

    /// Fade-out al detener sesión.
    /// Ej: 1.6s al terminar la sesión completa.
    static let stopFadeDuration: Float = 1.6

    /// Fade-in/out muy rápido (cambio de preset con autoarranque).
    /// Ej: 0.15s para no solapar con el fade-in siguiente.
    static let quickFadeDuration: Float = 0.15

    // MARK: - Smoothing del renderer

    /// Constante de tiempo del suavizado de parámetros (tone difference, gains).
    /// Ej: 60 ms de smoothing evita clicks.
    static let parameterSmoothingSeconds: Float = 0.06

    /// Constante de tiempo del suavizado del ruido al cambiar de tipo.
    /// Ej: 120 ms de crossfade.
    static let noiseSmoothingSeconds: Float = 0.12

    // MARK: - Frecuencia base del binaural

    /// Frecuencia portadora del tono (afinación relajante).
    /// Ej: 432 Hz → base del binaural. La diferencia (40 Hz gamma)
    ///     se aplica sumando a este valor en el oído derecho.
    static let carrierFrequency: Float = 432

    // MARK: - Ambiente (archivos de audio)

    /// Volumen por defecto del slider de ruidos ambientales.
    static let defaultAmbienceVolume: Float = 0.65

    /// Fade de archivos de ambiente (streaming).
    static let ambienceFadeIn: TimeInterval = 1.4
    static let ambienceFadeOut: TimeInterval = 1.8
    static let ambiencePauseFade: TimeInterval = 0.9
}