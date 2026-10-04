import Foundation

// MARK: - Efectos de Sonido (SFX) unificados

enum SFX: Equatable, Sendable {
    case uiClick
    case focusEnd
    case breakEnd
    case allDone
    case warning10s
    case countdown3s
    case countdown

    var filename: String {
        switch self {
        case .uiClick:      return "ui_click"
        case .focusEnd:     return "focus_complete"
        case .breakEnd:     return "break_complete"
        case .allDone:      return "all_done"
        case .warning10s:   return "warning_10s"
        case .countdown3s:  return "countdown_3s"
        case .countdown:    return "countdown"
        }
    }

    /// Ganancia por defecto para cada SFX (el countdown suena más suave).
    var defaultVolume: Float {
        switch self {
        case .countdown, .countdown3s, .warning10s: return 0.4
        default: return 0.8
        }
    }
}

// MARK: - Protocolo del motor de audio

@MainActor
protocol AudioEngineProtocol: AnyObject {
    /// Inicia la reproducción de ambiente. `noiseId == 5` corresponde al sonido de naturaleza
    /// (mutuamente excluyente con los ruidos de color 1–4). El binaural (`freqId`) puede
    /// superponerse a cualquiera de ellos.
    func playBackground(noiseId: Int, freqId: Int)
    func stopBackground()
    func pauseBackground()
    func playSFX(_ effect: SFX)
}
