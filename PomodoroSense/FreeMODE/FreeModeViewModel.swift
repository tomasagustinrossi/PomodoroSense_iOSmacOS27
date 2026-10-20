import Foundation
import Combine
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class FreeModeViewModel: NSObject, ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var sessions: [FreeModeSession] = []

    @Published var noiseId: Int = 0
    @Published var freqId: Int = 0
    @Published private(set) var currentTheme: PomodoroTheme = ThemeManager.getTheme(for: 0)

    private var ticker: Timer?
    private var startReferenceDate: Date?
    private var sessionStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0

    private let sessionsKey = "freeMode.sessions"
    private let defaults: UserDefaults
    private static let minSessionDuration: TimeInterval = 5 * 60

#if os(iOS) && canImport(ActivityKit)
private var currentActivityId: String?
#endif
private var localCommandObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        loadSessions()

        #if os(iOS)
        // 1. Notificación Darwin (app en segundo plano / otro proceso)
        let darwinNotification = "com.tomiirossi.PomodoroSense.WidgetCommand"
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                let vm = Unmanaged<FreeModeViewModel>.fromOpaque(observer!).takeUnretainedValue()
                Task { @MainActor in vm.handleWidgetCommand() }
            },
            darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
        #endif

        // 2. Notificación local (app en primer plano). `PomodoroWidgetBridge.send` la postea
        //    siempre; antes este VM no la escuchaba en iOS y por eso la isla no pausaba la app.
        //    Si llegan las dos, la segunda no hace nada: la primera ya consumió el comando.
        localCommandObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("WidgetCommandReceived"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWidgetCommand() }
        }
    }

    deinit {
        #if os(iOS)
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        #endif
        if let obs = localCommandObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        localCommandObserver = nil
    }

    func toggleTimer() {
        isRunning ? pauseTimer() : startTimer()
    }

    func startTimer() {
        guard !isRunning else { return }
        if sessionStartedAt == nil { sessionStartedAt = Date() }
        startReferenceDate = Date()
        isRunning = true
        startTicker()

        if noiseId != 0 || freqId != 0 {
            AudioManager.shared.playBackground(noiseId: noiseId, freqId: freqId)
        }

        // Si ya hay una Live Activity, solo se actualiza. Si no, se crea.
        startLiveActivity()
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
        AudioManager.shared.pauseBackground()

        updateLiveActivity()
    }

    @discardableResult
    func finishSession() -> FreeModeSession? {
        pauseTimer()
        defer { AudioManager.shared.stopBackground() }

        guard let startedAt = sessionStartedAt else {
            resetTimerState()
            return nil
        }
        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(startedAt)

        resetTimerState()

        guard duration >= Self.minSessionDuration else { return nil }

        let session = FreeModeSession(startedAt: startedAt, endedAt: endedAt)
        sessions.insert(session, at: 0)
        persistSessions()
        return session
    }

    func discardSession() {
        pauseTimer()
        resetTimerState()   // ya detiene la Live Activity
        AudioManager.shared.stopBackground()
    }

    private func resetTimerState() {
        isRunning = false
        elapsed = 0
        accumulatedElapsed = 0
        sessionStartedAt = nil
        startReferenceDate = nil
        cancelTicker()
        stopLiveActivity()
    }

    func restartTickerIfNeeded() {
        guard isRunning, ticker == nil else { return }
        startTicker()
    }

    private func startTicker() {
        cancelTicker()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
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

    func updateNoiseId(_ id: Int) {
        guard noiseId != id else { return }
        noiseId = id
        currentTheme = ThemeManager.getTheme(for: id)
        if isRunning { AudioManager.shared.playBackground(noiseId: id, freqId: freqId) }
    }

    func updateFreqId(_ id: Int) {
        guard freqId != id else { return }
        freqId = id
        if isRunning { AudioManager.shared.playBackground(noiseId: noiseId, freqId: id) }
    }

    func updateNote(for sessionId: UUID, note: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].note = trimmed.isEmpty ? nil : trimmed
        persistSessions()
    }

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

    // MARK: - Live Activity

    /// Tiempo transcurrido "en vivo" (acumulado + tramo en curso), sin depender del ticker.
    private var currentElapsed: TimeInterval {
        accumulatedElapsed + (startReferenceDate.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// `targetDate` de Free Mode: ahora + 24h - transcurrido.
    /// El widget calcula el inicio real como `targetDate - 24h`, así que debe descontar
    /// lo ya transcurrido (antes siempre era ahora + 24h y al reanudar el reloj volvía a 0).
    private func freeModeTargetDate() -> Date {
        Date().addingTimeInterval(PomodoroLiveActivity.freeModeSpan - currentElapsed)
    }

    private func startLiveActivity() {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let state = PomodoroAttributes.ContentState(
            isBreak: false,
            currentSession: 1,
            totalSessions: 1,
            targetDate: freeModeTargetDate(),
            noiseId: noiseId,
            isRunning: true,
            pausedSeconds: nil,
            reward: nil,
            isFreeMode: true
        )
        let content = ActivityContent(state: state, staleDate: nil)

        // Si ya hay una Live Activity de Free Mode (la propia o una huérfana de otro arranque),
        // solo se actualiza. Antes, con `currentActivityId == nil` se creaba una segunda isla.
        if let existing = Activity<PomodoroAttributes>.activities.first(where: {
            $0.id == currentActivityId || $0.content.state.isFreeMode
        }) {
            currentActivityId = existing.id
            Task { await existing.update(content) }
            return
        }

        do {
            let attributes = PomodoroAttributes(presetName: "FREE MODE")
            let activity = try Activity<PomodoroAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivityId = activity.id
        } catch {
            print("Error starting Free Mode LA: \(error)")
        }
        #endif
    }

    private func updateLiveActivity() {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }

        // Estado calculado una sola vez, antes del Task, con los valores de este instante.
        let state = PomodoroAttributes.ContentState(
            isBreak: false,
            currentSession: 1,
            totalSessions: 1,
            targetDate: freeModeTargetDate(),
            noiseId: noiseId,
            isRunning: isRunning,
            pausedSeconds: isRunning ? nil : Int(currentElapsed),
            reward: nil,
            isFreeMode: true
        )
        let content = ActivityContent(state: state, staleDate: nil)

        // Solo las Live Activities de Free Mode (nunca las de Pomodoro).
        let ownId = currentActivityId
        let freeActivities = Activity<PomodoroAttributes>.activities.filter {
            $0.content.state.isFreeMode || $0.id == ownId
        }
        Task {
            for activity in freeActivities {
                await activity.update(content)
            }
        }
        #endif
    }

    private func stopLiveActivity() {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let ownId = currentActivityId
        currentActivityId = nil
        let freeActivities = Activity<PomodoroAttributes>.activities.filter {
            $0.content.state.isFreeMode || $0.id == ownId
        }
        Task {
            for activity in freeActivities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    /// Si este VM arrancó "en blanco" (app relanzada, VM nuevo) pero la isla de Free Mode sigue viva,
    /// la isla es la fuente de verdad: recuperamos el tiempo transcurrido desde ella.
    /// Sin esto, un "pausar" desde la isla se convertía en "iniciar de cero" y parecía no hacer nada.
    private func adoptLiveActivityIfNeeded() {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard sessionStartedAt == nil, !isRunning else { return }
        guard let activity = Activity<PomodoroAttributes>.activities.first(where: { $0.content.state.isFreeMode })
        else { return }

        let state = activity.content.state
        let recovered: TimeInterval = state.isRunning
            ? PomodoroLiveActivity.freeModeSpan - state.targetDate.timeIntervalSinceNow
            : TimeInterval(state.pausedSeconds ?? 0)

        // Valor imposible (isla vieja o corrupta): no adoptamos.
        guard recovered >= 0, recovered <= PomodoroLiveActivity.freeModeSpan else { return }

        currentActivityId = activity.id
        noiseId = state.noiseId
        currentTheme = ThemeManager.getTheme(for: state.noiseId)
        accumulatedElapsed = recovered
        elapsed = recovered
        sessionStartedAt = Date().addingTimeInterval(-recovered)

        if state.isRunning {
            startReferenceDate = Date()
            isRunning = true
            startTicker()
            if noiseId != 0 || freqId != 0 {
                AudioManager.shared.playBackground(noiseId: noiseId, freqId: freqId)
            }
        }
        #endif
    }

    // MARK: - Widget Commands

    func handleWidgetCommand() {
        let defaults = PomodoroSessionStore.shared
        guard let command = defaults.string(forKey: PomodoroWidgetBridge.commandKey) else { return }

        // Sólo procesamos comandos de Free Mode. Si es de Pomodoro, lo dejamos
        // intacto para que TimerViewModel lo tome.
        let freeCommands: Set<WidgetCommand> = [.freeToggle, .freeStop, .freePause, .freeResume]
        guard let cmd = WidgetCommand(rawValue: command), freeCommands.contains(cmd) else { return }

        let sentAt = defaults.double(forKey: PomodoroWidgetBridge.commandDateKey)
        defaults.removeObject(forKey: PomodoroWidgetBridge.commandKey)
        defaults.removeObject(forKey: PomodoroWidgetBridge.commandDateKey)

        guard sentAt > 0,
              Date().timeIntervalSince1970 - sentAt < PomodoroWidgetBridge.commandTTL else {
            #if DEBUG
            print("🟣 [Free] \(command) descartado por TTL")
            #endif
            return
        }

        #if DEBUG
        print("🟣 [Free] \(command) — VM corriendo: \(isRunning), transcurrido: \(Int(currentElapsed))s")
        #endif

        // El STOP no necesita recuperar nada; el resto sí, por si el VM arrancó en blanco.
        if cmd != .freeStop { adoptLiveActivityIfNeeded() }

        switch cmd {
        case .freeToggle: toggleTimer()
        case .freePause:  pauseTimer()    // idempotente: si ya estaba en pausa, no hace nada
        case .freeResume: startTimer()    // idempotente: si ya estaba corriendo, no hace nada
        case .freeStop:   finishSession()
        default:          break
        }
    }
}
