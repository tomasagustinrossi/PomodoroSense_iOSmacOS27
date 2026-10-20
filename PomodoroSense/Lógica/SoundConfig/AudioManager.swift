import AVFoundation
import Foundation

@MainActor
final class AudioManager: AudioEngineProtocol {
    static let shared = AudioManager()

    // MARK: - Subsistemas
    private let binauralManager = BinauralManager()

    // Motor dedicado a los archivos de ambiente (streaming + loop).
    private let ambienceEngine = AVAudioEngine()
    private let ambiencePlayerNode = AVAudioPlayerNode()
    private let ambienceMixer = AVAudioMixerNode()
    private var loadedFiles: [Int: AVAudioFile] = [:]     // cache por soundId
    private var currentAmbienceId: Int?                    // qué archivo está sonando
    private var ambienceIsPrimed = false
    private var ownedBGPlayer: AVAudioPlayer?
    private var shopBGPlayer: AVAudioPlayer?

    // SFX: un player por efecto, reutilizado (antes se creaba y decodificaba uno en cada disparo,
    // incluido el countdown que suena cada segundo en los últimos 10 s).
    private var sfxPlayers: [String: AVAudioPlayer] = [:]

    // Estado
    private var currentNoiseId: Int?
    private var currentFreqId: Int?

    // Fade
    private var ambienceFadeTimer: Timer?
    private var ambienceDesiredVolume: Float = AudioManager.defaultAmbienceSliderVolume
    var isTimerAudioPlaying: Bool {
            return binauralManager.isPlaying || ambiencePlayerNode.isPlaying
        }

    // MARK: - Constantes
    static let defaultAmbienceSliderVolume: Float = 0.65
    private static let ambienceFileExtension = "m4a"

    private static var fadeInDuration: TimeInterval    { AudioBalance.ambienceFadeIn }
    private static var fadeOutDuration: TimeInterval   { AudioBalance.ambienceFadeOut }
    private static var pauseFadeDuration: TimeInterval { AudioBalance.ambiencePauseFade }

    /// Valor por defecto del slider (0–1).
    static var defaultNatureSliderVolume: Float { AudioBalance.defaultAmbienceVolume }

    /// Nombre base del archivo. El usuario debe agregar `nature_ambience.m4a` al bundle.
    private static let natureFileBaseName = "nature_ambience"
    private static let natureFileExtension = "m4a"

    private init() {
        configureAndActivateSession()
        setupAmbienceGraph()
        // Nota: ya no preload. Los archivos se cargan on-demand.
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

    // MARK: - Grafo

    private func setupAmbienceGraph() {
        ambienceEngine.attach(ambiencePlayerNode)
        ambienceEngine.attach(ambienceMixer)

        let sr = ambienceEngine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sr > 0 ? sr : 44_100, channels: 2)!

        do {
            // iOS/macOS 27: `connect(_:to:format:)` quedó deprecado; la versión nueva lanza.
            try ambienceEngine.connectNode(ambiencePlayerNode, to: ambienceMixer, format: format)
            try ambienceEngine.connectNode(ambienceMixer, to: ambienceEngine.mainMixerNode, format: format)
        } catch {
            print("Error conectando el grafo de ambiente: \(error.localizedDescription)")
        }

        ambienceMixer.outputVolume = 0
        ambienceEngine.mainMixerNode.outputVolume = 1
    }

    /// `AVAudioPlayerNode.play()` quedó deprecado en 27; `playAudio()` lanza.
    @discardableResult
    private func startAmbiencePlayer() -> Bool {
        do {
            try ambiencePlayerNode.playAudio()
            return true
        } catch {
            print("Error iniciando el player de ambiente: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Carga de archivos (lazy + cache)

    private func loadFile(for soundId: Int) -> AVAudioFile? {
        if let cached = loadedFiles[soundId] { return cached }

        guard let fileName = AmbientSound.from(id: soundId).fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: Self.ambienceFileExtension) else {
            print("⚠️ Archivo '\(AmbientSound.from(id: soundId).fileName ?? "?")' no encontrado en el bundle.")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)  // streaming, no carga a RAM
            loadedFiles[soundId] = file
            return file
        } catch {
            print("Error cargando \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Encola dos reproducciones del archivo y re-encola una cada vez que una termina.
    /// Resultado: loop continuo sin gap perceptible, con un solo nodo.
    private func primeAmbienceLoop(soundId: Int) {
        scheduleChunk(soundId: soundId)
        scheduleChunk(soundId: soundId)
        ambienceIsPrimed = true
    }

    private func scheduleChunk(soundId: Int) {
        guard let file = loadedFiles[soundId] else { return }
        ambiencePlayerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.ambienceIsPrimed,
                      self.currentAmbienceId == soundId else { return }
                self.scheduleChunk(soundId: soundId)
            }
        }
    }

    // MARK: - Reproducción de naturaleza

    private func playAmbience(soundId: Int) {
        guard loadFile(for: soundId) != nil else { return }

        // Mismo sonido ya sonando → sólo resumimos si estaba pausado.
        if soundId == currentAmbienceId && ambienceIsPrimed {
            if !ambienceEngine.isRunning {
                do { try ambienceEngine.start() }
                catch {
                    print("Error reiniciando motor de ambiente: \(error.localizedDescription)")
                    return
                }
            }
            if !ambiencePlayerNode.isPlaying { startAmbiencePlayer() }
            fadeAmbienceVolume(to: ambienceDesiredVolume, duration: Self.fadeInDuration)
            return
        }

        // Cambio de sonido: paramos el anterior y empezamos el nuevo.
        ambiencePlayerNode.stop()
        ambienceIsPrimed = false
        currentAmbienceId = soundId
        primeAmbienceLoop(soundId: soundId)

        if !ambienceEngine.isRunning {
            do { try ambienceEngine.start() }
            catch {
                print("Error iniciando motor de ambiente: \(error.localizedDescription)")
                return
            }
        }

        guard startAmbiencePlayer() else { return }
        fadeAmbienceVolume(to: ambienceDesiredVolume, duration: Self.fadeInDuration)
    }

    private func pauseAmbience() {
        guard ambiencePlayerNode.isPlaying else { return }
        fadeAmbienceVolume(to: 0, duration: Self.pauseFadeDuration) { [weak self] in
            guard let self = self else { return }
            self.ambiencePlayerNode.pause()
            // Paramos el engine: en pausa no hay razón para mantener los
            // buffers y threads activos. Se reconstruye en el próximo play.
            if self.ambienceEngine.isRunning {
                self.ambienceEngine.stop()
            }
        }
    }

    private func stopAmbience() {
        if ambienceMixer.outputVolume < 0.001 && !ambiencePlayerNode.isPlaying {
            ambiencePlayerNode.stop()
            ambienceIsPrimed = false
            currentAmbienceId = nil
            // Parar el engine entero: libera recursos.
            if ambienceEngine.isRunning {
                ambienceEngine.stop()
            }
            return
        }

        fadeAmbienceVolume(to: 0, duration: Self.fadeOutDuration) { [weak self] in
            guard let self = self else { return }
            self.ambiencePlayerNode.stop()
            self.ambienceIsPrimed = false
            self.currentAmbienceId = nil
            // Parar el engine tras el fade-out.
            if self.ambienceEngine.isRunning {
                self.ambienceEngine.stop()
            }
        }
    }

    private func stopAmbienceImmediate() {
        ambienceFadeTimer?.invalidate()
        ambienceFadeTimer = nil
        ambienceMixer.outputVolume = 0
        ambiencePlayerNode.stop()
        ambienceIsPrimed = false
        currentAmbienceId = nil
        // Antes el engine quedaba corriendo en vacío (consumo de CPU/batería sin sonido).
        if ambienceEngine.isRunning {
            ambienceEngine.stop()
        }
    }

    // MARK: - Fade

    private func fadeAmbienceVolume(to target: Float,
                                    duration: TimeInterval,
                                    completion: (() -> Void)? = nil) {
        ambienceFadeTimer?.invalidate()

        let start = ambienceMixer.outputVolume
        let clamped = min(max(target, 0), 1)
        let startTime = Date()
        // 30 Hz alcanza para un fade de volumen (es inaudible la diferencia) y gasta la mitad.
        let stepInterval: TimeInterval = 1.0 / 30.0

        let timer = Timer(timeInterval: stepInterval, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            let raw = Float(min(elapsed / duration, 1.0))
            let eased = raw * raw * (3 - 2 * raw)  // smoothstep

            self.ambienceMixer.outputVolume = start + (clamped - start) * eased
            if raw >= 1.0 {
                t.invalidate()
                self.ambienceMixer.outputVolume = clamped
                completion?()
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        ambienceFadeTimer = timer
    }


    func playSFX(_ effect: SFX) {
        guard let url = getURL(for: effect.filename) else { return }

        Task.detached(priority: .userInitiated) {
            try? await AudioPlatform.activateSession(mixWithOthers: true, ioBuffer: 0.04)

            await MainActor.run {
                do {
                    let player: AVAudioPlayer
                    if let cached = self.sfxPlayers[effect.filename] {
                        player = cached
                    } else {
                        player = try AVAudioPlayer(contentsOf: url)
                        player.prepareToPlay()
                        self.sfxPlayers[effect.filename] = player
                    }
                    
                    // Leer el volumen global (por defecto 0.8 si no existe)
                    let globalSFXVolume = UserDefaults.standard.object(forKey: "sfx_volume") as? Float ?? 0.8
                    
                    player.volume = effect.defaultVolume * globalSFXVolume
                    player.currentTime = 0
                    player.play()
                } catch {
                    print("Error SFX \(effect): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Ecualizador/Volumen

    func getNoiseVolume(id: Int) -> Float {
        let key = "vol_noise_\(id)"
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }
        switch AmbientSound.from(id: id) {
        case .brown:  return 0.70
        case .pink:   return 0.60
        case .white:  return 0.40
        case .violet: return 0.50
        case .nature, .rain, .ocean, .classicalMusic, .fireplace:
            return Self.defaultAmbienceSliderVolume
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

        if AmbientSound.from(id: id).isFileBased {
            ambienceDesiredVolume = min(max(volume, 0), 1)
            if ambiencePlayerNode.isPlaying {
                fadeAmbienceVolume(to: ambienceDesiredVolume, duration: 0.15)
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
        // Prioridad: el cronómetro pisa la música de la tienda y la colección.
        stopShopBGM()
        stopOwnedBGM()
        
        let sound = AmbientSound.from(id: noiseId)

        // 1) Ambiente basado en archivo
        if sound.isFileBased {
            playAmbience(soundId: noiseId)
        } else {
            stopAmbience()
        }

        // 2) Binaural + (opcional) ruido de color procedural
        let binauralNoiseId = sound.isFileBased ? 0 : noiseId
        let hasBinaural = freqId != 0
        let hasColorNoise = (1...4).contains(binauralNoiseId)

        if hasBinaural || hasColorNoise {
            binauralManager.play(
                noiseId: binauralNoiseId,
                brainwaveDifference: hasBinaural ? brainwaveDifference(for: freqId) : nil,
                noiseVolume: getNoiseVolume(id: noiseId),
                toneVolume: hasBinaural ? getFreqVolume(id: freqId) : 0
            )
        } else {
            binauralManager.stop()
        }

        currentNoiseId = noiseId
        currentFreqId = freqId
    }

    /// Reanuda la reproducción si estaba pausada (ej: al volver del
    /// background después de una suspensión larga de iOS). No hace nada
    /// si no había nada sonando o si ya estaba reproduciendo.
    func resumeIfNeeded() {
        guard currentAmbienceId != nil else { return }

        // Si el engine quedó detenido por iOS tras una suspensión larga,
        // lo arrancamos de nuevo.
        if !ambienceEngine.isRunning {
            do {
                try ambienceEngine.start()
            } catch {
                print("Error reiniciando engine de ambience: \(error.localizedDescription)")
                return
            }
        }

        // Si el nodo quedó pausado, lo reanudamos.
        if !ambiencePlayerNode.isPlaying {
            guard startAmbiencePlayer() else { return }
        }

        // Reaplicamos el volumen deseado con un fade muy corto (0.3s).
        fadeAmbienceVolume(to: ambienceDesiredVolume, duration: 0.3)
    }

    func pauseBackground() {
        pauseAmbience()
        binauralManager.pause()
    }

    func stopBackground() {
        stopAmbience()
        binauralManager.stop()
        currentNoiseId = nil
        currentFreqId = nil
    }


    func stopBackgroundImmediate() {
        stopAmbienceImmediate()
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
    
    // MARK: - Música de la Tienda (Premium)
    
    func playShopBGM() {
        guard !isTimerAudioPlaying else { return }
        guard shopBGPlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "shop_theme", withExtension: "mp3") else { return }
        
        do {
            shopBGPlayer = try AVAudioPlayer(contentsOf: url)
            shopBGPlayer?.numberOfLoops = -1
            
            // Leer el volumen guardado específico de la tienda (por defecto 0.4)
            let savedVolume = UserDefaults.standard.object(forKey: "shop_bgm_volume") as? Float ?? 0.4
            
            shopBGPlayer?.volume = 0
            Task { try? await AudioPlatform.activateSession(mixWithOthers: true) }
            shopBGPlayer?.play()
            shopBGPlayer?.setVolume(savedVolume, fadeDuration: 1.5)
        } catch {
            print("Error al reproducir la música de la tienda: \(error)")
        }
    }
    
    // Nueva función para actualizar el volumen en vivo
    func setShopBGMVolume(_ volume: Float) {
        shopBGPlayer?.setVolume(volume, fadeDuration: 0.1)
    }
    
    func stopShopBGM() {
        guard let player = shopBGPlayer else { return }
        
        // Fade-out de 1.5 segundos
        player.setVolume(0, fadeDuration: 1.5)
        
        // Esperamos a que termine el fade antes de destruirlo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            player.stop()
            self.shopBGPlayer = nil
        }
    }
    
    func pauseShopBGM() {
        shopBGPlayer?.pause()
    }
    
    func resumeShopBGM() {
        guard !isTimerAudioPlaying else { return }
        // Si no había sido creado (por ejemplo, si el usuario entró directo a pausar antes de que suene)
        if shopBGPlayer == nil {
            playShopBGM()
        } else {
            shopBGPlayer?.play()
        }
    }
    
    // MARK: - Música de la Colección (Premium)
    
    func playOwnedBGM() {
        guard !isTimerAudioPlaying else { return }
        guard ownedBGPlayer == nil else { return }
        // ⚠️ ACÁ PONÉS EL NOMBRE DE TU ARCHIVO DE AUDIO PARA LA COLECCIÓN
        guard let url = Bundle.main.url(forResource: "owned_theme", withExtension: "mp3") else { return }
        
        do {
            ownedBGPlayer = try AVAudioPlayer(contentsOf: url)
            ownedBGPlayer?.numberOfLoops = -1
            
            let savedVolume = UserDefaults.standard.object(forKey: "owned_bgm_volume") as? Float ?? 0.4
            ownedBGPlayer?.volume = 0
            Task { try? await AudioPlatform.activateSession(mixWithOthers: true) }
            ownedBGPlayer?.play()
            ownedBGPlayer?.setVolume(savedVolume, fadeDuration: 1.5)
        } catch {
            print("Error al reproducir la música de la colección: \(error)")
        }
    }
    
    func stopOwnedBGM() {
        guard let player = ownedBGPlayer else { return }
        player.setVolume(0, fadeDuration: 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            player.stop()
            self.ownedBGPlayer = nil
        }
    }
    
    func pauseOwnedBGM() {
        ownedBGPlayer?.pause()
    }
    
    func resumeOwnedBGM() {
        guard !isTimerAudioPlaying else { return }
        if ownedBGPlayer == nil {
            playOwnedBGM()
        } else {
            ownedBGPlayer?.play()
        }
    }
    
    func setOwnedBGMVolume(_ volume: Float) {
        ownedBGPlayer?.setVolume(volume, fadeDuration: 0.1)
    }
}
