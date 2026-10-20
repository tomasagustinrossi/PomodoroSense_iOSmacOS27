//
//  MacStatusBarPopover.swift
//  PomodoroSense
//
//  Contenedor del popover del status item de macOS.
//
//  Reemplaza a `NSPopover` porque la API del sistema:
//    · No permite re-anclar en caliente (arrow queda al aire al cambiar icono).
//    · No permite animaciones custom (sin rebote, entrada/salida rígidas).
//    · No cierra al clickear la menubar.
//
//  `NSPanel` nos da control total: re-anclaje automático vía observer,
//  animación de entrada con CASpringAnimation (rebote), y monitores
//  propios para cerrar al click fuera / menubar.
//
//  Cambios respecto a la versión anterior:
//    · Una sola fuente de verdad para el frame (`updateFrame`): el panel
//      siempre cuelga del botón, ya no "hereda" el borde superior del frame
//      anterior (evitaba derivas si reanchor y medición se pisaban).
//    · Altura inicial real (fittingSize) en vez de preferredContentSize,
//      que valía 0 porque el controller no es contentViewController.
//    · Si se reabre mientras corre la animación de salida, ya no se oculta
//      el panel por error (transitionID).
//    · Monitor local de clicks: cierra al clickear otra ventana de la propia
//      app (el monitor global solo ve clicks de OTRAS apps).
//    · El panel se mide contra `currentHeight`, no contra panel.frame
//      (que está a mitad de animación mientras cambia de tamaño).
//

#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel que puede volverse key (necesario para el TextField de
/// búsqueda) sin activar la app. Escape cierra.
private final class StatusBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
final class MacStatusBarPopover {

    // MARK: - Configuración

    private let contentWidth: CGFloat
    private let cornerRadius: CGFloat = 12
    private let anchorGap: CGFloat = 6
    private let screenMargin: CGFloat = 8
    private let fallbackHeight: CGFloat = 200

    /// Si es `false`, los cambios de alto/posición se aplican de golpe.
    /// Animarlos con AppKit mientras SwiftUI anima el contenido provocaba
    /// el crash "Update Constraints in Window pass" al pasar de la vista
    /// activa a la de presets. Poné `true` solo para experimentar.
    private let animatesFrameChanges = false

    // MARK: - Estado

    private var panel: StatusBarPanel?
    private var hostingController: NSHostingController<AnyView>?
    private weak var anchorButton: NSStatusBarButton?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var appResignObserver: NSObjectProtocol?
    private var measureTimer: Timer?

    /// Alto objetivo actual del panel (lo que debería medir al terminar
    /// cualquier animación en curso).
    private var currentHeight: CGFloat = 200

    /// Se incrementa en cada show/close. Permite ignorar el completion de
    /// una animación de salida vieja si el panel se volvió a abrir.
    private var transitionID = 0

    private(set) var isShown = false

    /// Se dispara cuando el panel se cierra por cualquier motivo.
    /// El controller lo usa para reevaluar visibilidad del icono.
    var onClose: (() -> Void)?

    // MARK: - Init

    init<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.contentWidth = width

        let wrapped = AnyView(
            content()
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )

        let hosting = NSHostingController(rootView: wrapped)
        // CLAVE contra el crash "marked as needing another Update Constraints
        // in Window pass": por defecto NSHostingController instala
        // restricciones min/max/intrínsecas que empujan el tamaño de la
        // ventana. Como nosotros manejamos el frame a mano, las apagamos
        // y medimos con `sizeThatFits` (lectura pura).
        hosting.sizingOptions = []
        // Tampoco queremos que SwiftUI "puentee" toolbar/título de escena
        // hacia esta ventana custom: otra fuente de pases de constraints.
        hosting.sceneBridgingOptions = []
        self.hostingController = hosting

        let panel = StatusBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Usamos `contentView` y NO `contentViewController`. Al asignar
        // el controller, AppKit toma el control del tamaño del window y
        // lo sincroniza con `preferredContentSize` en cada layout pass.
        // Como además nosotros llamamos `setFrame` desde `measureAndAdjust`,
        // había dos fuentes de verdad peleando por el mismo frame:
        // el layout entraba en un ciclo síncrono y reventaba el stack
        // (crash en ___chkstk_darwin).
        // El hosting view va dentro de un contenedor plano que sigue al
        // panel por autoresizing (sin constraints), así la ventana nunca
        // participa en los pases de Auto Layout del contenido SwiftUI.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        container.wantsLayer = true
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.wantsLayer = true
        container.addSubview(hosting.view)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.onEscape = { [weak self] in self?.close() }
        self.panel = panel
    }

    // MARK: - Show / Close

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown { close() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let panel, hostingController != nil, !isShown else { return }
        anchorButton = button

        // Invalida cualquier animación de salida pendiente.
        transitionID &+= 1
        panel.contentView?.layer?.removeAllAnimations()

        // Altura real del contenido antes de mostrar (evita el panel de
        // alto 0 y el "salto" al primer poll).
        let measured = measureContentHeight()
        currentHeight = measured > 1 ? measured : fallbackHeight

        let frame = computePanelFrame(for: button, height: currentHeight)
        guard frame != .zero else { return }

        panel.setFrame(frame, display: false)
        panel.alphaValue = 0

        panel.orderFrontRegardless()
        isShown = true

        // La vista re-reproduce la entrada escalonada de los presets.
        NotificationCenter.default.post(name: .statusBarPopoverWillShow, object: nil)

        installMonitors()
        animateIn()
        startMeasuring()
    }

    /// Cierra el panel con animación. `completion` se ejecuta cuando la
    /// animación de salida terminó (o enseguida si ya estaba cerrado), así
    /// se puede encadenar una acción sin que se vea "pisada" por el panel.
    func close(then completion: (() -> Void)? = nil) {
        guard let panel, isShown else {
            completion?()
            return
        }
        isShown = false
        removeMonitors()
        stopMeasuring()

        transitionID &+= 1
        let id = transitionID

        animateOut { [weak self] in
            guard let self else { completion?(); return }
            // Si mientras tanto se reabrió, no tocar el panel.
            if self.transitionID == id {
                panel.orderOut(nil)
                panel.alphaValue = 1
                if let contentLayer = panel.contentView?.layer {
                    contentLayer.transform = CATransform3DIdentity
                }
                self.onClose?()
            }
            completion?()
        }
    }

    /// Recalcula la posición del panel sin cerrarlo. Se llama cuando el
    /// botón del status item cambia de tamaño (por ejemplo al aparecer
    /// o desaparecer el título del timer). Evita el salto de dos pasos.
    func reanchor(relativeTo button: NSStatusBarButton) {
        guard isShown else { return }
        anchorButton = button
        updateFrame(duration: 0.15)
    }

    // MARK: - Frame

    /// Frame del panel colgando del botón, con el alto indicado y
    /// limitado horizontalmente al área visible de la pantalla.
    private func computePanelFrame(for button: NSStatusBarButton, height: CGFloat) -> NSRect {
        guard let buttonWindow = button.window else { return .zero }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let screen = buttonWindow.screen ?? NSScreen.main

        var x = buttonRectOnScreen.midX - contentWidth / 2
        let y = buttonRectOnScreen.minY - height - anchorGap

        if let visible = screen?.visibleFrame {
            let minX = visible.minX + screenMargin
            let maxX = visible.maxX - contentWidth - screenMargin
            x = min(max(x, minX), max(minX, maxX))
        }

        return NSRect(x: x, y: y, width: contentWidth, height: height)
    }

    /// Única función que mueve/redimensiona el panel. Siempre parte del
    /// botón ancla y de `currentHeight`.
    private func updateFrame(duration: TimeInterval) {
        guard let panel, isShown, let button = anchorButton else { return }

        let newFrame = computePanelFrame(for: button, height: currentHeight)
        guard newFrame != .zero, newFrame != panel.frame else { return }

        guard animatesFrameChanges else {
            // Un solo setFrame, sin interpolar: evita que AppKit relayoutee
            // el contenido en cada tick mientras SwiftUI también anima.
            panel.setFrame(newFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    /// Ajusta el frame del panel cuando el contenido cambia de alto,
    /// preservando el borde superior (el ancla visual al icono).
    private func handleContentSizeChange(_ newSize: NSSize) {
        guard isShown, newSize.height > 0 else { return }
        currentHeight = newSize.height
        updateFrame(duration: 0.18)
        animateSettle()
    }

    /// Pequeño "asentamiento" con spring cuando cambia el alto. Solo toca
    /// el transform del layer (Core Animation): no participa en layout ni
    /// en constraints, así que no reintroduce el bucle de Auto Layout.
    private func animateSettle() {
        guard let layer = panel?.contentView?.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = 6
        spring.toValue = 0
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 17
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "settle")
    }

    // MARK: - Animación

    private func animateIn() {
        guard let panel, let contentLayer = panel.contentView?.layer else {
            panel?.alphaValue = 1
            return
        }

        // Estado del modelo en su posición final, sin animar.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        // Fade in del panel completo.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        // Rebote: arranca 16pt más arriba (pegado a la menubar), cae y
        // rebasa levemente el fondo antes de asentarse.
        // ζ ≈ 0.5 → ~16% de overshoot (≈2.5pt): se nota sin ser exagerado.
        // (+y es hacia arriba: el contentView es un NSView plano, no flipped.)
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = 16
        spring.toValue = 0
        spring.mass = 1
        spring.stiffness = 240
        spring.damping = 15.5
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        contentLayer.add(spring, forKey: "entry")
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let panel, let contentLayer = panel.contentView?.layer else {
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { completion() }
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = 0
        anim.toValue = 8
        anim.duration = 0.12
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        contentLayer.add(anim, forKey: "exit")
        contentLayer.transform = CATransform3DMakeTranslation(0, 8, 0)
        CATransaction.commit()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        // Click global (en OTRAS apps / menubar): si es fuera del panel y
        // fuera del botón, cerrar.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isShown else { return }
            let mouse = NSEvent.mouseLocation

            if let panel = self.panel, panel.frame.contains(mouse) { return }

            if let button = self.anchorButton, let w = button.window {
                let r = w.convertToScreen(button.convert(button.bounds, to: nil))
                if r.contains(mouse) { return } // el botón hará toggle
            }

            self.close()
        }

        // Click local (en ventanas de NUESTRA app): el monitor global no
        // los ve, así que sin esto el panel quedaba abierto al clickear la
        // ventana principal.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.isShown else { return event }

            // Click dentro del panel: no cerrar.
            if event.window === self.panel { return event }
            // Click en el botón del status item: lo maneja el toggle.
            if let button = self.anchorButton, event.window === button.window { return event }

            self.close()
            return event
        }

        // App resigna active (⌘Tab, click en otra app).
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    private func removeMonitors() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        globalMouseMonitor = nil
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        localMouseMonitor = nil
        if let obs = appResignObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        appResignObserver = nil
    }

    // MARK: - Medición (polling)

    /// Arranca el poll que mantiene el panel del tamaño del contenido.
    /// Usamos polling en vez de KVO porque `preferredContentSize` de
    /// NSHostingController no es KVO-compliant de forma garantizada:
    /// suscribirse a él causaba un bucle setFrame → layout → KVO → crash.
    /// Con 0.15s de intervalo el costo es despreciable y el resultado,
    /// estable.
    private func startMeasuring() {
        stopMeasuring()
        // Primer ajuste tras el layout inicial.
        DispatchQueue.main.async { [weak self] in self?.measureAndAdjust() }
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.measureAndAdjust() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        measureTimer = t
    }

    private func stopMeasuring() {
        measureTimer?.invalidate()
        measureTimer = nil
    }

    /// Alto que quiere el contenido SwiftUI para el ancho fijo del panel.
    /// `sizeThatFits` es una lectura pura: no toca constraints ni layout
    /// de la ventana, así que no puede realimentar el ciclo.
    private func measureContentHeight() -> CGFloat {
        guard let hosting = hostingController else { return 0 }
        let size = hosting.sizeThatFits(in: NSSize(width: contentWidth, height: 10_000))
        return size.height
    }

    private func measureAndAdjust() {
        guard isShown else { return }

        let targetHeight = max(measureContentHeight(), 1)

        // Se compara contra el alto objetivo, no contra panel.frame: éste
        // está a mitad de camino mientras corre una animación.
        guard abs(targetHeight - currentHeight) > 0.5 else { return }

        handleContentSizeChange(NSSize(width: contentWidth, height: targetHeight))
    }

    // MARK: - Cleanup

    func tearDown() {
        removeMonitors()
        stopMeasuring()
        transitionID &+= 1
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        anchorButton = nil
        isShown = false
    }
}

extension Notification.Name {
    /// Se publica justo antes de mostrar el popover. La vista la usa para
    /// reproducir la entrada escalonada de la lista de presets.
    static let statusBarPopoverWillShow = Notification.Name("PomodoroSense.statusBarPopoverWillShow")
}

#endif
