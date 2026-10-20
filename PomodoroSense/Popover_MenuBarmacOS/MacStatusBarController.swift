//
//  MacStatusBarController.swift
//  PomodoroSense
//

#if os(macOS)
import SwiftUI
import AppKit
import Combine

@MainActor
final class MacStatusBarController: NSObject {

    static let shared = MacStatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: MacStatusBarPopover?
    private weak var timerVM: TimerViewModel?
    private weak var presetsVM: PresetsViewModel?
    private weak var freeModeVM: FreeModeViewModel?

    private var observers: [NSObjectProtocol] = []
    private var labelTimer: Timer?
    private var freeModeCancellables = Set<AnyCancellable>()
    private var isConfigured = false

    private var lastTitle: String?
    private var lastSymbol: String?

    private override init() { super.init() }

    // MARK: - Configuración

    func configure(timerVM: TimerViewModel, presetsVM: PresetsViewModel, freeModeVM: FreeModeViewModel) {
        guard !isConfigured else { return }
        isConfigured = true
        self.timerVM = timerVM
        self.presetsVM = presetsVM
        self.freeModeVM = freeModeVM

        let pop = MacStatusBarPopover(width: 260) { [weak self] in
            MenuBarTimerView(
                timerVM: timerVM,
                presetsVM: presetsVM,
                freeModeVM: freeModeVM,
                onDismiss: { completion in self?.popover?.close(then: completion) }
            )
        }
        pop.onClose = { [weak self] in
            self?.refreshVisibility()
        }
        self.popover = pop

        // Suscripción al Free Mode para actualizar el reloj en la barra de Mac
        freeModeVM.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLabel()
                self?.refreshVisibility()
            }
            .store(in: &freeModeCancellables)

        freeModeVM.$elapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                if freeModeVM.isRunning {
                    self?.refreshLabel()
                }
            }
            .store(in: &freeModeCancellables)

        installObservers()
        refreshVisibility()
    }

    // MARK: - Observers

    private func installObservers() {
        let nc = NotificationCenter.default

        let resignActive = nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        let becomeActive = nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        let miniaturize = nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        let deminiaturize = nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        let close = nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closingID = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            Task { @MainActor [weak self] in self?.refreshVisibility(excludingWindowID: closingID) }
        }

        observers = [resignActive, becomeActive, miniaturize, deminiaturize, close]
    }

    // MARK: - Visibilidad

    func refreshVisibility(excludingWindowID closingID: ObjectIdentifier? = nil) {
        if popover?.isShown == true {
            show()
            return
        }

        let hasVisibleWindow = NSApp.windows.contains { window in
            if let closingID, ObjectIdentifier(window) == closingID { return false }
            return window.isVisible && !window.isMiniaturized && window.canBecomeMain
        }

        if NSApp.isActive && hasVisibleWindow {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro Timer")
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        lastTitle = nil
        lastSymbol = nil
        startLabelUpdates()
        refreshLabel()
    }

    private func hide() {
        popover?.close()
        removeStatusItem()
        stopLabelUpdates()
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        lastTitle = nil
        lastSymbol = nil
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        popover?.toggle(relativeTo: sender)
    }

    // MARK: - Label updates

    private func startLabelUpdates() {
        guard labelTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLabel() }
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
        guard let item = statusItem else { return }
        guard let button = item.button else { return }

        let title: String
        let symbol: String
        let symbolDescription: String?

        // Prioridad 1: Free Mode activo
        if let fvm = freeModeVM, fvm.isRunning {
            title = " " + fvm.formattedElapsed
            symbol = "infinity"
            symbolDescription = "Free Mode"
        }
        // Prioridad 2: Pomodoro activo
        else if let vm = timerVM, vm.isActive {
            title = " " + vm.timeRemainingString
            symbol = vm.isBreak ? "cup.and.saucer.fill" : "brain.head.profile"
            symbolDescription = nil
        }
        // Idle
        else {
            title = ""
            symbol = "timer"
            symbolDescription = "Pomodoro Timer"
        }

        guard title != lastTitle || symbol != lastSymbol else { return }
        let symbolChanged = symbol != lastSymbol
        lastTitle = title
        lastSymbol = symbol

        button.title = title
        if symbolChanged {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbolDescription)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            self.popover?.reanchor(relativeTo: button)
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        stopLabelUpdates()
        removeStatusItem()
        popover?.tearDown()
        popover = nil
        freeModeCancellables.removeAll()
    }
}
#endif
