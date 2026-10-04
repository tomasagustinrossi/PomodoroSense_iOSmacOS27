//
//  MacStatusBarController.swift
//  PomodoroSense
//
//  Controla el ícono del timer en la barra de menú de macOS.
//
//  Estrategia de visibilidad:
//  - OCULTO cuando la app está activa (foreground) Y hay ventana visible.
//  - VISIBLE en cualquier otro caso:
//      · App en background (⌘Tab, click en otra app, ⌘H, escritorio).
//      · Ventana minimizada.
//      · Ventana cerrada.
//
//  Los observers principales son `didResignActive` / `didBecomeActive`.
//  Los de miniaturize / close quedan como refuerzo por si la app sigue
//  activa pero la ventana no está visible.
//

#if os(macOS)
import SwiftUI
import AppKit

@MainActor
final class MacStatusBarController: NSObject {

    static let shared = MacStatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var timerVM: TimerViewModel?
    private weak var presetsVM: PresetsViewModel?

    private var observers: [NSObjectProtocol] = []
    private var labelTimer: Timer?
    private var isConfigured = false

    private override init() { super.init() }

    // MARK: - Configuración

    /// Se llama una sola vez cuando la Scene principal aparece.
    func configure(timerVM: TimerViewModel, presetsVM: PresetsViewModel) {
        guard !isConfigured else { return }
        isConfigured = true
        self.timerVM = timerVM
        self.presetsVM = presetsVM

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(
            rootView: MenuBarTimerView(timerVM: timerVM, presetsVM: presetsVM)
        )
        self.popover = pop
        installObservers()
        refreshVisibility()
    }

    // MARK: - Observers

    private func installObservers() {
        let nc = NotificationCenter.default

        // La app pasa a background (⌘Tab, click en otra app, ⌘H, dock de
        // otra app, click en el escritorio) → mostrar status item.
        let resignActive = nc.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibility() }
        }

        // La app vuelve al foreground → puede ocultar (si hay ventana visible).
        let becomeActive = nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibility() }
        }

        // Refuerzos: cambios en la ventana mientras la app sigue activa.
        let miniaturize = nc.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibility() }
        }

        let deminiaturize = nc.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibility() }
        }

        let close = nc.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                    Task { @MainActor in self?.refreshVisibility() }
            }

            // Al cerrarse el popover, reevaluamos visibilidad: si la app sigue
            // activa y hay ventana visible, ahí sí ocultamos el icono.
            let popoverClosed = nc.addObserver(
                    forName: NSPopover.didCloseNotification,
                    object: nil, queue: .main
            ) { [weak self] _ in
                    Task { @MainActor in self?.refreshVisibility() }
            }

            observers = [resignActive, becomeActive, miniaturize, deminiaturize, close, popoverClosed]
    }

    // MARK: - Visibilidad

    /// Decide si el status item debe estar visible u oculto.
    ///
    /// Regla: ocultar solo si la app está activa Y hay alguna ventana
    /// principal visible. En cualquier otro caso, mostrar.
    func refreshVisibility() {
            // Si el popover está abierto, NUNCA ocultar el icono: el usuario
            // está interactuando con él. Sin este guard, el simple hecho de
            // clickear el ítem del menubar dispara `didBecomeActive` y el icono
            // se esfuma mientras el popover está abierto.
            if popover?.isShown == true {
                show()
                return
            }

            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible
                    && !window.isMiniaturized
                    && window.canBecomeMain
            }

            if NSApp.isActive && hasVisibleWindow {
                hide()
            } else {
                show()
            }
    }

    // MARK: - Show / Hide

    private func show() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "timer",
                accessibilityDescription: "Pomodoro Timer"
            )
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        startLabelUpdates()

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = false
        if let timerVM = timerVM, let presetsVM = presetsVM {
            pop.contentViewController = NSHostingController(
                rootView: MenuBarTimerView(timerVM: timerVM, presetsVM: presetsVM)
            )
        }
        self.popover = pop

        startLabelUpdates()
    }

    private func hide() {
        statusItem = nil
        stopLabelUpdates()
        // No nilificamos `popover`: se reutiliza en la próxima aparición,
        // así la apertura no reconstruye el árbol SwiftUI y se ve fluida.
    }

    // MARK: - Popover toggle

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Label updates

    private func startLabelUpdates() {
        guard labelTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLabel() }
        }
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common)
        labelTimer = t
    }

    private func stopLabelUpdates() {
        labelTimer?.invalidate()
        labelTimer = nil
    }

    private func refreshLabel() {
        guard let item = statusItem, let vm = timerVM else { return }
        if let button = item.button {
            if vm.isActive {
                button.title = " " + vm.timeRemainingString
                button.image = NSImage(
                    systemSymbolName: vm.isBreak ? "cup.and.saucer.fill" : "brain.head.profile",
                    accessibilityDescription: nil
                )
            } else {
                button.title = ""
                button.image = NSImage(
                    systemSymbolName: "timer",
                    accessibilityDescription: "Pomodoro Timer"
                )
            }
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        stopLabelUpdates()
        statusItem = nil
        popover = nil
    }
}

#endif
