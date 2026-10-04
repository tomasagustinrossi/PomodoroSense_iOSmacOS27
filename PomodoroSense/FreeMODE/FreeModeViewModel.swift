//
//  FreeModeViewModel.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  FreeModeViewModel.swift
//  PomodoroSense
//
//  ViewModel INDEPENDIENTE para el modo libre.
//  No toca TimerViewModel, SessionStore ni AudioManager.
//  Tiene su propio timer, su propio player y su propia persistencia.
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class FreeModeViewModel: NSObject, ObservableObject {

    // MARK: - Estado de sesión
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var sessions: [FreeModeSession] = []

    // MARK: - Música
    @Published private(set) var musicTitle: String? = nil
    @Published private(set) var isMusicPlaying = false
    @Published var musicVolume: Float = 0.8 {
        didSet { musicPlayer?.volume = musicVolume }
    }
    private var musicPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?

    // MARK: - Timer interno
    private var ticker: Timer?
    private var startReferenceDate: Date?
    private var sessionStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0

    // MARK: - Persistencia
    private let sessionsKey       = "freeMode.sessions"
    private let musicFileNameKey  = "freeMode.musicFileName"
    private let defaults: UserDefaults
    private static let musicFolderName = "FreeModeMusic"

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        loadSessions()
        restoreMusicIfPossible()
    }

    // MARK: - Timer

    func toggleTimer() {
        isRunning ? pauseTimer() : startTimer()
    }

    func startTimer() {
        guard !isRunning else { return }
        if sessionStartedAt == nil { sessionStartedAt = Date() }
        startReferenceDate = Date()
        isRunning = true
        startTicker()
    }

    func pauseTimer() {
        guard isRunning else { return }
        if let ref = startReferenceDate {
            accumulatedElapsed += Date().timeIntervalSince(ref)
        }
        startReferenceDate = nil
        isRunning = false
        cancelTicker()
        elapsed = accumulatedElapsed
    }

    /// Detiene y guarda la sesión actual (si dura al menos 10s).
    @discardableResult
    func finishSession() -> FreeModeSession? {
        pauseTimer()
        defer { stopMusic() }

        guard let startedAt = sessionStartedAt else {
            resetTimerState()
            return nil
        }
        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(startedAt)

        resetTimerState()

        // Mínimo 10s para no ensuciar el historial con clicks accidentales.
        guard duration >= 10 else { return nil }

        let session = FreeModeSession(
            startedAt: startedAt,
            endedAt: endedAt,
            musicTitle: musicTitle
        )
        sessions.insert(session, at: 0)
        persistSessions()
        return session
    }

    /// Descarta la sesión actual sin guardar.
    func discardSession() {
        pauseTimer()
        resetTimerState()
        stopMusic()
    }

    private func resetTimerState() {
        isRunning = false
        elapsed = 0
        accumulatedElapsed = 0
        sessionStartedAt = nil
        startReferenceDate = nil
        cancelTicker()
    }

    /// Se llama al volver del background / reabrir la vista.
    func restartTickerIfNeeded() {
        guard isRunning, ticker == nil else { return }
        startTicker()
    }

    // MARK: - Ticker

    private func startTicker() {
        cancelTicker()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func cancelTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isRunning, let ref = startReferenceDate else { return }
        elapsed = accumulatedElapsed + Date().timeIntervalSince(ref)
    }

    // MARK: - Formato

    /// HH:MM:SS si hay horas, MM:SS si no.
    var formattedElapsed: String {
        let total = Int(elapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Música

    func importMusic(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let folder = try musicFolder()
            let destName = url.lastPathComponent
            let dest = folder.appendingPathComponent(destName)

            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)

            defaults.set(destName, forKey: musicFileNameKey)
            musicTitle = destName
            prepareMusicPlayer(for: dest)
        } catch {
            print("[FreeMode] Error importando música: \(error)")
        }
    }

    func toggleMusic() {
        guard let player = musicPlayer else { return }
        if player.isPlaying {
            player.pause()
            isMusicPlaying = false
        } else {
            ensureSessionActive()
            player.play()
            isMusicPlaying = true
        }
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer?.currentTime = 0
        isMusicPlaying = false
    }

    func removeMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        musicTitle = nil
        isMusicPlaying = false
        defaults.removeObject(forKey: musicFileNameKey)
    }

    private func restoreMusicIfPossible() {
        guard let name = defaults.string(forKey: musicFileNameKey),
              let folder = try? musicFolder() else { return }
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            defaults.removeObject(forKey: musicFileNameKey)
            return
        }
        musicTitle = name
        prepareMusicPlayer(for: url)
    }

    private func prepareMusicPlayer(for url: URL) {
        musicPlayer?.stop()
        musicPlayer = nil
        isMusicPlaying = false
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0            // sin loop
            player.volume = musicVolume
            player.delegate = self
            player.prepareToPlay()
            musicPlayer = player
        } catch {
            print("[FreeMode] Error preparando player: \(error)")
        }
    }

    private func musicFolder() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = docs.appendingPathComponent(Self.musicFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        return folder
    }

    private func ensureSessionActive() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: - SFX al terminar la música

    private func playEndSFX() {
        let candidates = ["focus_complete"]
        for name in candidates {
            if let url = ["m4a", "mp3", "wav"]
                .compactMap({ Bundle.main.url(forResource: name, withExtension: $0) })
                .first {
                do {
                    let p = try AVAudioPlayer(contentsOf: url)
                    p.volume = 0.8
                    p.prepareToPlay()
                    p.play()
                    sfxPlayer = p
                } catch {
                    print("[FreeMode] SFX error: \(error)")
                }
                return
            }
        }
    }

    // MARK: - Persistencia de historial

    private func loadSessions() {
        guard let data = defaults.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([FreeModeSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: sessionsKey)
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persistSessions()
    }

    func clearHistory() {
        sessions.removeAll()
        persistSessions()
    }
}

// MARK: - AVAudioPlayerDelegate

extension FreeModeViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isMusicPlaying = false
            self.playEndSFX()
        }
    }
}