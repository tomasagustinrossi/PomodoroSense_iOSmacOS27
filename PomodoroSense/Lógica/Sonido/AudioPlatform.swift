import AVFoundation

/// Aísla todo lo que existe solo en iOS/tvOS/watchOS (AVAudioSession).
/// En macOS no hay sesión de audio: el sistema maneja el dispositivo de salida solo.
enum AudioPlatform {

    /// Configura y activa la sesión. En macOS no hace nada.
    static func activateSession(mixWithOthers: Bool = true,
                                ioBuffer: TimeInterval = 0.04) throws {
        #if os(macOS)
        // Sin AVAudioSession en macOS.
        #else
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback,
                                mode: .default,
                                options: mixWithOthers ? [.mixWithOthers] : [])
        try session.setPreferredIOBufferDuration(ioBuffer)
        try session.setActive(true)
        #endif
    }

    static func deactivateSession() throws {
        #if os(macOS)
        // Nada que hacer.
        #else
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Sample rate real de la salida (en macOS se lee del propio motor).
    static func hardwareSampleRate(for engine: AVAudioEngine) -> Double {
        #if os(macOS)
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        #else
        let sr = AVAudioSession.sharedInstance().sampleRate
        #endif
        return sr > 0 ? sr : 44100
    }

    /// En macOS no se puede saber de forma simple: se asume true para no bloquear la UI.
    static var headphonesConnected: Bool {
        #if os(macOS)
        return true
        #else
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio].contains($0.portType)
        }
        #endif
    }
}