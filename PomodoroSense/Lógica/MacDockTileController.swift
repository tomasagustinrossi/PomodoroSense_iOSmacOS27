//
//  MacDockTileController.swift
//  PomodoroSense
//
//  Anima el icono del Dock en macOS:
//  - Anillo de progreso que rodea el icono durante una sesión.
//  - Color según fase (FOCUS = workAccent, BREAK = breakAccent).
//  - Bounce al cambiar de fase (avisar sin sonido).
//
//  Usa NSDockTile.contentView, la API nativa de macOS. No afecta
//  a iOS.
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine

@MainActor
final class MacDockTileController {

    static let shared = MacDockTileController()

    private weak var timerVM: TimerViewModel?
    private var dockView: DockProgressView?
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private var lastPhaseKey: String = ""
    private var isInstalled = false

    private init() {}

    // MARK: - Configuración

    /// Se llama una vez cuando la app arranca. A partir de acá, el
    /// controlador observa al `TimerViewModel` y actualiza el Dock solo.
    func configure(timerVM: TimerViewModel) {
        guard !isInstalled else { return }
        isInstalled = true
        self.timerVM = timerVM

        // Observamos los cambios relevantes para el Dock.
        timerVM.$isRunning
            .combineLatest(timerVM.$isBreak, timerVM.$currentSession)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.onStateChanged()
            }
            .store(in: &cancellables)

        onStateChanged()
    }

    // MARK: - State

    private func onStateChanged() {
        guard let vm = timerVM else { return }

        // Detección de cambio de fase para bounce.
        let newPhaseKey = "\(vm.isBreak ? "B" : "F")-\(vm.currentSession)"
        let didPhaseChange = !lastPhaseKey.isEmpty && lastPhaseKey != newPhaseKey
        lastPhaseKey = newPhaseKey

        if didPhaseChange && vm.isActive {
            bounceDock()
        }

        updateDock()
        manageUpdateTimer()
    }

    // MARK: - Dock

    private func updateDock() {
        guard let vm = timerVM else { return }

        if vm.isActive {
            installDockViewIfNeeded()
            let theme = vm.currentTheme
            let accent = vm.isBreak ? theme.breakAccent : theme.workAccent

            dockView?.ringColor = NSColor(accent)
            dockView?.progress = vm.progress
            dockView?.isRunning = vm.isRunning
            dockView?.needsDisplay = true
            NSApp.dockTile.display()
        } else {
            uninstallDockView()
        }
    }

    private func installDockViewIfNeeded() {
        guard dockView == nil else { return }

        let view = DockProgressView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128)
        )
        dockView = view
        NSApp.dockTile.contentView = view
    }

    private func uninstallDockView() {
        guard dockView != nil else { return }
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
        dockView = nil
    }

    // MARK: - Update timer

    private func manageUpdateTimer() {
        guard let vm = timerVM else { return }

        if vm.isActive {
            guard updateTimer == nil else { return }
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateDock()
                }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            updateTimer = t
        } else {
            updateTimer?.invalidate()
            updateTimer = nil
        }
    }

    // MARK: - Bounce

    private func bounceDock() {
        // `.informationalRequest` rebota una vez. Si la app está activa,
        // no hace nada (por diseño de Apple: no molestar si ya la mirás).
        NSApp.requestUserAttention(.informationalRequest)
    }

    // MARK: - Cleanup

    func tearDown() {
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
        uninstallDockView()
    }
}

// MARK: - Vista custom del Dock

/// Vista que se instala como `contentView` del dock tile. Dibuja el
/// icono original de la app + un anillo de progreso alrededor.
final class DockProgressView: NSView {

    /// Progreso 0..1 (fracción de tiempo restante). 1 = lleno, 0 = vacío.
    var progress: CGFloat = 0
    var ringColor: NSColor = .systemOrange
    var isRunning: Bool = true

    override func draw(_ dirtyRect: NSRect) {
        // 1. Dibujamos el icono de la app original como base.
        NSApp.applicationIconImage?.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        // 2. Anillo de progreso.
        drawProgressRing()
    }

    private func drawProgressRing() {
        guard progress > 0 || !isRunning else { return }

        let inset: CGFloat = 2
        let ringRect = bounds.insetBy(dx: inset, dy: inset)
        let lineWidth: CGFloat = 7
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = (ringRect.width - lineWidth) / 2

        // Fondo del anillo (tenue, siempre visible cuando hay sesión).
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360
        )
        backgroundPath.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.35).setStroke()
        backgroundPath.stroke()

        // Anillo de progreso. Si está pausado, usamos opacidad reducida.
        let alpha: CGFloat = isRunning ? 1.0 : 0.5
        let arc = NSBezierPath()
        let startAngle: CGFloat = 90                  // top
        let endAngle: CGFloat = 90 - (360 * progress) // clockwise
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        ringColor.withAlphaComponent(alpha).setStroke()
        arc.stroke()
    }
}

#endif