//
//  LocalSyncEngine.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 15/10/2026.
//

import Foundation
import Network
import CryptoKit

/// Delega los eventos lógicos del motor a la UI (ViewModel).
@MainActor
protocol LocalSyncEngineDelegate: AnyObject {
    func syncEngineDidUpdateState(_ state: LocalSyncEngine.State)
    func syncEngineDidReceiveMasterState(_ timerState: MasterTimerState)
    func syncEngineDidReceiveMirrorCommand(_ command: MirrorCommand)
    /// El peer se desvinculó a propósito (botón Unlink). No hay período de gracia.
    func syncEngineDidReceiveUnlink()
}

extension LocalSyncEngineDelegate {
    func syncEngineDidReceiveUnlink() {}
}

@MainActor
final class LocalSyncEngine {

    enum State: Equatable {
        case idle
        case hosting(port: UInt16)
        case browsing
        case connected(peer: NWEndpoint, role: LocalSyncRole, peerName: String)
        case waiting(Error)
        case error(Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.browsing, .browsing):
                return true
            case (.hosting(let l), .hosting(let r)):
                return l == r
            case (.connected(let lp, let lr, let ln), .connected(let rp, let rr, let rn)):
                return lp == rp && lr == rr && ln == rn
            case (.waiting(let l), .waiting(let r)):
                return l.localizedDescription == r.localizedDescription
            case (.error(let l), .error(let r)):
                return l.localizedDescription == r.localizedDescription
            default:
                return false
            }
        }
    }

    // MARK: - Constantes

    /// Tiempo máximo para que una conexión (saliente o entrante) llegue a `.ready`.
    /// Network.framework deja las conexiones rechazadas/inalcanzables en `.waiting`
    /// reintentando indefinidamente: sin este límite una sola conexión muerta
    /// (por ejemplo a un registro Bonjour viejo) bloquea todo lo demás.
    private static let connectTimeout: Duration = .seconds(8)

    /// Tiempo máximo para recibir el `hello` del peer tras establecer TLS.
    private static let helloTimeout: Duration = .seconds(5)

    /// En modo bidireccional, el dispositivo que "espera inbound" marca igual
    /// si pasado este tiempo (más un jitter) no le llegó nada.
    private static let dialFallbackMilliseconds = 1_500

    // MARK: - Estado

    /// Código de pairing canonicalizado actual. Disponible una vez que
    /// el engine arrancó en modo hosting o tras el handshake como mirror.
    private(set) var currentPairingCode: String?

    /// true cuando buscamos Y anunciamos a la vez (reconexión bidireccional).
    /// Se activa tras el primer handshake exitoso, al reconectar con un peer conocido
    /// y al restaurar la sesión: el rol final lo define el `hello`, no quién marca.
    private var isAutoReconnect = false

    /// true en modo "disponible": solo anuncia (no busca ni marca) con la PSK de un peer
    /// conocido, para que ese peer pueda vincularse tocando "Paired" aunque este lado esté
    /// en reposo. No muestra estados ni errores en la UI. Termina al conectarse o al `stop()`.
    private var isStandby = false

    /// Tras un Unlink propio, durante unos segundos el standby NO acepta vínculos: cualquier
    /// conexión entrante (típicamente el peer que se perdió el aviso y reconecta solo) recibe
    /// `.unlink` y se cierra. Pasada la ventana, el peer puede volver a vincularse con "Paired".
    private var rejectInboundUntil: Date?

    private(set) var currentState: State = .idle {
        didSet { delegate?.syncEngineDidUpdateState(currentState) }
    }

    private var localHello: HelloMessage?
    private var peerHello: HelloMessage?
    private var helloTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var dialFallbackTask: Task<Void, Never>?
    private var pendingDialEndpoint: NWEndpoint?
    private var activePeerEndpoint: NWEndpoint?
    private var handshakeComplete = false
    private var connectedPeerName: String?

    private(set) var currentRole: LocalSyncRole
    weak var delegate: LocalSyncEngineDelegate?

    private var discovery: LocalSyncDiscovery?
    private var connection: LocalSyncConnection?

    /// Clave de la sesión actual. Se usa para TODO (listener, browser y conexión saliente),
    /// así los dos lados siempre comparten la misma.
    private var pairingKey: SymmetricKey?
    private var deviceName = ""

    /// true mientras el usuario quiere la sincronización activa (entre `start` y `stop`).
    private var wantsSync = false
    private var reconnectTask: Task<Void, Never>?

    init(role: LocalSyncRole) {
        self.currentRole = role
    }

    // MARK: - Identidad en la red (nombre de servicio Bonjour)

    /// Primeros 8 caracteres hex del peerId propio. Va en el nombre del servicio para
    /// reconocerse a sí mismo y desempatar sin depender del nombre del dispositivo
    /// (en iOS `UIDevice.current.name` suele ser genérico: "iPhone").
    private var myShortId: String {
        String(SyncPersistence.shared.myPeerId.uuidString.prefix(8))
    }

    /// Nombre con el que se publica el servicio: `"<deviceName> [<shortId>]"` (máx. 63 bytes).
    private var publishedName: String {
        Self.makeServiceName(deviceName: deviceName, shortId: myShortId)
    }

    private static func makeServiceName(deviceName: String, shortId: String) -> String {
        var base = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Device" }
        let suffix = " [\(shortId)]"
        let maxBytes = 63 - suffix.utf8.count
        while base.utf8.count > maxBytes { base.removeLast() }
        return base + suffix
    }

    private static func rawServiceName(from endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    /// Separa `"MacBook de Tomás [1A2B3C4D]"` en nombre visible e id.
    /// Si el servicio lo publicó una versión sin sufijo, `id` es nil.
    private static func parseServiceName(_ raw: String) -> (name: String, id: String?) {
        guard raw.hasSuffix("]"), let open = raw.lastIndex(of: "[") else { return (raw, nil) }
        let idStart = raw.index(after: open)
        let idEnd = raw.index(before: raw.endIndex)
        guard idStart <= idEnd else { return (raw, nil) }
        let id = String(raw[idStart..<idEnd])
        guard id.count == 8, id.allSatisfy({ $0.isHexDigit }) else { return (raw, nil) }
        let name = raw[..<open].trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? raw : name, id)
    }

    /// Nombre legible del endpoint (el `deviceName` que publicó el peer).
    static func peerName(from endpoint: NWEndpoint) -> String {
        guard let raw = rawServiceName(from: endpoint) else { return "Unknown Device" }
        return parseServiceName(raw).name
    }

    // MARK: - Control principal

    /// - Parameter pairingCode: Master: `LocalSyncTransport.pairingCode(from:)` de su propia clave.
    ///   Mirror: el código que recibió del Master (QR o texto).
    func start(pairingCode: String, deviceName: String) {
        stop()

        do {
            let key = try LocalSyncTransport.derivePSK(fromRaw: pairingCode)
            try LocalSyncTransport.savePSK(key)
            pairingKey = key
            self.deviceName = deviceName
            self.currentPairingCode = LocalSyncTransport.canonicalize(pairingCode)
            wantsSync = true
            try beginDiscovery()
        } catch {
            wantsSync = false
            currentState = .error(error)
        }
    }

    /// Arranca sin derivar (para restauración: PSK ya en Keychain).
    /// Siempre en modo bidireccional: el otro lado puede estar anunciando o buscando.
    func resume(pairingKey: SymmetricKey, deviceName: String) {
        stop()

        self.pairingKey = pairingKey
        self.deviceName = deviceName
        // Recupera el código del peer conocido cuya PSK coincide, para que el
        // handshake pueda actualizar su `KnownPeer` (rol y fecha) igual que en una conexión nueva.
        self.currentPairingCode = Self.knownPairingCode(matching: pairingKey)
        isAutoReconnect = true
        wantsSync = true

        do {
            try beginAutoReconnectDiscovery()
        } catch {
            wantsSync = false
            currentState = .error(error)
        }
    }

    /// Arranca como Master con un código recién generado.
    /// Devuelve el código formateado (para mostrarlo en QR / copiar).
    /// El PSK ya queda persistido en Keychain.
    @discardableResult
    func startAsMasterHosting(deviceName: String) throws -> String {
        stop()

        let code = try LocalSyncTransport.generatePairingCode()
        let key = try LocalSyncTransport.derivePSK(fromRaw: code)
        try LocalSyncTransport.savePSK(key)

        pairingKey = key
        self.deviceName = deviceName
        self.currentPairingCode = LocalSyncTransport.canonicalize(code)
        wantsSync = true
        try beginDiscovery()

        return code
    }

    /// Reconexión con un peer conocido: arranca hosting Y browse al mismo
    /// tiempo, así no importa quién toca primero. El rol final lo define el
    /// intercambio de `hello` (rol preferido de cada lado), no la dirección TCP.
    func startReconnect(pairingCode: String, deviceName: String) {
        stop()
        do {
            let key = try LocalSyncTransport.derivePSK(fromRaw: pairingCode)
            try LocalSyncTransport.savePSK(key)
            pairingKey = key
            self.deviceName = deviceName
            self.currentPairingCode = LocalSyncTransport.canonicalize(pairingCode)
            isAutoReconnect = true
            wantsSync = true
            try beginAutoReconnectDiscovery()
        } catch {
            wantsSync = false
            currentState = .error(error)
        }
    }

    func stop() {
        wantsSync = false
        isAutoReconnect = false
        isStandby = false
        rejectInboundUntil = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        teardown()
        currentPairingCode = nil
        currentState = .idle
    }

    /// Queda "disponible" para un peer conocido: solo anuncia con su PSK y espera que el otro
    /// lado toque "Paired". Nunca marca por su cuenta, así que no re-vincula solo tras un Unlink.
    /// - Parameter rejectInboundFor: segundos durante los que se rechaza cualquier conexión
    ///   entrante (usar tras un Unlink propio; ver `rejectInboundUntil`).
    func startStandby(pairingCode: String, deviceName: String, rejectInboundFor seconds: TimeInterval = 0) {
        stop()
        rejectInboundUntil = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
        do {
            let key = try LocalSyncTransport.derivePSK(fromRaw: pairingCode)
            pairingKey = key
            self.deviceName = deviceName
            self.currentPairingCode = LocalSyncTransport.canonicalize(pairingCode)
            wantsSync = true
            try beginStandbyDiscovery()
        } catch {
            wantsSync = false
            isStandby = false
            print("⚠️ [Engine] No se pudo iniciar standby: \(error)")
        }
    }

    /// Avisa al peer que nos desvinculamos a propósito y espera un instante a que el
    /// mensaje salga. Después hay que llamar a `stop()` (o descartar el engine).
    func notifyUnlink() async {
        guard handshakeComplete, let conn = connection else { return }
        conn.onEvent = nil   // ignoramos lo que pase mientras se despacha el aviso
        // Espera a que el sistema confirme el envío (antes: sleep fijo de 250 ms).
        await conn.sendAndWait(payload: SyncMessage.unlink)
    }

    /// Conexión entrante durante la ventana de rechazo: se le avisa `.unlink` y se cierra.
    private func rejectStrayPeer(_ conn: LocalSyncConnection) {
        print("🚫 [Engine] Standby con Unlink reciente: se rechaza la conexión entrante")
        conn.onEvent = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        connection = nil
        Task { [weak conn] in
            await conn?.sendAndWait(payload: SyncMessage.unlink)
            conn?.stop()
        }
    }

    /// Busca entre los peers conocidos el que deriva exactamente esta PSK.
    private static func knownPairingCode(matching key: SymmetricKey) -> String? {
        let target = key.withUnsafeBytes { Data($0) }
        for peer in SyncPersistence.shared.knownPeers {
            let candidate = LocalSyncTransport.derivePSK(fromCanonical: peer.pairingCode)
            if candidate.withUnsafeBytes({ Data($0) }) == target {
                return peer.pairingCode
            }
        }
        return nil
    }

    // MARK: - Envío

    func sendMasterState(_ state: MasterTimerState) {
        guard currentRole == .master else { return }
        connection?.send(payload: SyncMessage.masterState(state))
    }

    func sendMirrorCommand(_ command: MirrorCommand) {
        guard currentRole == .mirror else { return }
        connection?.send(payload: SyncMessage.mirrorCommand(command))
    }

    // MARK: - Descubrimiento

    /// Descubrimiento de un solo sentido (primer emparejamiento):
    /// el Master anuncia, el Mirror busca.
    private func beginDiscovery() throws {
        guard let key = pairingKey else { return }

        let discovery = LocalSyncDiscovery(parameters: LocalSyncTransport.secureParameters(key: key))
        self.discovery = discovery
        setupDiscoveryCallbacks(discovery, key: key)

        if currentRole == .master {
            currentState = .hosting(port: 0) // El puerto real llega en onHostReady
            try discovery.startHosting(name: publishedName)
        } else {
            currentState = .browsing
            discovery.startBrowsing()
        }
    }

    /// Descubrimiento bidireccional: anuncia y busca a la vez.
    private func beginAutoReconnectDiscovery() throws {
        guard let key = pairingKey else { return }

        let discovery = LocalSyncDiscovery(parameters: LocalSyncTransport.secureParameters(key: key))
        self.discovery = discovery
        setupDiscoveryCallbacks(discovery, key: key)

        currentState = .hosting(port: 0) // El puerto real llega en onHostReady
        try discovery.startHosting(name: publishedName)
        discovery.startBrowsing()
    }

    /// Modo disponible: solo anuncia, no busca ni marca.
    private func beginStandbyDiscovery() throws {
        guard let key = pairingKey else { return }

        isStandby = true
        isAutoReconnect = false

        let discovery = LocalSyncDiscovery(parameters: LocalSyncTransport.secureParameters(key: key))
        self.discovery = discovery
        setupDiscoveryCallbacks(discovery, key: key)

        try discovery.startHosting(name: publishedName)
    }

    /// Reinicia el descubrimiento respetando el modo actual. Es lo que usan los reintentos:
    /// antes siempre caían en el modo de un solo sentido y rompían la reconexión.
    private func restartDiscovery() throws {
        if isStandby {
            try beginStandbyDiscovery()
        } else if isAutoReconnect {
            try beginAutoReconnectDiscovery()
        } else {
            try beginDiscovery()
        }
    }

    /// Cierra discovery y conexión sin tocar `wantsSync`, `isAutoReconnect` ni el estado.
    private func teardown() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        helloTimeoutTask?.cancel()
        helloTimeoutTask = nil
        dialFallbackTask?.cancel()
        dialFallbackTask = nil
        pendingDialEndpoint = nil

        discovery?.stop()
        discovery = nil

        connection?.onEvent = nil // evita eventos de la conexión que estamos cerrando
        connection?.stop()
        connection = nil
        
        handshakeComplete = false
        connectedPeerName = nil
        localHello = nil
        peerHello = nil
        activePeerEndpoint = nil
    }

    /// En modo bidireccional ambos lados ven al otro. Para no marcarse a la vez,
    /// el de id mayor espera un inbound (con salida: ver `onPeerDiscovered`).
    private func shouldWaitForInbound(peerId: String?, peerName: String) -> Bool {
        if let peerId { return myShortId > peerId }
        return deviceName > peerName // peer de una versión sin id en el nombre
    }

    private func setupDiscoveryCallbacks(_ discovery: LocalSyncDiscovery, key: SymmetricKey) {
        discovery.onHostReady = { [weak self] port in
            guard let self, !self.isStandby else { return }
            if case .connected = self.currentState { return }
            self.currentState = .hosting(port: port)
        }

        // Sigue anunciándose hasta que el handshake TLS termine bien (ver `.connected`).
        discovery.onInboundConnection = { [weak self] nwConnection in
            guard let self else { return }
            guard self.wantsSync, self.connection == nil else {
                nwConnection.cancel()
                return
            }
            print("🤝 [Engine] Aceptando conexión entrante")
            self.dialFallbackTask?.cancel()
            self.dialFallbackTask = nil
            self.pendingDialEndpoint = nil
            self.setupActiveConnection(nwConnection, peer: nwConnection.endpoint)
        }

        // Puede haber varios peers en la red; se intenta de a uno.
        discovery.onPeerDiscovered = { [weak self] endpoint in
            guard let self, self.wantsSync, self.connection == nil else { return }
            guard self.currentRole == .mirror || self.isAutoReconnect else { return }

            let raw = LocalSyncEngine.rawServiceName(from: endpoint)
            let (peerName, peerId) = raw.map(LocalSyncEngine.parseServiceName) ?? ("Unknown Device", nil)

            // ⚠️ Filtrar el propio servicio. Bonjour nos muestra en el browser
            // aunque estemos anunciando: sin este guard, el motor intentaría conectar
            // consigo mismo. Se compara por id (no por nombre: dos iPhones se llaman igual).
            if peerId == self.myShortId || raw == self.publishedName {
                return
            }

            if self.isAutoReconnect, self.shouldWaitForInbound(peerId: peerId, peerName: peerName) {
                print("🤝 [Engine] Auto-reconnect: espero inbound de '\(peerName)'; si no llega, marco yo")
                self.pendingDialEndpoint = endpoint
                self.dialFallbackTask?.cancel()
                let jitter = Int.random(in: 0...500)   // evita que ambos marquen en el mismo instante
                self.dialFallbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(LocalSyncEngine.dialFallbackMilliseconds + jitter))
                    guard !Task.isCancelled, let self, self.connection == nil else { return }
                    self.pendingDialEndpoint = nil
                    self.dial(endpoint, key: key)
                }
                return
            }

            self.dial(endpoint, key: key)
        }

        // Si el peer por el que esperábamos desaparece, no marcamos a un endpoint muerto.
        discovery.onPeerLost = { [weak self] endpoint in
            guard let self, self.pendingDialEndpoint == endpoint else { return }
            self.dialFallbackTask?.cancel()
            self.dialFallbackTask = nil
            self.pendingDialEndpoint = nil
        }

        // Transitorio (permiso de Red Local pendiente, sin red…): se informa pero NO se reinicia nada.
        discovery.onWaiting = { [weak self] error in
            guard let self, !self.isStandby else { return }
            if case .connected = self.currentState { return }
            self.currentState = .waiting(error)
        }

        // Error crítico (`.failed`): el componente ya se detuvo; reiniciamos el descubrimiento.
        discovery.onError = { [weak self] error in
            guard let self else { return }
            if case .connected = self.currentState { return }
            if !self.isStandby { self.currentState = .error(error) }
            self.scheduleReconnect(after: .seconds(5))
        }
    }

    private func dial(_ endpoint: NWEndpoint, key: SymmetricKey) {
        guard wantsSync, connection == nil else { return }
        print("🤝 [Engine] Conectando outbound a '\(LocalSyncEngine.peerName(from: endpoint))'")
        let nwConnection = NWConnection(
            to: endpoint,
            using: LocalSyncTransport.secureParameters(key: key)
        )
        setupActiveConnection(nwConnection, peer: endpoint)
    }

    // MARK: - Conexión activa

    private func setupActiveConnection(_ nwConnection: NWConnection, peer: NWEndpoint) {
        let newConnection = LocalSyncConnection(connection: nwConnection)

        newConnection.onEvent = { [weak self, weak newConnection] event in
            guard let self, let newConnection, self.connection === newConnection else { return }

            switch event {
            case .connected:
                if self.isStandby, let until = self.rejectInboundUntil, until > Date() {
                    self.rejectStrayPeer(newConnection)
                    return
                }
                
                if self.handshakeComplete {
                    // Misma conexión recuperada de un .waiting: no rehacer el handshake.
                    let peerEndpoint = self.activePeerEndpoint ?? peer
                    self.currentState = .connected(peer: peerEndpoint,
                                                   role: self.currentRole,
                                                   peerName: self.connectedPeerName ?? "Unknown Device")
                    return
                }
                guard self.localHello == nil else { return }
                
                // TLS establecido. NO notificamos todavía: primero hay que
                // intercambiar `hello` para negociar rol y aprender el nombre.
                self.connectTimeoutTask?.cancel()
                self.connectTimeoutTask = nil
                self.dialFallbackTask?.cancel()
                self.dialFallbackTask = nil
                self.pendingDialEndpoint = nil
                self.discovery?.stop()
                self.activePeerEndpoint = peer
                self.handshakeComplete = false
                self.peerHello = nil
                self.localHello = nil
                self.sendHello()

            case .waiting(let error):
                if self.isStandby && !self.handshakeComplete { return }
                self.currentState = .waiting(error)

            case .disconnected(let error):
                self.connectTimeoutTask?.cancel()
                self.connectTimeoutTask = nil
                self.helloTimeoutTask?.cancel()
                self.helloTimeoutTask = nil
                let strayStandbyAttempt = self.isStandby && !self.handshakeComplete
                self.connection = nil
                self.handshakeComplete = false
                // En standby, un intento ajeno que falla (TLS inválido, etc.) no debe tocar la UI.
                if !strayStandbyAttempt {
                    self.currentState = error.map { .error($0) } ?? .idle
                }
                self.scheduleReconnect()

            case .messageReceived(let data):
                self.handleIncomingData(data)
            }
        }

        connection = newConnection
        armConnectTimeout(for: newConnection)
        newConnection.start()
    }

    /// Si la conexión no llega a `.ready` a tiempo, se abandona y se reinicia el descubrimiento.
    private func armConnectTimeout(for conn: LocalSyncConnection) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self, weak conn] in
            try? await Task.sleep(for: LocalSyncEngine.connectTimeout)
            guard !Task.isCancelled, let self, let conn, self.connection === conn else { return }
            print("⏱ [Engine] Conexión sin establecer tras \(LocalSyncEngine.connectTimeout) — se abandona")
            self.connectTimeoutTask = nil
            conn.onEvent = nil
            conn.stop()
            self.connection = nil
            self.scheduleReconnect(after: .seconds(1))
        }
    }

    private func sendHello() {
        let hello = HelloMessage(
            deviceName: deviceName,
            peerId: SyncPersistence.shared.myPeerId,
            preferredRole: currentRole
        )
        localHello = hello
        connection?.send(payload: SyncMessage.hello(hello))

        // Timeout de seguridad: si no llegó el hello del peer,
        // seguimos con el rol actual y el nombre que publicó Bonjour.
        helloTimeoutTask?.cancel()
        helloTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: LocalSyncEngine.helloTimeout)
            guard !Task.isCancelled, let self, !self.handshakeComplete else { return }
            print("⏱ [Engine] Hello timeout — usando rol local")
            let fallbackName = self.activePeerEndpoint.map { LocalSyncEngine.peerName(from: $0) } ?? "Unknown Device"
            self.finalizeHandshake(peerName: fallbackName)
        }
    }

    private func handleHello(_ hello: HelloMessage) {
        guard !handshakeComplete else { return }
        peerHello = hello
        helloTimeoutTask?.cancel()
        finalizeHandshake(peerName: hello.deviceName)
    }

    private func finalizeHandshake(peerName: String) {
        guard !handshakeComplete else { return }
        handshakeComplete = true
        helloTimeoutTask?.cancel()
        helloTimeoutTask = nil

        // Negociación determinista. Ambos lados corren el mismo algoritmo
        // y llegan al mismo resultado, sin coordinación adicional.
        let finalRole: LocalSyncRole
        if let local = localHello, let peer = peerHello {
            if local.preferredRole != peer.preferredRole {
                finalRole = local.preferredRole
            } else {
                // Mismo rol preferido → desempate por peerId.
                // El UUID lexicográficamente menor gana master.
                finalRole = local.peerId.uuidString < peer.peerId.uuidString ? .master : .mirror
            }
        } else {
            finalRole = currentRole
        }

        currentRole = finalRole

        // Ya emparejados: de acá en adelante cualquier reconexión es bidireccional.
        isAutoReconnect = true
        isStandby = false

        let peer = activePeerEndpoint ?? .hostPort(host: "unknown", port: 0)
        print("🤝 [Engine] Handshake OK — peer='\(peerName)' role=\(finalRole.rawValue)")
        connectedPeerName = peerName
        currentState = .connected(peer: peer, role: finalRole, peerName: peerName)
    }

    // MARK: - Reconexión

    /// Vuelve a anunciarse y/o buscar (según el modo) mientras el usuario siga queriendo sync.
    /// Se agrega un jitter para que los dos lados no reinicien exactamente al mismo tiempo.
    private func scheduleReconnect(after delay: Duration = .seconds(2)) {
        guard wantsSync else { return }

        let jitter = Duration.milliseconds(Int.random(in: 0...800))

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay + jitter)
            guard !Task.isCancelled, let self, self.wantsSync else { return }

            self.teardown()
            do {
                try self.restartDiscovery()
            } catch {
                self.currentState = .error(error)
                self.scheduleReconnect(after: .seconds(5))
            }
        }
    }

    // MARK: - Unlink remoto

    /// El peer se desvinculó a propósito. Pasamos a "disponible" (solo anunciar) en vez de
    /// reconectar solos: así el Unlink se respeta y cualquiera de los dos puede volver a
    /// vincular tocando "Paired".
    private func handleRemoteUnlink() {
        print("🔌 [Engine] El peer se desvinculó")
        delegate?.syncEngineDidReceiveUnlink()
        // Si el delegate nos detuvo (el Mirror vuelve a su estado local), no seguimos.
        guard wantsSync else { return }

        reconnectTask?.cancel()
        reconnectTask = nil
        teardown()
        currentState = .idle
        do {
            try beginStandbyDiscovery()
        } catch {
            print("⚠️ [Engine] No se pudo pasar a standby: \(error)")
        }
    }

    // MARK: - Datos entrantes

    private func handleIncomingData(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(SyncMessage.self, from: data)

            switch message {
            case .hello(let hello):
                handleHello(hello)

            case .masterState(let state):
                guard currentRole == .mirror else { return }
                delegate?.syncEngineDidReceiveMasterState(state)

            case .mirrorCommand(let command):
                guard currentRole == .master else { return }
                delegate?.syncEngineDidReceiveMirrorCommand(command)

            case .roleSwap:
                break

            case .unlink:
                // Sin exigir handshake: el TLS-PSK ya autenticó al peer, y un Unlink puede
                // llegar justo cuando este lado se estaba reconectando.
                handleRemoteUnlink()
            }
        } catch {
            print("❌ [Engine] Error decodificando mensaje: \(error)")
        }
    }
}
