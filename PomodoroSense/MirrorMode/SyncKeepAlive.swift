//
//  SyncKeepAlive.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


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
    private var reasons = Set<String>()
    
    func setEnabled(_ enabled: Bool, reason: String = "sync") {
        #if os(iOS)
        if enabled { reasons.insert(reason) } else { reasons.remove(reason) }
        let shouldRun = !reasons.isEmpty
        guard shouldRun != requested else { return }
        requested = shouldRun
        shouldRun ? start() : stop()
        #endif
    }

    private var requested = false

    #if os(iOS)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var graphBuilt = false
    /// Buffer de silencio. Se vuelve a programar en cada arranque: no dependemos de que
    /// el player conserve su cola después de `engine.stop()`.
    private var silence: AVAudioPCMBuffer?
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
        do {
            // iOS/macOS 27: `connect(_:to:format:)` quedó deprecado; la versión nueva lanza.
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        } catch {
            print("⚠️ [KeepAlive] no pudo conectar el grafo: \(error.localizedDescription)")
            engine.detach(player)
            return
        }
        silence = buffer

        // Si el sistema reconfigura el audio (cambio de ruta, llamada…), reiniciamos.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartIfRequested() }
        })
        // iOS 27: `interruptionNotification` (y `InterruptionType`) quedó deprecada. La nueva
        // `resumptionRecommendationNotification` se publica cuando termina una interrupción.
        // Reiniciamos siempre (como antes con `.ended`): el keep-alive es silencio, no hay
        // motivo para respetar un "shouldNotResume" pensado para audio audible.
        observers.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartIfRequested() }
        })

        graphBuilt = true
    }

    private func start() {
        Task { @MainActor in
            // Misma sesión (.playback + mixWithOthers) que usa AudioManager: no corta la música del usuario.
            try? await AudioPlatform.activateSession(mixWithOthers: true, ioBuffer: 0.04)
            guard requested else { return }   // lo apagaron mientras activábamos la sesión

            buildGraphIfNeeded()
            guard graphBuilt else { return }
            do {
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                if !player.isPlaying {
                    // Cola limpia + silencio en loop: evita acumular buffers duplicados.
                    player.stop()
                    scheduleSilenceLoop()
                    // iOS/macOS 27: `play()` quedó deprecado; la versión nueva lanza.
                    try player.playAudio()
                }
                #if DEBUG
                print("🫀 [KeepAlive] activo")
                #endif
            } catch {
                print("⚠️ [KeepAlive] no pudo iniciar: \(error.localizedDescription)")
            }
        }
    }

    /// Función SÍNCRONA a propósito: dentro de un `Task`/contexto async, Swift elegiría la
    /// variante `async` de `scheduleBuffer`, que no retorna hasta que el buffer termina de
    /// sonar (con `.loops`, nunca) y colgaría el arranque. Con `completionHandler:` explícito
    /// se usa siempre la versión con callback.
    private func scheduleSilenceLoop() {
        guard let silence else { return }
        player.scheduleBuffer(silence, at: nil, options: .loops, completionHandler: nil)
    }

    private func stop() {
        player.stop()
        if engine.isRunning { engine.stop() }
        #if DEBUG
        print("🫀 [KeepAlive] detenido")
        #endif
    }

    private func restartIfRequested() {
        guard requested else { return }
        if engine.isRunning && player.isPlaying { return }
        start()
    }

    #endif
}
