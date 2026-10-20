//
//  ToggleTimerIntent.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 07/10/2026.
//
//  IMPORTANTE: este archivo debe tener Target Membership en la app Y en la extensión del widget.
//
import AppIntents
import Foundation
#if os(iOS)
import ActivityKit
#endif

// MARK: - Compatibilidad Multiplataforma (iOS / macOS)
#if os(iOS)
typealias BaseTimerIntent = LiveActivityIntent
#else
typealias BaseTimerIntent = AppIntent
#endif

// MARK: - Estado de sesión compartido
enum PomodoroSessionStore {

    /// ID del App Group compartido entre app y widget.
    /// ⚠️ Debe coincidir EXACTAMENTE con el configurado en ambos targets.
    static let appGroupId = "group.com.tomiirossi.PomodoroSense"

    /// UserDefaults del App Group. Compartido entre app y extensión.
    static var shared: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    /// Claves de la sesión en curso que se borran al detener el timer.
    private static let sessionKeys = [
        "session_isRunning",
        "session_isBreak",
        "session_currentSession",
        "session_targetDate",
        "session_noiseId",
        "session_config",
        "session_secondsRemaining",
        "session_lastSaveTimestamp",
        // Fase 1: estado de la corrida del preset.
        "session_currentPresetRunId",
        "session_pendingPresetRecordIds",
        "session_presetHasSkip"
    ]

    @MainActor
    static func clear() {
        // Limpiamos App Group (fuente de verdad desde que hay widgets).
        let sharedDefaults = shared
        sessionKeys.forEach { sharedDefaults.removeObject(forKey: $0) }

        // Limpiamos también `.standard` por backward compat.
        let standardDefaults = UserDefaults.standard
        sessionKeys.forEach { standardDefaults.removeObject(forKey: $0) }
    }
}

// MARK: - Live Activities

enum PomodoroLiveActivity {

    /// Free Mode usa `targetDate = ahora + freeModeSpan - transcurrido`, así que el
    /// inicio real es `targetDate - freeModeSpan`. La app, el intent y el widget
    /// DEBEN usar este mismo valor.
    static let freeModeSpan: TimeInterval = 24 * 3600

    /// Cierra todas las Live Activities de Pomodoro. No hace nada fuera de iOS.
    static func endAll() async {
        #if os(iOS)
        for activity in Activity<PomodoroAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    #if os(iOS)
    /// Aplica `transform` al estado de las Live Activities de UN solo modo y las actualiza de inmediato.
    /// `freeMode: false` (por defecto) toca solo las de Pomodoro; `freeMode: true` solo las de Free Mode.
    /// Así un intent de Pomodoro nunca pisa la isla de Free Mode, ni al revés.
    static func updateAll(freeMode: Bool = false,
                          _ transform: (inout PomodoroAttributes.ContentState) -> Void) async {
        for activity in Activity<PomodoroAttributes>.activities
        where activity.content.state.isFreeMode == freeMode {
            var state = activity.content.state
            transform(&state)
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    /// `true` si Free Mode está corriendo según la isla, `false` si está pausado,
    /// `nil` si no hay Live Activity de Free Mode.
    static func freeModeIsRunning() -> Bool? {
        Activity<PomodoroAttributes>.activities
            .first(where: { $0.content.state.isFreeMode })?
            .content.state.isRunning
    }
    #endif
}

// MARK: - Puente Widget → App

/// Comandos que el widget le manda a la app.
/// ⚠️ Los `rawValue` son el contrato con el ViewModel: no cambiarlos.
enum WidgetCommand: String {
    case toggle     = "TOGGLE"
    case skip       = "SKIP"
    case stop       = "STOP"
    case freeToggle = "FREE_TOGGLE"
    case freeStop   = "FREE_STOP"
    /// Free Mode: pausar / reanudar EXPLÍCITOS. La isla decide el destino y la app solo lo aplica
    /// (un toggle ciego se desincroniza si la app y la Live Activity no coinciden).
    case freePause  = "FREE_PAUSE"
    case freeResume = "FREE_RESUME"
}

/// Puente de comunicación Widget → App.
enum PomodoroWidgetBridge {

    /// Clave donde se guarda el último comando pendiente.
    static let commandKey = "WidgetCommand"
    /// Clave donde se guarda el timestamp del comando (anti-stale).
    static let commandDateKey = "WidgetCommandDate"
    /// Vida útil del comando (delegado a `SyncBalance`).
    static var commandTTL: TimeInterval { SyncBalance.widgetCommandTTL }

    /// Nombre de la notificación Darwin (entre procesos).
    private static let darwinNotificationName = "com.tomiirossi.PomodoroSense.WidgetCommand"
    /// Nombre de la notificación local (dentro del proceso de la app).
    private static let localNotificationName = NSNotification.Name("WidgetCommandReceived")

    @MainActor
    static func send(_ command: WidgetCommand) {
        send(command.rawValue)
    }

    @MainActor
    static func send(_ command: String) {
        let defaults = PomodoroSessionStore.shared
        defaults.set(command, forKey: commandKey)
        defaults.set(Date().timeIntervalSince1970, forKey: commandDateKey)

        #if os(iOS)
        // 1. Notificación Darwin (para la app en segundo plano)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName as CFString),
            nil, nil, true
        )
        #endif

        // 2. Notificación local (para el TimerViewModel en primer plano; en macOS es la única vía)
        NotificationCenter.default.post(name: localNotificationName, object: nil)
    }
}

// MARK: - Intents Pomodoro

struct ToggleTimerIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Play/Pause"

    func perform() async throws -> some IntentResult {
        #if os(iOS)
        // Actualizamos la Live Activity inmediatamente para que la UI responda al toque
        await PomodoroLiveActivity.updateAll { state in
            state.isRunning.toggle()

            if !state.isRunning {
                let remaining = max(0, Int(state.targetDate.timeIntervalSinceNow))
                state.pausedSeconds = remaining
            } else {
                state.targetDate = Date().addingTimeInterval(TimeInterval(state.pausedSeconds ?? 0))
                state.pausedSeconds = nil
            }
        }
        #endif

        await MainActor.run {
            PomodoroWidgetBridge.send(.toggle)
        }
        return .result()
    }
}

struct SkipTimerIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Skip Session"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PomodoroWidgetBridge.send(.skip)
        }
        return .result()
    }
}

struct DismissRewardIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Dismiss Reward"

    func perform() async throws -> some IntentResult {
        // Solo cierra las Live Activities. NO toca el timer ni el estado
        // de la app (a diferencia de StopTimerIntent).
        await PomodoroLiveActivity.endAll()
        return .result()
    }
}

struct StopTimerIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Stop Timer"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            // 1. Limpieza directa, SIN depender del ViewModel.
            PomodoroSessionStore.clear()

            // 2. Detener audio e informar al ViewModel si está vivo.
            PomodoroWidgetBridge.send(.stop)
        }

        // 3. Limpieza de Live Activities.
        await PomodoroLiveActivity.endAll()

        return .result()
    }
}

// MARK: - Intents Free Mode

struct PauseFreeModeIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Pause/Play Free Mode"

    func perform() async throws -> some IntentResult {
        #if os(iOS)
        let command = await Self.applyToLiveActivity()
        #else
        let command: WidgetCommand = .freeToggle
        #endif

        await MainActor.run {
            PomodoroWidgetBridge.send(command)
        }
        return .result()
    }

    #if os(iOS)
    /// Actualiza la isla al instante y devuelve el comando EXPLÍCITO que debe aplicar la app.
    /// El destino (pausar/reanudar) se decide una sola vez, mirando la Live Activity.
    @MainActor
    private static func applyToLiveActivity() async -> WidgetCommand {
        // Sin Live Activity de Free Mode: caemos al toggle clásico.
        guard let wasRunning = PomodoroLiveActivity.freeModeIsRunning() else {
            return .freeToggle
        }

        await PomodoroLiveActivity.updateAll(freeMode: true) { state in
            if wasRunning {
                // Guardamos el tiempo TRANSCURRIDO: es el inverso exacto de la fórmula de reanudación.
                let elapsed = PomodoroLiveActivity.freeModeSpan - state.targetDate.timeIntervalSinceNow
                state.isRunning = false
                state.pausedSeconds = max(0, Int(elapsed))
            } else {
                state.targetDate = Date().addingTimeInterval(
                    PomodoroLiveActivity.freeModeSpan - TimeInterval(state.pausedSeconds ?? 0)
                )
                state.isRunning = true
                state.pausedSeconds = nil
            }
        }
        return wasRunning ? .freePause : .freeResume
    }
    #endif
}

struct StopFreeModeIntent: BaseTimerIntent {
    static let title: LocalizedStringResource = "Stop Free Mode"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PomodoroWidgetBridge.send(.freeStop)
        }

        await PomodoroLiveActivity.endAll()

        return .result()
    }
}
