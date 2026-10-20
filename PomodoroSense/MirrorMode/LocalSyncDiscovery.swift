//
//  LocalSyncDiscovery.swift
//  PomodoroSense
//

import Foundation
import Network

/// Maneja la visibilidad y búsqueda de pares en la red local.
/// Su única responsabilidad es encontrar el `NWEndpoint` opuesto o aceptar conexiones entrantes.
///
/// Todo el estado vive en el hilo principal (`@MainActor`); las callbacks de Network
/// se reenvían al main actor antes de tocar propiedades o llamar a tus closures.
///
/// Cada handler comprueba que el listener/browser que lo disparó siga siendo el actual:
/// así un listener viejo (ya cancelado) nunca puede cerrar ni pisar al nuevo.
@MainActor
final class LocalSyncDiscovery {

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let parameters: NWParameters

    // MARK: - Callbacks de estado

    /// El listener publicó el servicio. Entrega el puerto.
    var onHostReady: ((UInt16) -> Void)?

    /// Llegó una conexión entrante. Quien la reciba debe llamar a `LocalSyncConnection.start()`
    /// (o `cancel()` si la descarta).
    var onInboundConnection: ((NWConnection) -> Void)?

    /// El browser vio aparecer un par. Se llama UNA vez por cada par nuevo (no en cada cambio).
    var onPeerDiscovered: ((NWEndpoint) -> Void)?

    /// Un par dejó de estar visible.
    var onPeerLost: ((NWEndpoint) -> Void)?

    /// Listener o browser en espera. Es transitorio (típico cuando el usuario aún no aceptó
    /// el permiso de Red Local, o no hay red). NO es un error: puede recuperarse solo.
    var onWaiting: ((NWError) -> Void)?

    /// Error crítico del listener o del browser (`.failed`). Ya se detuvo el componente que falló.
    var onError: ((NWError) -> Void)?

    init(parameters: NWParameters) {
        self.parameters = parameters
    }

    // MARK: - Modo anfitrión

    /// Publica el servicio Bonjour para que otros dispositivos lo encuentren.
    /// - Parameter name: Nombre del servicio Bonjour (máx. 63 bytes UTF-8).
    func startHosting(name: String) throws {
        stopHosting()

        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(
            name: name,
            type: LocalSyncTransport.serviceType,
            domain: "local."
        )

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        print("📡 [Discovery] Anfitrión listo en puerto \(port)")
                        self.onHostReady?(port)
                    }
                case .waiting(let error):
                    print("⏳ [Discovery] Listener en espera: \(error)")
                    self.onWaiting?(error)
                case .failed(let error):
                    print("❌ [Discovery] Error crítico en Listener: \(error)")
                    self.stopHosting()
                    self.onError?(error)
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else {
                    connection.cancel()
                    return
                }
                print("📥 [Discovery] Conexión entrante.")
                self.onInboundConnection?(connection)
            }
        }

        self.listener = listener
        listener.start(queue: .main)
    }

    func stopHosting() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Modo cliente

    /// Escanea la red buscando pares disponibles.
    func startBrowsing() {
        stopBrowsing()

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: LocalSyncTransport.serviceType,
            domain: "local."
        )
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.browseResultsChangedHandler = { [weak self, weak browser] _, changes in
            // Solo los cambios nuevos, para no reintentar la conexión en cada actualización.
            var added: [NWEndpoint] = []
            var removed: [NWEndpoint] = []
            for change in changes {
                switch change {
                case .added(let result): added.append(result.endpoint)
                case .removed(let result): removed.append(result.endpoint)
                default: break
                }
            }
            guard !added.isEmpty || !removed.isEmpty else { return }

            // Copias inmutables: un `var` no puede capturarse en un Task (Swift 6).
            let addedEndpoints = added
            let removedEndpoints = removed

            Task { @MainActor [weak self, weak browser] in
                guard let self, let browser, self.browser === browser else { return }
                for endpoint in addedEndpoints {
                    print("🔍 [Discovery] Par encontrado: \(endpoint)")
                    self.onPeerDiscovered?(endpoint)
                }
                for endpoint in removedEndpoints {
                    self.onPeerLost?(endpoint)
                }
            }
        }

        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor [weak self, weak browser] in
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .waiting(let error):
                    print("⏳ [Discovery] Browser en espera: \(error)")
                    self.onWaiting?(error)
                case .failed(let error):
                    print("❌ [Discovery] Error crítico en Browser: \(error)")
                    self.stopBrowsing()
                    self.onError?(error)
                default:
                    break
                }
            }
        }

        self.browser = browser
        browser.start(queue: .main)
    }

    /// Llamar apenas haya conexión, para no seguir escaneando.
    func stopBrowsing() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
    }

    // MARK: - Ciclo de vida

    /// Detiene el listener y el browser.
    func stop() {
        stopHosting()
        stopBrowsing()
    }
}
