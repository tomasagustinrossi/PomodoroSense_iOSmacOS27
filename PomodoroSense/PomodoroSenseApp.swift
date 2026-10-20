//
//  PomodoroSenseApp.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 04/10/2026.
//

import SwiftUI

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        // Nota: en iOS moderno esto NO se llama en swipe-kill (solo en casos
        // raros como crash del sistema o presión de memoria severa).
        // La detección real de "app muerta" se hace vía Live Activity
        // al reabrir (ver TimerViewModel.resumeTimerAfterReconciliation).
        //
        // Cerramos Live Activities para no dejar LA colgadas cuando el
        // sistema SÍ nos avisa que va a matar la app.
        LiveActivityCleaner.endAllAndWait()
    }
}
#endif

#if os(macOS)
import AppKit

class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Se ejecuta antes de salir (⌘Q / Quit): desvincula avisando al otro dispositivo.
    static var onWillTerminate: (@MainActor () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let hook = Self.onWillTerminate else { return .terminateNow }
        Task { @MainActor in
            await hook()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // La app sigue viva cuando se cierra la última ventana.
        // El timer, el audio y la barra de menú siguen funcionando.
        // Solo se termina con Quit explícito (⌘Q o desde el dropdown).
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MacDockTileController.shared.tearDown()
        MacStatusBarController.shared.tearDown()
    }
}
#endif

@main
struct PomodoroSenseApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var macDelegate
#endif
    
    /// Instancia única compartida con el status bar de macOS.
    @StateObject private var sharedTimerVM = TimerViewModel()
    
    
    /// Instancia única compartida con el status bar de macOS.
    @StateObject private var sharedPresetsVM = PresetsViewModel(
        repository: UserDefaultsPomodoroRepository()
    )
    
    // Agregá esta propiedad:
    @StateObject private var sharedFreeModeVM = FreeModeViewModel()
    
    var body: some Scene {
        /*
         WindowGroup {
         SimpleSyncTestView(viewModel: TimerViewModel())
         }*/
        // PRUEBA
        WindowGroup {
            PomodoroMinimalistView(
                timerViewModel: sharedTimerVM,
                presetsVM: sharedPresetsVM,
                freeModeVM: sharedFreeModeVM // <-- NUEVO
            )
            .onAppear {
#if os(macOS)
                MacStatusBarController.shared.configure(
                    timerVM: sharedTimerVM,
                    presetsVM: sharedPresetsVM,
                    freeModeVM: sharedFreeModeVM // <-- NUEVO
                )
                MacDockTileController.shared.configure(timerVM: sharedTimerVM)
                let timerVM = sharedTimerVM
                MacAppDelegate.onWillTerminate = { await timerVM.disableSync() }
#endif
            }
        }
#if os(macOS)
        .windowResizability(.contentMinSize)
#endif
    }
}
