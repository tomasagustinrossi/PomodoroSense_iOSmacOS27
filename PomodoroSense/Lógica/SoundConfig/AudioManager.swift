import AVFoundation
import Foundation

@MainActor
final class AudioManager: AudioEngineProtocol {
    static let shared = AudioManager()

    // MARK: - Subsistemas
    private let binauralManager = BinauralManager()

    // Motor dedicado SOLO al archivo de naturaleza (streaming + loop).
    // Separarlo del motor binaural permite fades independientes y evita que
    // el render callback del binaural tenga que lidiar con I/O de disco.
    private let natureEngine = AVAudioEngine()
    private let naturePlayerNode = AVAudioPlayerNode()
    private let natureMixer = AVAudioMixerNode()
    private var natureAudioFile: AVAudioFile?
    private var natureIsPrimed = false

    // SFX
    private var sfxPlayer: AVAudioPlayer?

    // Estado
    private var currentNoiseId: Int?
    private var currentFreqId: Int?

    // Fade
    private var natureFadeTimer: Timer?
    private var natureDesiredVolume: Float = AudioManager.defaultNatureSliderVolume

    // MARK: - Constantes
    /// Identificador de sonido de naturaleza. Mutuamente excluyente con colores 1–4.
    static let natureNoiseId = 5

    /// Nombre base del archivo. El usuario debe agregar `nature_ambience.mp3` al bundle.
    private static let natureFileBaseName = "nature_ambience"
    private static let natureFileExtension = "mp3"

    /// Valor por defecto del slider (0–1).
    static let defaultNatureSliderVolume: Float = 0.65

    private static let fadeInDuration: TimeInterval  = 1.4
    private static let fadeOutDuration: TimeInterval = 1.8
    private static let pauseFadeDuration: TimeInterval = 0.9

    private init() {
        configureAndActivateSession()
        setupNatureGraph()
        preloadNatureFile()
    }

    // MARK: - Sesión

    func configureAndActivateSession() {
        Task {
            do {
                try await AudioPlatform.activateSession(mixWithOthers: true, ioBuffer: 0.04)
            } catch {
                print("Error configurando/activando sesión: \(error.localizedDescription)")
            }
        }
    }

    func deactivateSession() {
        Task {
            do {
                try await AudioPlatform.deactivateSession()
            } catch {
                print("Error desactivando sesión: \(error.localizedDescription)")
            }
        }
    }

    func keepAppAlive(enable: Bool) {}

    // MARK: - Grafo de naturaleza

    private func setupNatureGraph() {
        natureEngine.attach(naturePlayerNode)
        natureEngine.attach(natureMixer)

        let sr = natureEngine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sr > 0 ? sr : 44_100, channels: 2)!

        natureEngine.connect(naturePlayerNode, to: natureMixer, format: format)
        natureEngine.connect(natureMixer, to: natureEngine.mainMixerNode, format: format)

        natureMixer.outputVolume = 0
        natureEngine.mainMixerNode.outputVolume = 1
    }

    private func preloadNatureFile() {
        guard let url = Bundle.main.url(
            forResource: Self.natureFileBaseName,
            withExtension: Self.natureFileExtension
        ) else {
            print("⚠️ nature_ambience.\(Self.natureFileExtension) no encontrado en el bundle.")
            return
        }

        do {
            // AVAudioFile hace streaming desde disco: NO carga las 2 h en RAM.
            natureAudioFile = try AVAudioFile(forReading: url)
        } catch {
            print("Error cargando sonido de naturaleza: \(error.localizedDescription)")
        }
    }

    /// Encola dos reproducciones del archivo y re-encola una cada vez que una termina.
    /// Resultado: loop continuo sin gap perceptible, con un solo nodo.
    private func primeNatureLoop() {
        guard let file = natureAudioFile else { return }
        scheduleChunk(file)
        scheduleChunk(file)
        natureIsPrimed = true
    }

    private func scheduleChunk(_ file: AVAudioFile) {
        naturePlayerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self = self, let f = self.natureAudioFile, self.natureIsPrimed else { return }
                self.scheduleChunk(f)
            }
        }
    }

    // MARK: - Reproducción de naturaleza

    private func playNatureSound() {
        guard natureAudioFile != nil else { return }

        if !natureIsPrimed { primeNatureLoop() }

        if !natureEngine.isRunning {
            do { try natureEngine.start() }
            catch {
                print("Error iniciando motor de naturaleza: \(error.localizedDescription)")
                return
            }
        }

        if !naturePlayerNode.isPlaying { naturePlayerNode.play() }

        fadeNatureVolume(to: natureDesiredVolume, duration: Self.fadeInDuration)
    }

    private func pauseNatureSound() {
        guard naturePlayerNode.isPlaying else { return }
        fadeNatureVolume(to: 0, duration: Self.pauseFadeDuration) { [weak self] in
            self?.naturePlayerNode.pause()
        }
    }

    private func stopNatureSound() {
        // Fast-path: si ya está silencioso, limpiamos sin animar.
        if natureMixer.outputVolume < 0.001 && !naturePlayerNode.isPlaying {
            naturePlayerNode.stop()
            natureIsPrimed = false
            return
        }

        fadeNatureVolume(to: 0, duration: Self.fadeOutDuration) { [weak self] in
            guard let self = self else { return }
            self.naturePlayerNode.stop()
            self.natureIsPrimed = false
        }
    }

    /// Fade lineal con easing smoothstep sobre `natureMixer.outputVolume`.
    /// No toca el render thread del binaural, así que no hay riesgo de glitches.
    private func fadeNatureVolume(
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        natureFadeTimer?.invalidate()

        let start = natureMixer.outputVolume
        let clamped = min(max(target, 0), 1)
        let startTime = Date()
        let stepInterval: TimeInterval = 1.0 / 60.0

        let timer = Timer(timeInterval: stepInterval, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }

            let elapsed = Date().timeIntervalSince(startTime)
            let raw = Float(min(elapsed / duration, 1.0))
            let eased = raw * raw * (3 - 2 * raw)   // smoothstep

            self.natureMixer.outputVolume = start + (clamped - start) * eased

            if raw >= 1.0 {
                t.invalidate()
                self.natureMixer.outputVolume = clamped
                completion?()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        natureFadeTimer = timer
    }

    // MARK: - SFX

    func playSFX(_ effect: SFX) {
        guard let url = getURL(for: effect.filename) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = effect.defaultVolume
            player.prepareToPlay()
            player.play()
            sfxPlayer = player
        } catch {
            print("Error SFX \(effect): \(error.localizedDescription)")
        }
    }

    // MARK: - Ecualizador

    func getNoiseVolume(id: Int) -> Float {
        let key = "vol_noise_\(id)"
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }
        switch id {
        case 1: return 0.70   // Marrón
        case 2: return 0.60   // Rosa
        case 3: return 0.40   // Blanco
        case 4: return 0.50   // Violeta
        case Self.natureNoiseId: return Self.defaultNatureSliderVolume
        default: return 0.50
        }
    }

    func getFreqVolume(id: Int) -> Float {
        let key = "vol_freq_\(id)"
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }
        switch id {
        case 1: return 0.15
        case 2: return 0.20
        case 3: return 0.25
        case 4: return 0.30
        default: return 0.20
        }
    }

    func setNoiseVolume(id: Int, volume: Float) {
        UserDefaults.standard.set(volume, forKey: "vol_noise_\(id)")
        guard currentNoiseId == id else { return }

        if id == Self.natureNoiseId {
            natureDesiredVolume = min(max(volume, 0), 1)
            // Si está sonando, reflejamos el cambio de inmediato (fade corto).
            if naturePlayerNode.isPlaying {
                fadeNatureVolume(to: natureDesiredVolume, duration: 0.15)
            }
        } else {
            binauralManager.setNoiseVolume(volume)
        }
    }

    func setFreqVolume(id: Int, volume: Float) {
        UserDefaults.standard.set(volume, forKey: "vol_freq_\(id)")
        guard currentFreqId == id else { return }
        binauralManager.setToneVolume(volume)
    }

    // MARK: - Ambiente (implementación del protocolo)

    func playBackground(noiseId: Int, freqId: Int) {
        // ¿Hay que cambiar el "color" del fondo?
        if noiseId == Self.natureNoiseId {
            playNatureSound()
        } else {
            stopNatureSound()
        }

        // Binaural: SIEMPRE va por encima de cualquier fondo (naturaleza o color).
        // Si `noiseId == 5`, le pasamos 0 al binaural para que NO genere color encima.
        if freqId != 0 {
            let binauralNoiseId = (noiseId == Self.natureNoiseId) ? 0 : noiseId
            binauralManager.play(
                noiseId: binauralNoiseId,
                brainwaveDifference: brainwaveDifference(for: freqId),
                noiseVolume: getNoiseVolume(id: noiseId),
                toneVolume: getFreqVolume(id: freqId)
            )
        } else if noiseId == Self.natureNoiseId {
            // Solo naturaleza, sin binaural: cortamos el binaural.
            binauralManager.stop()
        } else if noiseId == 0 {
            // Nada seleccionado.
            binauralManager.stop()
        } else {
            // Ruido de color sin binaural.
            binauralManager.play(
                noiseId: noiseId,
                brainwaveDifference: nil,
                noiseVolume: getNoiseVolume(id: noiseId),
                toneVolume: 0
            )
        }

        currentNoiseId = noiseId
        currentFreqId = freqId
    }

    func pauseBackground() {
        pauseNatureSound()
        binauralManager.pause()
    }

    func stopBackground() {
        stopNatureSound()
        binauralManager.stop()
        currentNoiseId = nil
        currentFreqId = nil
    }
    
    /// Detiene todo sin fade, útil cuando en el mismo ciclo se va a arrancar otro sonido.
    func stopBackgroundImmediate() {
        natureFadeTimer?.invalidate()
        natureMixer.outputVolume = 0
        naturePlayerNode.stop()
        natureIsPrimed = false
        binauralManager.stopImmediate()
        currentNoiseId = nil
        currentFreqId = nil
    }

    // MARK: - Helpers

    private func getURL(for filename: String) -> URL? {
        for ext in ["m4a", "mp3", "wav"] {
            if let url = Bundle.main.url(forResource: filename, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func brainwaveDifference(for id: Int) -> Float? {
        switch id {
        case 1: return 40   // Gamma  (~40 Hz)
        case 2: return 15   // Beta   (~15 Hz)
        case 3: return 10   // Alpha  (~10 Hz)
        case 4: return 6    // Theta  (~6 Hz)
        default: return nil
        }
    }
}
