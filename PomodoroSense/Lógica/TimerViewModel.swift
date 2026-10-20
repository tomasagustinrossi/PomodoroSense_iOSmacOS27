import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Limpieza síncrona de Live Activities
/// Se usa cuando la app está por morir (willTerminate): bloquea el hilo hasta que iOS
/// confirme que las Live Activities terminaron, o hasta agotar el timeout.
enum LiveActivityCleaner {
    static func endAllAndWait(timeout: TimeInterval = 2) {
#if os(iOS) && canImport(ActivityKit)
        // `end(_:dismissalPolicy:)` con ActivityContent es iOS 16.2+.
        guard #available(iOS 16.2, *) else { return }

        let activities = Activity<PomodoroAttributes>.activities
        guard !activities.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
#endif
    }
}

// MARK: - Snapshot del estado previo a ser mirror
struct MirrorSnapshot {
    let config: PomodoroConfigDTO
    let isRunning: Bool
    let isBreak: Bool
    let currentSession: Int
    let totalSessions: Int
    let targetDate: Date?
    let secondsRemaining: TimeInterval
    let progress: CGFloat
    let timeRemainingString: String
    let totalTimeRemainingString: String
}

// MARK: - Summary payload
struct SessionSummaryPayload: Equatable {
    let chipsEarned: Int
    let newStreak: Int
}

@MainActor
class TimerViewModel: ObservableObject {

    // MARK: - Estado Público
    @Published var isRunning: Bool = false
    @Published var isBreak: Bool = false
    @Published var progress: CGFloat = 1.0
    @Published var currentSession: Int = 1
    @Published var totalSessions: Int = 5
    @Published var timeRemainingString: String = "30:00"
    @Published var currentTheme: PomodoroTheme = ThemeManager.getTheme(for: 0)
    @Published var totalTimeRemainingString: String = "0M LEFT"
    @Published var wantsToNavigateToTimer: Bool = false
    /// Flag para navegar a la pantalla de presets al terminar/skipear
    /// el preset completo. Lo consume la vista principal y lo limpia.
    @Published var wantsToNavigateToSavedPresets: Bool = false
    @Published var sessionReward: SessionRewardPayload? = nil
    @Published var sessionSummary: SessionSummaryPayload? = nil
    @Published var tierUnlock: CurrencyTier? = nil
    

    // MARK: Conexión automática con dispositivo vinculado
    /// Se conserva por compatibilidad con la UI. El LocalSyncEngine ya se reconecta solo.
    @Published var autoConecting: Bool = false

    // MARK: - Estado de Red (Mirror Mode)
    @Published var syncState: LocalSyncEngine.State = .idle
    /// true solo mientras este dispositivo está conectado como Mirror de otro.
    @Published private(set) var isMirror: Bool = false
    /// Evita lanzar dos desvinculaciones si Stop se dispara dos veces seguidas
    /// (doble tap, o comando remoto + unlink propio cruzándose).
    private var isUnlinkingFromStop = false
    
    /// Segundos que, tras desvincular, el standby rechaza vínculos entrantes.
    private static let unlinkQuarantine: TimeInterval = 20

    // MARK: - Estado Privado
    private var syncEngine: LocalSyncEngine?
    private var sessionRewardPayloadBuffer: SessionRewardPayload? = nil
    private var preMirrorActiveConfig: PomodoroConfigDTO?
    private var preMirrorSnapshot: MirrorSnapshot?
    private var isMirroringActiveSession: Bool = false
    private var rewardDismissTask: Task<Void, Never>? = nil
    private var rewardCleanupTask: Task<Void, Never>? = nil
    private var summaryDismissTask: Task<Void, Never>? = nil
    /// Pequeña espera (0.5 s) entre que el timer llega a 0 y se avanza de fase.
    /// Se guarda para poder cancelarla y evitar un doble avance (skip manual en esa ventana).
    private var phaseAdvanceTask: Task<Void, Never>? = nil

    /// `true` desde que el preset se cerró con éxito hasta que se limpia el estado
    /// (popup de reward / LA "COMPLETED"). Mientras sea true, los controles del timer
    /// no deben hacer nada (si no, un toggle en 00:00 registraría una sesión de más).
    private var isPresetFinished: Bool = false

    private enum LocalSyncDefaults {
        static let enabled = "localsync_enabled"
        static let role = "localsync_role"
        static let deviceName = "localsync_deviceName"
    }

    // MARK: - Corrida del preset
    private var currentPresetRunId: UUID = UUID()
    /// IDs de los records de la corrida en curso, en orden de creación.
    private var pendingPresetRecordIds: [UUID] = []
    /// `true` si la corrida quedó "manchada" (skip de focus o salto hacia adelante).
    private var presetHasSkip: Bool = false

    @Published var activeConfig: PomodoroConfigDTO = TimerViewModel.defaultConfig
    private var hasAutoNavigatedForCurrentSession: Bool = false

    private var totalSecondsForCurrentPhase: TimeInterval = 0
    private var secondsRemaining: TimeInterval = 0

    private var disconnectGraceTask: Task<Void, Never>? = nil

    private var lastPlayedCountdownSecond: Int = -1
    private var lastSyncBroadcast: Date = .distantPast

    private var targetDate: Date? {
        didSet {
            objectWillChange.send()
        }
    }

    /// ¿Hay una sesión activa (corriendo o pausada)?
    var isActive: Bool {
        isRunning || targetDate != nil
    }

    private var timer: Timer?
    private var observers = Set<AnyCancellable>()
    private var currentActivityId: String? = nil

    // MARK: - Preset por Defecto
    static let defaultConfig = PomodoroConfigDTO(
        name: "DEFAULT",
        focus: 30,
        breakTime: 10,
        sessions: 5,
        audio: AudioConfigDTO(presetId: 0, noiseId: 0, freqId: 0)
    )

    init() {
        activeConfig = Self.defaultConfig
        totalSessions = Self.defaultConfig.sessions
        currentTheme = ThemeManager.getTheme(for: Self.defaultConfig.audio.noiseId)
        setupPhase()
        setupLifecycleObservers()
        restorePersistedState()
        handleWidgetCommand()
    }

    // MARK: - Helpers de corrida del preset

    /// Invalida la corrida actual si tiene records pendientes y limpia el buffer.
    /// Es idempotente: llamarla dos veces no invalida dos veces.
    private func invalidateCurrentPresetRunIfNeeded() {
        guard !pendingPresetRecordIds.isEmpty else { return }
        SessionStore.shared.markPresetInvalidated(currentPresetRunId)
        pendingPresetRecordIds.removeAll()
    }

    /// Invalida los records de la corrida desde `session` en adelante (se van a rehacer)
    /// y recalcula el buffer y el flag de skip a partir de lo que queda.
    private func invalidateRecords(fromSession session: Int) {
        SessionStore.shared.markPresetRecordsInvalidated(
            currentPresetRunId,
            fromSession: session
        )
        // Solo cuentan los records vigentes de sesiones anteriores.
        let remaining = SessionStore.shared
            .records(forPresetRunId: currentPresetRunId)
            .filter { $0.sessionNumber < session && !$0.presetInvalidated }
        pendingPresetRecordIds = remaining.map { $0.id }
        presetHasSkip = remaining.contains { !$0.qualifiesForChips }
    }

    private func phaseTotalSeconds() -> TimeInterval {
        TimeInterval((isBreak ? activeConfig.breakTime : activeConfig.focus) * 60)
    }

    private func cancelPopupTasks() {
        rewardCleanupTask?.cancel()
        rewardCleanupTask = nil
        rewardDismissTask?.cancel()
        rewardDismissTask = nil
        summaryDismissTask?.cancel()
        summaryDismissTask = nil
    }

    // MARK: - Intenciones de la Interfaz
    func loadConfiguration(_ config: PomodoroConfigDTO, autoStart: Bool = false) {
        if isMirror {
            // Primero desvincular (async) y recién después cargar: si no, `disableSync`
            // restauraba el snapshot viejo encima de la config nueva.
            Task { await self.unlinkAndLoad(config, autoStart: autoStart) }
            return
        }

        if autoStart {
            cancelPopupTasks()
            AudioManager.shared.stopBackgroundImmediate()

            activeConfig = config
            totalSessions = config.sessions
            currentTheme = ThemeManager.getTheme(for: config.audio.noiseId)

            resetToInitialState()   // invalida la corrida anterior si quedó algo pendiente
            isRunning = true
            startTicking()

            if !isBreak {
                AudioManager.shared.playBackground(noiseId: config.audio.noiseId, freqId: config.audio.freqId)
            }
        } else {
            // Con una sesión en curso NO se pisa la config: cambiaría las duraciones
            // de las fases siguientes a mitad de corrida.
            let isTimerStarted = isActive || progress < 1.0 || currentSession > 1
            guard !isTimerStarted || isPresetFinished else { return }

            activeConfig = config
            totalSessions = config.sessions
            currentTheme = ThemeManager.getTheme(for: config.audio.noiseId)
            resetToInitialState()
        }
    }

    // MARK: - Cambios de Audio en Vivo

    func updateNoiseId(_ id: Int) {
        guard activeConfig.audio.noiseId != id else { return }
        activeConfig.audio.noiseId = id
        currentTheme = ThemeManager.getTheme(for: id)

        if isRunning && !isBreak {
            AudioManager.shared.playBackground(
                noiseId: id,
                freqId: activeConfig.audio.freqId
            )
        }
        savePersistedState()
        broadcastState()
    }

    func updateFreqId(_ id: Int) {
        guard activeConfig.audio.freqId != id else { return }
        activeConfig.audio.freqId = id

        if isRunning && !isBreak {
            AudioManager.shared.playBackground(
                noiseId: activeConfig.audio.noiseId,
                freqId: id
            )
        }
        savePersistedState()
        broadcastState()
    }

    @discardableResult
    private func recordFocusCompletion() -> PomodoroSessionRecord {
        return SessionStore.shared.recordCompletedSession(
            presetName: activeConfig.name,
            focusMinutes: activeConfig.focus,
            sessionNumber: currentSession,
            breakMinutes: activeConfig.breakTime,
            totalSessions: totalSessions,
            mirroredToDeviceIds: [],
            presetRunId: currentPresetRunId
        )
    }

    func resetToInitialState() {
        // Si quedaba una corrida con records sin cerrar, se invalida (STOP, nueva
        // sesión, etc.). Si venía de un cierre exitoso, el buffer ya está vacío.
        invalidateCurrentPresetRunIfNeeded()
        currentPresetRunId = UUID()
        presetHasSkip = false
        isPresetFinished = false

        cancelTimer()
        cancelPopupTasks()
        sessionRewardPayloadBuffer = nil
        sessionReward = nil
        sessionSummary = nil
        tierUnlock = nil

        self.currentSession = 1
        self.isBreak = false
        self.isRunning = false
        self.targetDate = nil
        self.hasAutoNavigatedForCurrentSession = false
        setupPhase()
        clearPersistedState()
        syncWidgetTimerState()
        broadcastState()
    }

    func stopAndReset() {
        stopTicking()
        AudioManager.shared.stopBackground()
        resetToInitialState()
    }

    private func toggleTimer() {
        guard !isPresetFinished else { return }

        isRunning.toggle()

        if isRunning {
            startTicking()
            if !isBreak {
                AudioManager.shared.playBackground(
                    noiseId: activeConfig.audio.noiseId,
                    freqId: activeConfig.audio.freqId
                )
            }
        } else {
            // Pausa: congelar el valor exacto
            if let target = targetDate {
                secondsRemaining = max(0, target.timeIntervalSinceNow)
            }
            // targetDate se preserva (no se nulea) para que savePersistedState lo guarde
            cancelTimer()
            updateUIState()
            AudioManager.shared.keepAppAlive(enable: false)
            AudioManager.shared.pauseBackground()
            updateLiveActivity()
        }
        savePersistedState()
        broadcastState()
    }

    // MARK: - Skip de fase

    @discardableResult
    func skipToNextPhase(wasCompleted: Bool = true) -> Bool {
        guard !isPresetFinished else { return false }
        // Un skip manual sin sesión activa no debe registrar nada ni arrancar el timer.
        guard wasCompleted || isActive else { return false }

        cancelTimer()

        if isBreak {
            AudioManager.shared.playSFX(.breakEnd)
            currentSession += 1
            isBreak = false
        } else {
            if wasCompleted {
                let record = recordFocusCompletion()
                pendingPresetRecordIds.append(record.id)
            } else {
                // SKIP explícito: invalida toda la corrida.
                rewardDismissTask?.cancel()
                rewardDismissTask = nil
                if sessionReward != nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sessionReward = nil
                    }
                }
                sessionRewardPayloadBuffer = nil

                let skipped = SessionStore.shared.recordSkippedSession(
                    presetName: activeConfig.name,
                    focusMinutes: activeConfig.focus,
                    sessionNumber: currentSession,
                    breakMinutes: activeConfig.breakTime,
                    totalSessions: totalSessions,
                    presetRunId: currentPresetRunId
                )
                pendingPresetRecordIds.append(skipped.id)
                presetHasSkip = true
            }

            AudioManager.shared.pauseBackground()

            if currentSession >= totalSessions {
                AudioManager.shared.playSFX(.allDone)
                finalizePreset(silent: false)
                return true
            } else {
                AudioManager.shared.playSFX(.focusEnd)
                isBreak = true
            }
        }

        setupPhase()
        isRunning = true
        startTicking()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updateLiveActivity()
        }

        if !isBreak {
            AudioManager.shared.playBackground(
                noiseId: activeConfig.audio.noiseId,
                freqId: activeConfig.audio.freqId
            )
        }
        return false
    }

    // MARK: - Reward

    /// Cierra la corrida sin acreditar nada (invalidada, vacía o sin records).
    private func closePresetWithoutReward(silent: Bool) {
        invalidateCurrentPresetRunIfNeeded()
        stopLiveActivity()
        resetToInitialState()
        if !silent { wantsToNavigateToSavedPresets = true }
    }

    /// Limpia LA + estado a los N segundos, salvo que el usuario ya haya arrancado otra cosa.
    private func scheduleCompletionCleanup(after seconds: TimeInterval = 15) {
        rewardCleanupTask?.cancel()
        rewardCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isPresetFinished else { return }
            self.stopLiveActivity()
            self.resetToInitialState()
            self.wantsToNavigateToSavedPresets = true
        }
    }

    /// Cierra el preset actual. Es el ÚNICO punto donde se acreditan chips.
    /// - Skip en cualquier focus → corrida invalidada, sin chips ni popup.
    /// - Sin skip → se reasigna al día del cierre, se suman los earnings de todos los focus
    ///   y se acredita UNA vez.
    private func finalizePreset(silent: Bool) {
        isRunning = false
        targetDate = nil
        cancelTimer()

        guard !pendingPresetRecordIds.isEmpty else {
            closePresetWithoutReward(silent: silent)
            return
        }

        if presetHasSkip {
            closePresetWithoutReward(silent: silent)   // invalida la corrida
            return
        }

        let runId = currentPresetRunId
        SessionStore.shared.reassignPresetToDate(runId, to: Date())
        let presetRecords = SessionStore.shared.commitAndCalculateGlobalQuality(forPresetRunId: runId)

        // La corrida se cierra acá: el buffer ya no debe invalidarse en el reset posterior.
        pendingPresetRecordIds.removeAll()

        guard !presetRecords.isEmpty else {
            closePresetWithoutReward(silent: silent)
            return
        }

        let streak = SessionStore.shared.currentStreak
        let walletBefore = SessionStore.shared.wallet

        // ─── CONTROL ANTI-FARMEO ───
        let today = Calendar.current.startOfDay(for: Date())
        let previousRecordsToday = SessionStore.shared.records.filter {
            $0.dayStart == today && !$0.presetInvalidated && $0.qualifiesForChips
        }
        
        var earnedSilverToday = 0
        var earnedGoldToday = 0
        for record in previousRecordsToday {
            let e = ScoreCalculator.tierEarnings(for: record, streakDays: streak, wallet: walletBefore)
            earnedSilverToday += e[.silver] ?? 0
            earnedGoldToday += e[.gold] ?? 0
        }

        var totalEarnings: [CurrencyTier: Int] = [:]
        for record in presetRecords {
            var e = ScoreCalculator.tierEarnings(
                for: record,
                streakDays: streak,
                wallet: walletBefore
            )
            
            // Tope de Plata (10 al día)
            if let s = e[.silver], s > 0 {
                let remaining = max(0, CurrencyBalance.silverDailyCap - earnedSilverToday)
                let allowed = min(s, remaining)
                if allowed > 0 {
                    e[.silver] = allowed
                    earnedSilverToday += allowed
                } else {
                    e[.silver] = nil
                }
            }
            
            // Tope de Oro (1 al día)
            if let g = e[.gold], g > 0 {
                let remaining = max(0, CurrencyBalance.goldDailyCap - earnedGoldToday)
                let allowed = min(g, remaining)
                if allowed > 0 {
                    e[.gold] = allowed
                    earnedGoldToday += allowed
                } else {
                    e[.gold] = nil
                }
            }

            for (tier, amount) in e {
                totalEarnings[tier, default: 0] += amount
            }
        }

        let credited = SessionStore.shared.creditSession(
            totalEarnings,
            streakDays: streak
        )

        let bronze = credited[.bronze] ?? 0
        let silver = credited[.silver] ?? 0
        let gold   = credited[.gold]   ?? 0
        let totalEarned = bronze + silver + gold

        let walletAfter = SessionStore.shared.wallet
        let newlyUnlocked = walletAfter.unlockedTiers
            .subtracting(walletBefore.unlockedTiers)
            .first

        if silent {
            stopLiveActivity()
            resetToInitialState()
            return
        }

        let isJackpot = totalEarned >= 100

        let payload = SessionRewardPayload(
            chipsEarned: bronze,
            totalChipsToday: totalEarned,
            newStreak: streak,
            isLucky: false,
            isLastSession: true,
            isJackpot: isJackpot,
            bronzeEarned: bronze,
            silverEarned: silver,
            goldEarned: gold,
            newlyUnlockedTier: newlyUnlocked,
            generatedAt: Date()
        )

        isPresetFinished = true

        // Si totalEarned == 0 la LA se renderiza como "COMPLETED".
        updateLiveActivityWithReward(payload)
        broadcastSessionEnd()

        if totalEarned > 0 || newlyUnlocked != nil {
            if isJackpot || newlyUnlocked != nil {
                Haptics.success()
            } else {
                Haptics.impact(.light, intensity: 0.6)
            }

            if let tier = newlyUnlocked {
                self.sessionRewardPayloadBuffer = payload
                self.sessionReward = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    self.tierUnlock = tier
                }
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    self.sessionReward = payload
                }
                rewardDismissTask?.cancel()
                rewardDismissTask = Task { @MainActor [weak self] in
                    let duration: TimeInterval = isJackpot ? 5.0 : 2.8
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled, let self else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        self.sessionReward = nil
                    }
                }
            }

            // (Antes este bloque estaba duplicado más abajo.)
            if bronze > 0 {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    self.sessionSummary = SessionSummaryPayload(
                        chipsEarned: bronze,
                        newStreak: streak
                    )
                }
                summaryDismissTask?.cancel()
                summaryDismissTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, let self else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        self.sessionSummary = nil
                    }
                }
            }
        } else {
            // Nada que festejar: no dejamos al usuario mirando un timer en 00:00.
            wantsToNavigateToSavedPresets = true
        }

        // Con el popup de tier abierto no se programa limpieza: si no, a los 15 s
        // se borraba el popup. Se programa al cerrarlo (`dismissTierUnlock`).
        if newlyUnlocked == nil {
            scheduleCompletionCleanup()
        }
    }

    func dismissSessionReward() {
        rewardDismissTask?.cancel()
        rewardDismissTask = nil

        let wasLastSession = sessionReward?.isLastSession ?? false

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            sessionReward = nil
        }

        if wasLastSession {
            wantsToNavigateToSavedPresets = true
        }
    }

    func dismissSessionSummary() {
        summaryDismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            sessionSummary = nil
        }
    }

    func dismissTierUnlock() {
        let pendingPayload = sessionRewardPayloadBuffer
        sessionRewardPayloadBuffer = nil

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            tierUnlock = nil
        }

        // Ahora sí arranca la cuenta regresiva de limpieza.
        scheduleCompletionCleanup()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isPresetFinished, let payload = pendingPayload else { return }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                self.sessionReward = payload
            }

            self.rewardDismissTask?.cancel()
            self.rewardDismissTask = Task { @MainActor [weak self] in
                let duration: TimeInterval = payload.isJackpot ? 6.0 : 4.0
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    self.sessionReward = nil
                }
            }
        }
    }

    // MARK: - Skip previo

    @discardableResult
    func skipToPreviousPhase() -> Bool {
        guard !isPresetFinished else { return false }

        cancelTimer()

        if isBreak {
            // Volver al focus de la MISMA sesión: ese focus ya estaba registrado.
            // Hay que invalidar su record, si no se registraría dos veces (doble chips).
            invalidateRecords(fromSession: currentSession)
            isBreak = false
        } else {
            if currentSession > 1 {
                currentSession -= 1
                isBreak = true
            } else {
                AudioManager.shared.stopBackground()
                stopLiveActivity()
                resetToInitialState()
                return true
            }
        }

        setupPhase()
        isRunning = true
        startTicking()

        if !isBreak {
            AudioManager.shared.playBackground(noiseId: activeConfig.audio.noiseId, freqId: activeConfig.audio.freqId)
        } else {
            AudioManager.shared.pauseBackground()
        }
        savePersistedState()
        broadcastState()
        return false
    }

    // MARK: - Live Activity

    func updateLiveActivity() {
#if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard let targetDate = self.targetDate else { return }

        let updatedState = PomodoroAttributes.ContentState(
            isBreak: self.isBreak,
            currentSession: self.currentSession,
            totalSessions: self.totalSessions,
            targetDate: targetDate,
            noiseId: self.activeConfig.audio.noiseId,
            isRunning: self.isRunning,
            pausedSeconds: self.isRunning ? nil : Int(ceil(self.secondsRemaining)),
            reward: nil
        )

        let content = ActivityContent(state: updatedState, staleDate: nil)

        Task {
            await withTaskGroup(of: Void.self) { group in
                // Solo Pomodoro: antes pisaba también la isla de Free Mode (isFreeMode volvía a false).
                for activity in Activity<PomodoroAttributes>.activities where !activity.content.state.isFreeMode {
                    group.addTask {
                        await activity.update(content)
                    }
                }
            }
        }
#endif
    }

    private func updateLiveActivityWithReward(_ payload: SessionRewardPayload) {
        guard !isMirror else { return }
#if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }

        let effectiveTargetDate = self.targetDate ?? Date()

        let state = PomodoroAttributes.ContentState(
            isBreak: self.isBreak,
            currentSession: self.currentSession,
            totalSessions: self.totalSessions,
            targetDate: effectiveTargetDate,
            noiseId: self.activeConfig.audio.noiseId,
            isRunning: false,
            pausedSeconds: 0,
            reward: payload
        )

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(15)
        )
#if DEBUG
        print("🎁 [Reward LA] Actualizando LA con reward. Activas: \(Activity<PomodoroAttributes>.activities.count)")
#endif

        Task {
            for activity in Activity<PomodoroAttributes>.activities where !activity.content.state.isFreeMode {
                await activity.update(content)
            }
        }
#endif
    }

    func handlePendingWidgetCommands() {
        handleWidgetCommand()
    }

    // MARK: - Control de Ciclo de Vida

    func sceneMovedToBackground() {
        guard !isMirror, isRunning, targetDate != nil else { return }
        savePersistedState()
    }

    func sceneMovedToForeground() {
        // El mirror NO reconcilia fases (registraría focus que no son suyos):
        // solo refresca su display y espera el próximo estado del Master.
        if isMirror {
            mirrorTick()
            syncEngine?.sendMirrorCommand(.requestState)
            return
        }
        resumeTimerAfterReconciliation(checkForKill: false)
    }

    // MARK: - Motor Interno

    private func wasAppContinuouslyRunning() -> Bool {
        let lastSave = UserDefaults.standard.double(forKey: "session_lastSaveTimestamp")
        guard lastSave > 0 else { return false }
        let delta = Date().timeIntervalSince1970 - lastSave
        return delta < 5.0
    }

    /// La app murió sin LA viva. Registramos la sesión como interrumpida (sin chips),
    /// invalidamos la corrida y dejamos el timer PAUSADO donde quedó.
    private func pauseOfflineSession(savedSeconds: Int) {
        // El chequeo de "ya registrada" se hace ANTES de invalidar y acotado a la corrida
        // (antes miraba cualquier record del día con mismo nombre y número, y podía
        // descartar la interrupción por culpa de una corrida anterior).
        let alreadyRecorded = isBreak || SessionStore.shared
            .records(forPresetRunId: currentPresetRunId)
            .contains { $0.sessionNumber == currentSession && !$0.presetInvalidated }

        invalidateCurrentPresetRunIfNeeded()
        currentPresetRunId = UUID()
        presetHasSkip = false

        if !isBreak && !alreadyRecorded {
            SessionStore.shared.recordInterruptedSession(
                presetName: activeConfig.name,
                focusMinutes: activeConfig.focus,
                sessionNumber: currentSession,
                breakMinutes: activeConfig.breakTime,
                totalSessions: totalSessions,
                presetRunId: currentPresetRunId
            )
        }

        isRunning = false
        targetDate = nil
        hasAutoNavigatedForCurrentSession = false

        let maxSeconds = Int(totalSecondsForCurrentPhase)
        if savedSeconds > 0 && savedSeconds <= maxSeconds {
            secondsRemaining = TimeInterval(savedSeconds)
        } else {
            secondsRemaining = totalSecondsForCurrentPhase
        }
        updateUIState()

        AudioManager.shared.stopBackground()
        AudioManager.shared.keepAppAlive(enable: false)
        stopLiveActivity()

        savePersistedState()
    }

    /// Reconcilia el timer con el paso del tiempo.
    private func resumeTimerAfterReconciliation(savedSeconds: Int = 0, checkForKill: Bool = false) {
        guard !isMirror, isRunning, targetDate != nil else { return }

        if checkForKill && !wasAppContinuouslyRunning() {
            pauseOfflineSession(savedSeconds: savedSeconds)
            return
        }

        cancelTimer()
        guard reconcileExpiredPhases() else { return }

        guard let targetDate else { return }
        secondsRemaining = max(0, targetDate.timeIntervalSinceNow)
        updateUIState()

        if isBreak {
            AudioManager.shared.pauseBackground()
        } else {
            AudioManager.shared.playBackground(
                noiseId: activeConfig.audio.noiseId,
                freqId: activeConfig.audio.freqId
            )
            AudioManager.shared.resumeIfNeeded()
        }

        startTicking(reusingTargetDate: true)
    }

    @discardableResult
    private func reconcileExpiredPhases() -> Bool {
        guard var phaseEndDate = targetDate else { return false }
        let now = Date()

        while phaseEndDate <= now {
            if isBreak {
                currentSession += 1
                isBreak = false
            } else if currentSession >= totalSessions {
                let record = recordFocusCompletion()
                pendingPresetRecordIds.append(record.id)
                AudioManager.shared.stopBackground()
                isRunning = false
                targetDate = nil
                stopLiveActivity()
                finalizePreset(silent: true)
                return false
            } else {
                let record = recordFocusCompletion()
                pendingPresetRecordIds.append(record.id)
                isBreak = true
            }

            setupPhase()
            // `max(1, …)` evita un loop infinito si una fase dura 0 min.
            phaseEndDate = phaseEndDate.addingTimeInterval(max(1, totalSecondsForCurrentPhase))
            targetDate = phaseEndDate
        }

        return true
    }

    /// Arranca el tick del timer.
    ///
    /// `targetDate` es la ÚNICA fuente de verdad del reloj: de ahí cuentan el Master
    /// (`handleTick`), el Mirror (`mirrorTick`), la Live Activity, el widget y la
    /// reconciliación. Al reanudar tras una pausa se recalcula desde `secondsRemaining`
    /// (congelado al pausar), así la cuenta continúa donde quedó.
    private func startTicking(reusingTargetDate: Bool = false) {
        AudioManager.shared.keepAppAlive(enable: true)
        if !reusingTargetDate {
            targetDate = Date().addingTimeInterval(secondsRemaining)
        }

        cancelTimer()

        // 0.25 s: el display redondea hacia arriba (ceil), con 1 s fijo el segundero
        // podía saltear o repetir un número. `updateUIState` solo publica si algo cambió.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if let target = targetDate {
            startLiveActivity(target: target)
        }
        savePersistedState()
        broadcastState()
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
        phaseAdvanceTask?.cancel()
        phaseAdvanceTask = nil
    }

    // MARK: - Sincronización del timer con widgets

    private struct TimerWidgetSnapshot: Equatable {
        let isRunning: Bool
        let isBreak: Bool
        let currentSession: Int
        let totalSessions: Int
        let targetDate: Date?
        let pausedSeconds: Int?
        let noiseId: Int
        let presetName: String
    }

    private static var lastWidgetSnapshot: TimerWidgetSnapshot?

    private func syncWidgetTimerState() {
        let paused: Int? = isRunning ? nil : Int(ceil(secondsRemaining))
        let snapshot = TimerWidgetSnapshot(
            isRunning: isRunning,
            isBreak: isBreak,
            currentSession: currentSession,
            totalSessions: totalSessions,
            targetDate: targetDate,
            pausedSeconds: paused,
            noiseId: activeConfig.audio.noiseId,
            presetName: activeConfig.name
        )

        guard snapshot != Self.lastWidgetSnapshot else { return }
        Self.lastWidgetSnapshot = snapshot

        let state = WidgetTimerState(
            isRunning: isRunning,
            isBreak: isBreak,
            currentSession: currentSession,
            totalSessions: totalSessions,
            targetDate: targetDate,
            pausedSeconds: paused,
            noiseId: activeConfig.audio.noiseId,
            presetName: activeConfig.name
        )

        WidgetShared.writeTimerState(state)
        WidgetShared.reloadWidgets()
    }

    /// Sincroniza LA + widget con el estado actual del VM.
    private func syncSystemUI() {
        if isActive {
            let target = targetDate
                ?? Date().addingTimeInterval(TimeInterval(max(0, secondsRemaining)))
            startLiveActivity(target: target)
        } else {
            stopLiveActivity()
        }
        syncWidgetTimerState()
    }

    private func stopTicking() {
        cancelTimer()
        AudioManager.shared.keepAppAlive(enable: false)
        targetDate = nil
        stopLiveActivity()
    }

    private func setupPhase() {
        totalSecondsForCurrentPhase = phaseTotalSeconds()
        secondsRemaining = totalSecondsForCurrentPhase
        lastPlayedCountdownSecond = -1
        updateUIState()
    }

    private func handleTick() {
        // `isRunning` en el guard: el Timer despacha a un Task, así que un tick ya
        // encolado puede ejecutarse DESPUÉS de pausar. Sin esto pisaba el valor congelado.
        guard !isMirror, isRunning, let target = targetDate else { return }

        // `targetDate` es la fuente de verdad (la misma que usan Mirror, LA y widget).
        secondsRemaining = max(0, target.timeIntervalSinceNow)

        if Date().timeIntervalSince(lastSyncBroadcast) > 5 {
            lastSyncBroadcast = Date()
            broadcastState()
        }

        let currentSecondInt = Int(ceil(secondsRemaining))
        if currentSecondInt <= 10 && currentSecondInt > 0 {
            if lastPlayedCountdownSecond != currentSecondInt {
                lastPlayedCountdownSecond = currentSecondInt
                AudioManager.shared.playSFX(.countdown)
            }
        }

        if secondsRemaining <= 0 {
            cancelTimer()
            secondsRemaining = 0
            updateUIState()

            // Tarea cancelable: si en estos 0.5 s el usuario hace skip/pausa/stop,
            // `cancelTimer()` la cancela y no se avanza de fase dos veces.
            phaseAdvanceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.phaseAdvanceTask = nil
                self.skipToNextPhase()
            }
        } else {
            updateUIState()
        }
    }

    private func updateUIState() {
        let rawProgress = totalSecondsForCurrentPhase > 0
            ? CGFloat(secondsRemaining / totalSecondsForCurrentPhase)
            : 0.0
        let newProgress = min(1.0, max(0.0, rawProgress))
        if abs(progress - newProgress) > 0.001 {
            progress = newProgress
        }

        let totalSecondsInt = max(0, Int(ceil(secondsRemaining)))
        let minutes = totalSecondsInt / 60
        let seconds = totalSecondsInt % 60

        let newTimeString = String(format: "%02d:%02d", minutes, seconds)
        if timeRemainingString != newTimeString {
            timeRemainingString = newTimeString
        }

        var futureSeconds = 0
        let remainingFocuses = max(0, totalSessions - currentSession)
        if !isBreak {
            let remainingBreaks = remainingFocuses
            futureSeconds = (remainingFocuses * activeConfig.focus * 60)
                          + (remainingBreaks * activeConfig.breakTime * 60)
        } else {
            let remainingBreaks = max(0, totalSessions - currentSession - 1)
            futureSeconds = (remainingFocuses * activeConfig.focus * 60)
                          + (remainingBreaks * activeConfig.breakTime * 60)
        }

        let totalLeftSeconds = totalSecondsInt + futureSeconds
        let hoursLeft = totalLeftSeconds / 3600
        let minutesLeft = (totalLeftSeconds % 3600) / 60

        let newTotalString = hoursLeft > 0
            ? "\(hoursLeft)H \(minutesLeft)M LEFT"
            : "\(minutesLeft)M LEFT"
        if totalTimeRemainingString != newTotalString {
            totalTimeRemainingString = newTotalString
        }
    }

    // MARK: - Live Activities Engine

    private func startLiveActivity(target: Date) {

#if os(iOS) && canImport(ActivityKit)
        print("🎬 [LA] start llamado. enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = PomodoroAttributes.ContentState(
            isBreak: isBreak,
            currentSession: currentSession,
            totalSessions: totalSessions,
            targetDate: target,
            noiseId: activeConfig.audio.noiseId,
            isRunning: self.isRunning,
            pausedSeconds: self.isRunning ? nil : Int(ceil(self.secondsRemaining)),
            reward: nil
        )

        let content = ActivityContent(state: state, staleDate: nil)

        let activeActivities = Activity<PomodoroAttributes>.activities
            .filter {
                LiveActivityFilter.isReusablePomodoro(
                    isActive: $0.activityState == .active,
                    isStale: $0.activityState == .stale,
                    isFreeMode: $0.content.state.isFreeMode
                )
            }

        #if DEBUG
        print("🎬 [LA] startLiveActivity — activas: \(activeActivities.count), knownId: \(currentActivityId ?? "nil")")
        #endif

        if let knownId = currentActivityId,
           let known = activeActivities.first(where: { $0.id == knownId }) {
            Task {
                print("🎬 [LA] update → id=\(known.id) estado=\(known.activityState) isBreak=\(isBreak) target=\(target)")
                await known.update(content)
                print("🎬 [LA] update OK id=\(known.id) estado=\(known.activityState)")
            }
            return
        }

        if let first = activeActivities.first {
            currentActivityId = first.id

            let strays = Array(activeActivities.dropFirst())
            if !strays.isEmpty {
                Task {
                    for stray in strays {
                        await stray.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }

            Task {
                await first.update(content)
            }
            return
        }

        do {
            let attributes = PomodoroAttributes(presetName: activeConfig.name)
            let activity = try Activity<PomodoroAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivityId = activity.id
        } catch {
            print("🎬 [LA] Error creando: \(error.localizedDescription)")
        }
#endif
    }

    private func stopLiveActivity() {
    #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        currentActivityId = nil

        Task {
            for activity in Activity<PomodoroAttributes>.activities
            where LiveActivityFilter.shouldEndAll(
                isFreeMode: activity.content.state.isFreeMode,
                filter: false
            ) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    #endif
    }

    // MARK: - Protocolo Anti-Zombie

    func setupLifecycleObservers() {
        NotificationCenter.default
            .publisher(for: Notification.Name("WidgetCommandReceived"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWidgetCommand()
            }
            .store(in: &observers)
            
        #if os(iOS)
        let darwinNotification = "com.tomiirossi.PomodoroSense.WidgetCommand"
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                let vm = Unmanaged<TimerViewModel>.fromOpaque(observer!).takeUnretainedValue()
                Task { @MainActor in vm.handleWidgetCommand() }
            },
            darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
        #endif
    }

    private func handleWidgetCommand() {
        let defaults = PomodoroSessionStore.shared
        guard let command = defaults.string(forKey: PomodoroWidgetBridge.commandKey) else {
            return
        }

        // Espejo: sólo consumimos comandos de Pomodoro. Los FREE_* los
        // procesa FreeModeViewModel.
        let owned: Set<String> = ["TOGGLE", "SKIP", "STOP"]
        guard owned.contains(command) else {
            #if DEBUG
            print("🔵 [Timer] Ignora comando ajeno: \(command)")
            #endif
            return
        }

        let sentAt = defaults.double(forKey: PomodoroWidgetBridge.commandDateKey)
        defaults.removeObject(forKey: PomodoroWidgetBridge.commandKey)
        defaults.removeObject(forKey: PomodoroWidgetBridge.commandDateKey)

        guard sentAt > 0,
              Date().timeIntervalSince1970 - sentAt < PomodoroWidgetBridge.commandTTL else {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            switch command {
            case "TOGGLE": userToggleTimer()
            case "SKIP":   userSkipNext()
            case "STOP":   userStopAndReset()
            default:       break
            }
        }
    }

    // MARK: - Sincronización (LocalSyncEngine)

    /// Nombre visible por defecto del dispositivo en la red local.
    /// (Sin `nonisolated`: `UIDevice.current` es @MainActor.)
    static var defaultSyncDeviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    func startSyncAsMasterHosting(deviceName: String? = nil) throws -> String {
        let resolvedName = deviceName ?? Self.defaultSyncDeviceName

        detachSyncEngine()

        let engine = LocalSyncEngine(role: .master)
        engine.delegate = self
        syncEngine = engine

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LocalSyncDefaults.enabled)
        defaults.set(LocalSyncRole.master.rawValue, forKey: LocalSyncDefaults.role)
        defaults.set(resolvedName, forKey: LocalSyncDefaults.deviceName)

        do {
            let code = try engine.startAsMasterHosting(deviceName: resolvedName)
            if case .error = engine.currentState {
                defaults.set(false, forKey: LocalSyncDefaults.enabled)
            }
            return code
        } catch {
            // Si falla, no dejamos un engine zombie ni "sync activo" persistido.
            detachSyncEngine()
            throw error
        }
    }

    func startSyncAsMirror(
        pairingCode: String,
        deviceName: String? = nil
    ) {
        let resolvedDeviceName = deviceName ?? Self.defaultSyncDeviceName

        startSync(
            as: .mirror,
            pairingCode: pairingCode,
            deviceName: resolvedDeviceName
        )
    }

    func startSync(
        as role: LocalSyncRole,
        pairingCode: String,
        deviceName: String? = nil
    ) {
        let resolvedDeviceName = deviceName ?? Self.defaultSyncDeviceName

        detachSyncEngine()

        let engine = LocalSyncEngine(role: role)
        engine.delegate = self
        syncEngine = engine

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LocalSyncDefaults.enabled)
        defaults.set(role.rawValue, forKey: LocalSyncDefaults.role)
        defaults.set(resolvedDeviceName, forKey: LocalSyncDefaults.deviceName)

        engine.start(
            pairingCode: pairingCode,
            deviceName: resolvedDeviceName
        )

        if case .error = engine.currentState {
            defaults.set(false, forKey: LocalSyncDefaults.enabled)
        }
    }

    func reconnectToKnownPeer(_ peer: KnownPeer) {
        let name = Self.defaultSyncDeviceName

        detachSyncEngine()
        let engine = LocalSyncEngine(role: peer.lastRole)
        engine.delegate = self
        syncEngine = engine

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LocalSyncDefaults.enabled)
        defaults.set(peer.lastRole.rawValue, forKey: LocalSyncDefaults.role)
        defaults.set(name, forKey: LocalSyncDefaults.deviceName)

        engine.startReconnect(pairingCode: peer.pairingCode, deviceName: name)

        if case .error = engine.currentState {
            defaults.set(false, forKey: LocalSyncDefaults.enabled)
        }
    }

    /// Reanuda el sync al abrir la app si estaba activo.
    func restoreSyncIfNeeded() async {
            // Cambiamos "?? true" por "?? false"
            guard UserDefaults.standard.object(forKey: "mirror_mode_enabled") as? Bool ?? false else {
                return
            }
            
            let defaults = UserDefaults.standard
        guard defaults.bool(forKey: LocalSyncDefaults.enabled),
              let rawRole = defaults.string(forKey: LocalSyncDefaults.role),
              let role = LocalSyncRole(rawValue: rawRole),
              let psk = try? LocalSyncTransport.loadPSK() else {
            startStandbyIfPossible()
            return
        }

        let name = defaults.string(forKey: LocalSyncDefaults.deviceName) ?? Self.defaultSyncDeviceName

        detachSyncEngine()   // deja `enabled = false`…
        defaults.set(true, forKey: LocalSyncDefaults.enabled)   // …así que lo volvemos a marcar.

        let engine = LocalSyncEngine(role: role)
        engine.delegate = self
        syncEngine = engine
        engine.resume(pairingKey: psk, deviceName: name)
    }

    /// - Parameter rejectInboundFor: tras un Unlink propio, segundos en los que el standby
    ///   rechaza conexiones entrantes (evita que un peer que se perdió el aviso re-vincule solo).
    func startStandbyIfPossible(rejectInboundFor seconds: TimeInterval = 0) {
            // Cambiamos "?? true" por "?? false"
            guard UserDefaults.standard.object(forKey: "mirror_mode_enabled") as? Bool ?? false else {
                return
            }
            
            guard syncEngine == nil else { return }
        guard let peer = SyncPersistence.shared.knownPeers.max(by: { $0.lastConnected < $1.lastConnected }) else { return }

        let engine = LocalSyncEngine(role: peer.lastRole)
        engine.delegate = self
        syncEngine = engine
        engine.startStandby(pairingCode: peer.pairingCode,
                            deviceName: Self.defaultSyncDeviceName,
                            rejectInboundFor: seconds)
    }

    func refreshSyncDiscovery() async {
        guard syncEngine != nil, !syncState.isConnected else { return }
        await restoreSyncIfNeeded()
    }

    /// Detiene el engine sin que sus callbacks vuelvan al ViewModel.
    private func detachSyncEngine() {
        let engine = syncEngine
        syncEngine = nil
        engine?.delegate = nil
        engine?.stop()
        syncState = .idle
        UserDefaults.standard.set(false, forKey: LocalSyncDefaults.enabled)
        // Sin sesión de sync no hay motivo para mantener la app despierta en segundo plano.
        SyncKeepAlive.shared.setEnabled(false)
    }

    private func handleConnectionDropped() {
        guard isMirror else { return }

        #if DEBUG
        print("🔌 handleConnectionDropped — isMirror: \(isMirror) (grace 15s)")
        #endif

        disconnectGraceTask?.cancel()
        disconnectGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            self.performDisconnectTeardown()
            self.startStandbyIfPossible()
        }
    }

    private func performDisconnectTeardown() {
        #if DEBUG
        print("🔌 performDisconnectTeardown — ejecutando teardown real")
        #endif

        disconnectGraceTask = nil
        detachSyncEngine()
        wantsToNavigateToTimer = false

        guard isMirror else { return }
        isMirror = false
        restoreStateAfterLeavingMirror()
    }

    /// Devuelve el VM a su estado previo a ser Mirror. Debe llamarse con `isMirror == false`.
    /// Lo comparten desconexión, "Desvincular" y cambio de rol mirror → master.
    private func restoreStateAfterLeavingMirror() {
        _ = SessionStore.shared.purgeRemoteOnlyRecords()

        let snapshot = preMirrorSnapshot
        let savedConfig = preMirrorActiveConfig
        preMirrorSnapshot = nil
        preMirrorActiveConfig = nil
        isMirroringActiveSession = false
        hasAutoNavigatedForCurrentSession = false
        wantsToNavigateToTimer = false
        cancelTimer()

        guard SyncPersistence.shared.resumePreMirrorSession else {
            stopAndReset()
            syncSystemUI()
            return
        }

        if let snapshot {
            activeConfig = snapshot.config
            currentTheme = ThemeManager.getTheme(for: snapshot.config.audio.noiseId)
            isRunning = snapshot.isRunning
            isBreak = snapshot.isBreak
            currentSession = snapshot.currentSession
            totalSessions = snapshot.totalSessions
            targetDate = snapshot.targetDate
            secondsRemaining = snapshot.secondsRemaining
            // El total de la fase pudo ser alterado por el display mirror: se recalcula.
            totalSecondsForCurrentPhase = phaseTotalSeconds()
            updateUIState()

            if isRunning, targetDate != nil {
                // Reconcilia: si mientras tanto terminaron fases, las registra/avanza
                // (antes se perdían y la sesión quedaba trabada).
                resumeTimerAfterReconciliation(checkForKill: false)
            } else if isRunning {
                isRunning = false
            } else if targetDate != nil {
                // Pausado: refrescamos el placeholder para que `isActive` siga siendo true.
                targetDate = Date().addingTimeInterval(secondsRemaining)
            }
        } else if let savedConfig {
            activeConfig = savedConfig
            totalSessions = savedConfig.sessions
            currentTheme = ThemeManager.getTheme(for: savedConfig.audio.noiseId)
            resetToInitialState()
        } else {
            resetToInitialState()
        }

        savePersistedState()
        syncSystemUI()
    }

    /// Se llama cuando la conexión queda establecida y ya se conoce el rol.
    private func handleRoleAssigned(_ role: LocalSyncRole, peerName: String) {
        // El rol lo define la dirección TCP: se persiste para la próxima restauración.
        UserDefaults.standard.set(role.rawValue, forKey: LocalSyncDefaults.role)
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil
        let wasMirror = isMirror
        isMirror = (role == .mirror)

        if role == .mirror {
            if !wasMirror {
                preMirrorSnapshot = MirrorSnapshot(
                    config: activeConfig,
                    isRunning: isRunning,
                    isBreak: isBreak,
                    currentSession: currentSession,
                    totalSessions: totalSessions,
                    targetDate: targetDate,
                    secondsRemaining: secondsRemaining,
                    progress: progress,
                    timeRemainingString: timeRemainingString,
                    totalTimeRemainingString: totalTimeRemainingString
                )
                preMirrorActiveConfig = activeConfig

                cancelTimer()
                AudioManager.shared.stopBackgroundImmediate()
                AudioManager.shared.keepAppAlive(enable: false)
                stopLiveActivity()
                syncWidgetTimerState()
            }
        } else {
            isMirroringActiveSession = false
            if wasMirror {
                // Antes solo se restauraba la config; ahora también la sesión.
                restoreStateAfterLeavingMirror()
            }
            broadcastState()
        }

        if let code = syncEngine?.currentPairingCode {
            let peer = KnownPeer(
                name: peerName,
                pairingCode: code,
                lastRole: role,
                lastConnected: Date()
            )
            SyncPersistence.shared.addOrUpdateKnownPeer(peer)
        }
    }

    // MARK: - Intenciones desde la UI

    func userToggleTimer() {
        #if DEBUG
        print("🎮 userToggleTimer — isMirror: \(isMirror), isRunning: \(isRunning)")
        #endif

        if isMirror {
            if isMirroringActiveSession {
                syncEngine?.sendMirrorCommand(.toggleTimer)
            } else {
                Task { await self.unlinkAndStartOwnSession() }
            }
        } else {
            toggleTimer()
        }
    }

    func userStartNewSession(with config: PomodoroConfigDTO) {
        if isMirror {
            Task { await self.unlinkAndLoad(config, autoStart: true) }
        } else {
            loadConfiguration(config, autoStart: true)
        }
    }

    /// Sale del modo Mirror de forma limpia para usar el dispositivo localmente.
    private func leaveMirrorForLocalUse() async {
        await syncEngine?.notifyUnlink()

        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil

        isMirror = false
        isMirroringActiveSession = false
        detachSyncEngine()
        startStandbyIfPossible(rejectInboundFor: Self.unlinkQuarantine)
        hasAutoNavigatedForCurrentSession = false
        preMirrorSnapshot = nil

        _ = SessionStore.shared.purgeRemoteOnlyRecords()

        cancelTimer()
        AudioManager.shared.stopBackgroundImmediate()
        AudioManager.shared.keepAppAlive(enable: false)
    }

    private func unlinkAndStartOwnSession() async {
        let saved = preMirrorActiveConfig
        await leaveMirrorForLocalUse()
        preMirrorActiveConfig = nil

        if let saved {
            activeConfig = saved
            totalSessions = saved.sessions   // antes quedaba con las sesiones del Master
            currentTheme = ThemeManager.getTheme(for: saved.audio.noiseId)
        }
        resetToInitialState()

        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !isMirror else { return }

        toggleTimer()
        wantsToNavigateToTimer = true
    }

    private func unlinkAndLoad(_ config: PomodoroConfigDTO, autoStart: Bool) async {
        await leaveMirrorForLocalUse()
        preMirrorActiveConfig = nil
        resetToInitialState()

        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !isMirror else { return }

        loadConfiguration(config, autoStart: autoStart)
        if autoStart { wantsToNavigateToTimer = true }
    }

    func userSkipNext() {
        if isMirror {
            syncEngine?.sendMirrorCommand(.skipNext)
        } else {
            _ = skipToNextPhase(wasCompleted: false)
        }
    }

    func userSkipPrevious() {
        if isMirror {
            syncEngine?.sendMirrorCommand(.skipPrevious)
        } else {
            _ = skipToPreviousPhase()
        }
    }

    /// Salta a una sesión específica del preset (tap en la barra inferior de sesiones).
    ///
    /// - **Forward** (target > actual): la corrida queda invalidada (`presetHasSkip`),
    ///   igual que un skip normal. Cada focus saltado se registra como skipped.
    ///   Se puede saltar varias sesiones de una, también desde un break.
    /// - **Backward** (target < actual, o target == actual estando en break):
    ///   se invalidan los records de sesión >= target (se rehacen) y se conservan los anteriores.
    ///   El flag de skip se recalcula con lo que quedó.
    /// - Siempre se aterriza en el FOCUS de la sesión elegida.
    /// - Corriendo → sigue corriendo. Pausado → pausado. Idle → solo mueve la etiqueta.
    func userSelectSession(_ target: Int) {
        guard !isMirror, !isPresetFinished else { return }
        guard (1...totalSessions).contains(target) else { return }
        guard target != currentSession || isBreak else { return }

        let wasRunning = isRunning
        let wasActive = isActive
        let wasBreak = isBreak
        let isForward = target > currentSession

        cancelTimer()
        AudioManager.shared.pauseBackground()
        AudioManager.shared.keepAppAlive(enable: false)

        if isForward {
            presetHasSkip = true
            if wasActive {
                // En break, el focus de la sesión actual ya estaba completado.
                let firstSkipped = wasBreak ? currentSession + 1 : currentSession
                if firstSkipped < target {
                    for n in firstSkipped..<target {
                        let skipped = SessionStore.shared.recordSkippedSession(
                            presetName: activeConfig.name,
                            focusMinutes: activeConfig.focus,
                            sessionNumber: n,
                            breakMinutes: activeConfig.breakTime,
                            totalSessions: totalSessions,
                            presetRunId: currentPresetRunId
                        )
                        pendingPresetRecordIds.append(skipped.id)
                    }
                }
            }
        } else {
            invalidateRecords(fromSession: target)
        }

        currentSession = target
        isBreak = false
        setupPhase()

        if wasRunning {
            isRunning = true
            startTicking()
            AudioManager.shared.playBackground(
                noiseId: activeConfig.audio.noiseId,
                freqId: activeConfig.audio.freqId
            )
        } else if wasActive {
            isRunning = false
            targetDate = Date().addingTimeInterval(secondsRemaining)
            updateUIState()
            updateLiveActivity()
        } else {
            isRunning = false
            targetDate = nil
            updateUIState()
        }

        savePersistedState()
        broadcastState()
    }

    func disableSync() async {
        await syncEngine?.notifyUnlink()

        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil

        let wasMirror = isMirror

        detachSyncEngine()
        startStandbyIfPossible(rejectInboundFor: Self.unlinkQuarantine)
        isMirror = false
        isMirroringActiveSession = false

        wantsToNavigateToTimer = false

        // Un Master que apaga el sync no tiene nada que restaurar.
        guard wasMirror else { return }

        AudioManager.shared.stopBackgroundImmediate()
        restoreStateAfterLeavingMirror()
    }

    /// Aplica el estado que manda el Master (solo Mirror).
    fileprivate func applyRemoteState(_ state: MasterTimerState) {
        guard isMirror else { return }

        let remoteHasSession = state.targetDate != nil || (state.pausedSeconds ?? 0) > 0
        isMirroringActiveSession = remoteHasSession

        if !remoteHasSession {
            showMirrorIdle()
            return
        }

        self.isRunning = state.isRunning
        self.isBreak = state.isBreak
        self.currentSession = state.currentSession
        self.totalSessions = state.totalSessions
        self.activeConfig.name = state.presetName
        self.activeConfig.audio.noiseId = state.noiseId
        self.activeConfig.audio.freqId = state.freqId
        self.currentTheme = ThemeManager.getTheme(for: state.noiseId)

        if let paused = state.pausedSeconds {
            secondsRemaining = TimeInterval(paused)
            self.targetDate = Date().addingTimeInterval(secondsRemaining)
        } else if let target = state.targetDate {
            self.targetDate = target
            secondsRemaining = max(0, target.timeIntervalSinceNow)
        }

        // El estado del Master no trae las duraciones: usamos las locales pero nunca
        // menos que lo que falta, para que el progreso no pase de 1.0 si las configs difieren.
        totalSecondsForCurrentPhase = max(phaseTotalSeconds(), secondsRemaining)
        updateUIState()

        if state.isRunning {
            ensureMirrorDisplayTimer()
            if !hasAutoNavigatedForCurrentSession {
                hasAutoNavigatedForCurrentSession = true
                wantsToNavigateToTimer = true
            }
        } else {
            cancelTimer()
        }
        syncSystemUI()
    }

    private func showMirrorIdle() {
        cancelTimer()
        isRunning = false
        isBreak = false
        targetDate = nil
        secondsRemaining = 0
        currentSession = 1
        totalSecondsForCurrentPhase = phaseTotalSeconds()

        AudioManager.shared.stopBackgroundImmediate()
        AudioManager.shared.keepAppAlive(enable: false)

        updateUIState()
        syncSystemUI()
    }

    private func ensureMirrorDisplayTimer() {
        guard timer == nil else { return }

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mirrorTick()
            }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func mirrorTick() {
        guard isMirror, let target = targetDate else { return }
        secondsRemaining = max(0, target.timeIntervalSinceNow)
        updateUIState()
    }

    private func killAllLiveActivities() {
#if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        currentActivityId = nil
        Task {
            await withTaskGroup(of: Void.self) { group in
                for activity in Activity<PomodoroAttributes>.activities {
                    group.addTask {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }
        }
#endif
    }

    // MARK: - Persistencia de Estado

    func savePersistedState() {
        guard !isMirror else { return }
        let defaults = UserDefaults.standard
        defaults.set(self.isRunning, forKey: "session_isRunning")
        defaults.set(self.isBreak, forKey: "session_isBreak")
        defaults.set(self.currentSession, forKey: "session_currentSession")
        defaults.set(self.targetDate?.timeIntervalSince1970 ?? 0, forKey: "session_targetDate")
        defaults.set(self.activeConfig.audio.noiseId, forKey: "session_noiseId")
        defaults.set(Int(ceil(self.secondsRemaining)), forKey: "session_secondsRemaining")
        defaults.set(Date().timeIntervalSince1970, forKey: "session_lastSaveTimestamp")
        if let configData = try? JSONEncoder().encode(self.activeConfig) {
            defaults.set(configData, forKey: "session_config")
        }

        defaults.set(currentPresetRunId.uuidString, forKey: "session_currentPresetRunId")
        defaults.set(presetHasSkip, forKey: "session_presetHasSkip")
        if let idsData = try? JSONEncoder().encode(pendingPresetRecordIds) {
            defaults.set(idsData, forKey: "session_pendingPresetRecordIds")
        }

        syncWidgetTimerState()
    }

    // TimerViewModel.swift
    func restorePersistedState() {
        guard SyncPersistence.shared.resumeSessionOnRelaunch else {
            killAllLiveActivities()
            Self.clearPersistedSessionKeys()
            return
        }

        let defaults = UserDefaults.standard
        let wasRunning = defaults.bool(forKey: "session_isRunning")
        let targetTimestamp = defaults.double(forKey: "session_targetDate")
        let savedSeconds = defaults.integer(forKey: "session_secondsRemaining")
        let savedSession = max(1, defaults.integer(forKey: "session_currentSession"))
        let savedIsBreak = defaults.bool(forKey: "session_isBreak")

        // Restaurar corrida ANTES del guard (para poder invalidar huérfanos)
        if let raw = defaults.string(forKey: "session_currentPresetRunId"),
           let id = UUID(uuidString: raw) {
            currentPresetRunId = id
        }
        presetHasSkip = defaults.bool(forKey: "session_presetHasSkip")
        if let idsData = defaults.data(forKey: "session_pendingPresetRecordIds"),
           let ids = try? JSONDecoder().decode([UUID].self, from: idsData) {
            pendingPresetRecordIds = ids
        }

        killAllLiveActivities()

        let hasRunningState = wasRunning && targetTimestamp > 0
        let hasPausedState  = !wasRunning && savedSeconds > 0

        guard hasRunningState || hasPausedState else {
            invalidateCurrentPresetRunIfNeeded()
            currentPresetRunId = UUID()
            presetHasSkip = false
            return
        }

        if let configData = defaults.data(forKey: "session_config"),
           let savedConfig = try? JSONDecoder().decode(PomodoroConfigDTO.self, from: configData) {
            activeConfig = savedConfig
            totalSessions = savedConfig.sessions
            currentTheme = ThemeManager.getTheme(for: savedConfig.audio.noiseId)
        }

        self.isBreak = savedIsBreak
        self.currentSession = savedSession
        totalSecondsForCurrentPhase = phaseTotalSeconds()

        if hasRunningState {
            self.targetDate = Date(timeIntervalSince1970: targetTimestamp)
            self.isRunning = true
            resumeTimerAfterReconciliation(savedSeconds: savedSeconds, checkForKill: true)
        } else {
            // ─── FIX: restaurar estado pausado ───
            isRunning = false
            let maxSeconds = Int(totalSecondsForCurrentPhase)
            if savedSeconds > 0 && savedSeconds <= maxSeconds {
                secondsRemaining = TimeInterval(savedSeconds)
            } else {
                secondsRemaining = totalSecondsForCurrentPhase
            }
            // targetDate "vivo" para que isActive = true y savePersistedState lo
            // conserve. Al darle play, toggleTimer recalcula desde secondsRemaining.
            targetDate = Date().addingTimeInterval(secondsRemaining)
            updateUIState()
        }
    }

    /// STOP del usuario (UI, menú de Mac, Live Activity y comando remoto del Mirror).
    ///
    /// Con los dispositivos vinculados, Stop SIEMPRE desvincula, se toque donde se toque:
    /// - Mirror: le manda `.stop` al Master (que detiene e invalida el preset) y luego se
    ///   desvincula. Los dos mensajes viajan en orden por el mismo socket.
    /// - Master: detiene, avisa `.unlink` al Mirror y se desvincula.
    /// Sin vínculo activo (sync apagado, o esperando al otro lado) solo resetea.
    func userStopAndReset() {
        let isLinked = syncEngine != nil && syncState.isConnected

        if isMirror {
            syncEngine?.sendMirrorCommand(.stop)
        } else {
            stopAndReset()
        }

        guard isLinked, !isUnlinkingFromStop else { return }
        isUnlinkingFromStop = true
        let wasMirror = isMirror
        Task { @MainActor [weak self] in
            guard let self else { return }
            // `disableSync` avisa `.unlink`, apaga el engine y deja al peer en standby.
            // Si somos Mirror, además restaura el estado previo a espejar.
            await self.disableSync()
            // Un Mirror que se desvincula estaba mirando el timer: vuelve a Saved Presets.
            if wasMirror { self.wantsToNavigateToSavedPresets = true }
            self.isUnlinkingFromStop = false
        }
    }

    func clearPersistedState() {
        Self.clearPersistedSessionKeys()
        // El store del widget se vació: forzamos que el próximo sync escriba.
        Self.lastWidgetSnapshot = nil
    }

    private func broadcastSessionEnd() {
        guard !isMirror, let engine = syncEngine else { return }
        let endState = MasterTimerState(
            isRunning: false,
            isBreak: false,
            currentSession: 1,
            totalSessions: totalSessions,
            targetDate: nil,
            pausedSeconds: nil,
            presetName: activeConfig.name,
            noiseId: activeConfig.audio.noiseId,
            freqId: activeConfig.audio.freqId
        )
        engine.sendMasterState(endState)
    }

    private func broadcastState() {
        guard !isMirror, let engine = syncEngine else { return }

        let hasSession = isRunning
            || targetDate != nil
            || currentSession > 1
            || progress < 1.0

        let pausedSeconds: Int? = (!isRunning && hasSession) ? Int(ceil(secondsRemaining)) : nil

        let state = MasterTimerState(
            isRunning: isRunning,
            isBreak: isBreak,
            currentSession: currentSession,
            totalSessions: totalSessions,
            targetDate: isRunning ? targetDate : nil,
            pausedSeconds: pausedSeconds,
            presetName: activeConfig.name,
            noiseId: activeConfig.audio.noiseId,
            freqId: activeConfig.audio.freqId
        )

        engine.sendMasterState(state)
    }

    @MainActor
    static func clearPersistedSessionKeys() {
        PomodoroSessionStore.clear()
    }
}

// MARK: - LocalSyncEngineDelegate

extension TimerViewModel: LocalSyncEngineDelegate {

    func syncEngineDidUpdateState(_ state: LocalSyncEngine.State) {
        let wasConnected = syncState.isConnected
        syncState = state

        switch state {
        case .connected(_, let role, let peerName):
            print("🔗 [Sync] Conectado con '\(peerName)' como \(role.rawValue)")
            // Master Y Mirror: en segundo plano iOS suspende la app y deja de entregar mensajes
            // del socket; la isla del otro lado quedaba con el estado viejo. Se mantiene mientras
            // dure la sesión (también durante una reconexión: `.waiting`/`.error`).
            SyncKeepAlive.shared.setEnabled(true)
            handleRoleAssigned(role, peerName: peerName)

        case .waiting(let error):
            print("⏳ [Sync] Esperando red: \(error.localizedDescription)")
            if wasConnected { handleConnectionDropped() }

        case .error(let error):
            print("❌ [Sync] Error: \(error.localizedDescription)")
            if wasConnected { handleConnectionDropped() }

        case .idle, .hosting, .browsing:
            if wasConnected { handleConnectionDropped() }
        }
    }

    func syncEngineDidReceiveMasterState(_ timerState: MasterTimerState) {
        applyRemoteState(timerState)
    }

    func syncEngineDidReceiveUnlink() {
        #if DEBUG
        print("🔌 [Sync] El peer se desvinculó (isMirror: \(isMirror))")
        #endif

        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil

        guard isMirror else {
            // Master: el engine ya pasó solo a standby. Falta marcar el sync como apagado
            // (si no, al relanzar la app se reanudaba) y soltar el keep-alive de audio.
            UserDefaults.standard.set(false, forKey: LocalSyncDefaults.enabled)
            SyncKeepAlive.shared.setEnabled(false)
            return
        }

        performDisconnectTeardown()
        startStandbyIfPossible()
        // El Master nos desvinculó: no dejamos al Mirror mirando un timer vacío.
        wantsToNavigateToSavedPresets = true
    }

    func syncEngineDidReceiveMirrorCommand(_ command: MirrorCommand) {
        #if DEBUG
        print("🎮 [Sync] Comando remoto: \(command), isMirror: \(isMirror)")
        #endif

        guard !isMirror else { return }

        switch command {
        case .toggleTimer:
            toggleTimer()
        case .skipNext:
            _ = skipToNextPhase(wasCompleted: false)
        case .skipPrevious:
            _ = skipToPreviousPhase()
        case .stop:
            userStopAndReset()
        case .requestState:
            broadcastState()
        }
    }
}

extension LocalSyncEngine.State {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

#if DEBUG
extension TimerViewModel {
    func debugPresetRunIdForTest() -> UUID { currentPresetRunId }
    func debugPendingPresetRecordIdsForTest() -> [UUID] { pendingPresetRecordIds }
    func debugPresetHasSkipForTest() -> Bool { presetHasSkip }
    func debugSecondsRemainingForTest() -> TimeInterval { secondsRemaining }
    func debugTargetDateForTest() -> Date? { targetDate }
    func debugSetCurrentSessionForTest(_ n: Int) { currentSession = n }
    func debugSetIsBreakForTest(_ b: Bool) { isBreak = b }
    func debugSetIsRunningForTest(_ r: Bool) {
        isRunning = r
        if r {
            targetDate = Date().addingTimeInterval(secondsRemaining)
        }
    }
    func debugSetIsMirrorForTest(_ m: Bool) { isMirror = m }
    func debugSetActiveForTest(_ active: Bool) {
        if active && targetDate == nil {
            targetDate = Date().addingTimeInterval(secondsRemaining)
        } else if !active {
            targetDate = nil
        }
    }
}
#endif
