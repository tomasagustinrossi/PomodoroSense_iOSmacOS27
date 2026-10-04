import Foundation
import Network

/// Maneja la visibilidad y búsqueda de pares en la red local.
/// Su única responsabilidad es encontrar el `NWEndpoint` opuesto o aceptar conexiones entrantes.
final class LocalSyncDiscovery {
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let parameters: NWParameters
    
    // MARK: - Callbacks de Estado
    
    /// Se llama cuando el Master publica el servicio exitosamente.
    var onHostReady: ((UInt16) -> Void)?
    
    /// Se llama cuando el Master recibe una solicitud de conexión de un Mirror.
    var onInboundConnection: ((NWConnection) -> Void)?
    
    /// Se llama cuando el Mirror encuentra un Master en la red.
    var onPeerDiscovered: ((NWEndpoint) -> Void)?
    
    init(parameters: NWParameters) {
        self.parameters = parameters
    }
    
    // MARK: - Modo Anfitrión (Master)
    
    /// Inicia la transmisión del servicio Bonjour para que otros dispositivos lo encuentren.
    /// - Parameter name: El nombre visible del dispositivo (ej. "MacBook de Tomás").
    func startHosting(name: String) throws {
        stop()
        
        listener = try NWListener(using: parameters)
        
        listener?.service = NWListener.Service(
            name: name,
            type: LocalSyncTransport.serviceType,
            domain: "local."
        )
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    print("📡 [Discovery] Anfitrión listo en puerto \(port)")
                    self?.onHostReady?(port)
                }
            case .failed(let error):
                print("❌ [Discovery] Error crítico en Listener: \(error)")
                self?.stop()
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            print("📥 [Discovery] Intento de conexión entrante interceptado.")
            self?.onInboundConnection?(connection)
        }
        
        listener?.start(queue: .main)
    }
    
    // MARK: - Modo Cliente (Mirror)
    
    /// Inicia el escaneo pasivo de la red buscando un Master disponible.
    func startBrowsing() {
        stop()
        
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: LocalSyncTransport.serviceType,
            domain: "local."
        )
        
        browser = NWBrowser(for: descriptor, using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            // En una red privada asumimos que el primer resultado válido es nuestro par,
            // ya que el TLS rechazará cualquier intruso de todas formas.
            if let endpoint = results.first?.endpoint {
                print("🔍 [Discovery] Par encontrado: \(endpoint)")
                self?.onPeerDiscovered?(endpoint)
            }
        }
        
        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                print("❌ [Discovery] Error crítico en Browser: \(error)")
                self?.stop()
            }
        }
        
        browser?.start(queue: .main)
    }
    
    // MARK: - Control de Ciclo de Vida
    
    /// Detiene cualquier operación de red activa (Listener o Browser).
    func stop() {
        listener?.cancel()
        listener = nil
        
        browser?.cancel()
        browser = nil
    }
}
