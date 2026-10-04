import AVFoundation
import Foundation

@MainActor
final class AudioManager {
    static let shared = AudioManager()

    private var sfxPlayer: AVAudioPlayer?
    private let binauralManager = BinauralManager()

    private var currentNoiseId: Int?
    private var currentFreqId: Int?

    private init() {
        configureAndActivateSession()
    }

    // MARK: - Sesión

    func configureAndActivateSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.04)
            try session.setActive(true)
        } catch {
            print("Error configurando/activando sesión: \(error.localizedDescription)")
        }
    }

    func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            print("Error desactivando sesión: \(error.localizedDescription)")
        }
    }

    /// La escena generada mantiene activa la sesión mientras el temporizador está en foco.
    func keepAppAlive(enable: Bool) {}

    nonisolated enum SFX: Equatable, Sendable {
        case uiClick, focusEnd, breakEnd, allDone, countdown

        var filename: String {
            switch self {
            case .uiClick: return "ui_click"
            case .focusEnd: return "focus_complete"
            case .breakEnd: return "break_complete"
            case .allDone: return "all_done"
            case .countdown: return "countdown"
            }
        }
    }

    // MARK: - SFX

    func playSFX(_ effect: SFX) {
        guard let url = getURL(for: effect.filename) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = effect == .countdown ? 0.4 : 0.8
            player.prepareToPlay()
            player.play()
            sfxPlayer = player
        } catch {
            print("Error SFX: \(error.localizedDescription)")
        }
    }

    // MARK: - Ecualizador

    func getNoiseVolume(id: Int) -> Float {
        let key = "vol_noise_\(id)"

        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }

        switch id {
        case 1: return 0.7
        case 2: return 0.6
        case 3: return 0.4
        case 4: return 0.5
        default: return 0.5
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

        guard currentNoiseId == id else {
            return
        }

        binauralManager.setNoiseVolume(volume)
    }

    func setFreqVolume(id: Int, volume: Float) {
        UserDefaults.standard.set(volume, forKey: "vol_freq_\(id)")

        guard currentFreqId == id else {
            return
        }

        binauralManager.setToneVolume(volume)
    }

    // MARK: - Ambiente

    func playBackground(noiseId: Int, freqId: Int) {
        currentNoiseId = noiseId
        currentFreqId = freqId

        guard noiseId != 0 || freqId != 0 else {
            binauralManager.pause()
            return
        }

        binauralManager.play(
            noiseId: noiseId,
            brainwaveDifference: brainwaveDifference(for: freqId),
            noiseVolume: getNoiseVolume(id: noiseId),
            toneVolume: getFreqVolume(id: freqId)
        )
    }

    func pauseBackground() {
        binauralManager.pause()
    }

    func stopBackground() {
        binauralManager.stop()
        currentNoiseId = nil
        currentFreqId = nil
    }

    private func getURL(for filename: String) -> URL? {
        let extensions = ["m4a", "mp3", "wav"]

        for ext in extensions {
            if let url = Bundle.main.url(forResource: filename, withExtension: ext) {
                return url
            }
        }

        return nil
    }

    private func brainwaveDifference(for id: Int) -> Float? {
        switch id {
        case 1: return 40
        case 2: return 15
        case 3: return 10
        case 4: return 6
        default: return nil
        }
    }
}
