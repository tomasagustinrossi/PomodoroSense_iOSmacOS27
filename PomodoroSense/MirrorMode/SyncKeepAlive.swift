//
//  SyncKeepAlive.swift
//  PomodoroSense
//
//  Mantiene viva la app en segundo plano (solo iOS) mientras hay una sesión de sync
//  Master/Mirror activa, para que el socket siga entregando mensajes y la Live Activity
//  se actualice en el momento.
//
//  POR QUÉ: iOS suspende la app unos segundos después de pasar a segundo plano. Suspendida,
//  no recibe nada por la red: la isla del Mirror queda con el `targetDate` viejo y su contador
//  (que dibuja el sistema, no la app) sigue corriendo aunque el Master ya pausó.
//
//  CÓMO: un motor de audio dedicado que reproduce un buffer de SILENCIO en loop. Necesita
//  `UIBackgroundModes → audio` en el Info.plist (el mismo que ya usa el ruido de fondo).
//  Es independiente de `AudioManager` (no toca su ambiente ni sus binaurales).
//
import AVFoundation

@MainActor
final class SyncKeepAlive {

    static let shared = SyncKeepAlive()

    private var requested = false

    #if os(iOS)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var graphBuilt = false
    private var observers: [NSObjectProtocol] = []
    #endif

    private init() {}

    /// Idempotente. `true` mientras haya una sesión de sync conectada o reconectando.
    func setEnabled(_ enabled: Bool) {
        #if os(iOS)
        guard enabled != requested else { return }
        requested = enabled
        enabled ? start() : stop()
        #endif
    }

    #if os(iOS)

    private func buildGraphIfNeeded() {
        guard !graphBuilt else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(44_100)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        // Silencio explícito: no dependemos de que la memoria venga en cero.
        if let channel = buffer.floatChannelData?[0] {
            channel.update(repeating: 0, count: Int(frames))
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops)

        // Si el sistema reconfigura el audio (cambio de ruta, llamada…), reiniciamos.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartIfRequested() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            Task { @MainActor in self?.restartIfRequested() }
        })

        graphBuilt = true
    }

    private func start() {
        Task { @MainActor in
            // Misma sesión (.playback + mixWithOthers) que usa AudioManager: no corta la música del usuario.
            try? await AudioPlatform.activateSession(mixWithOthers: true, ioBuffer: 0.04)
            guard requested else { return }   // lo apagaron mientras activábamos la sesión

            buildGraphIfNeeded()
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                if !player.isPlaying { player.play() }
                #if DEBUG
                print("🫀 [KeepAlive] activo")
                #endif
            } catch {
                print("⚠️ [KeepAlive] no pudo iniciar: \(error.localizedDescription)")
            }
        }
    }

    private func stop() {
        player.pause()
        if engine.isRunning { engine.stop() }
        #if DEBUG
        print("🫀 [KeepAlive] detenido")
        #endif
    }

    private func restartIfRequested() {
        guard requested else { return }
        stop()
        start()
    }

    #endif
}