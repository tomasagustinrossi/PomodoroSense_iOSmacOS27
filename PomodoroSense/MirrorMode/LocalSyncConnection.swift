//
//  LocalSyncConnection.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 15/10/2026.
//

import Foundation
import Network

/// Eventos que puede emitir una conexión activa.
enum SyncConnectionEvent {
    case connected
    /// La conexión está esperando red o permisos (por ejemplo, Red Local denegada). Puede recuperarse sola.
    case waiting(Error)
    /// La conexión terminó. Se emite UNA sola vez por conexión.
    case disconnected(Error?)
    case messageReceived(Data)
}

enum SyncConnectionError: Error {
    case frameTooLarge(Int)
    case truncatedFrame
}

/// Envuelve un `NWConnection` para enviar y recibir mensajes con framing TCP:
/// `[4 bytes: tamaño en big-endian][N bytes: JSON]`.
@MainActor
final class LocalSyncConnection {

    /// Tamaño máximo de un mensaje (1 MB). Evita que un par obligue a reservar memoria arbitraria.
    static let maxFrameSize = 1_048_576

    private let connection: NWConnection
    private var hasStarted = false
    private var isReady = false
    private var isClosed = false

    /// Notifica al Engine sobre el estado y los datos recibidos.
    var onEvent: ((SyncConnectionEvent) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Inicia la conexión y comienza el bucle de escucha. Solo se puede llamar una vez.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStateUpdate(state)
            }
        }
        connection.start(queue: .main)
    }

    /// Cierra la conexión. Emite `.disconnected(nil)` si todavía no se había cerrado.
    func stop() {
        close(error: nil)
    }

    // MARK: - Envío

    /// Codifica un objeto a JSON y lo envía con un prefijo de 4 bytes (tamaño).
    func send<T: Encodable>(payload: T) {
        guard isReady, !isClosed else {
            print("⚠️ [Connection] Envío ignorado: la conexión no está lista.")
            return
        }

        do {
            let payloadData = try JSONEncoder().encode(payload)
            guard payloadData.count <= Self.maxFrameSize else {
                print("❌ [Connection] Payload demasiado grande: \(payloadData.count) bytes")
                return
            }

            let length = UInt32(payloadData.count).bigEndian
            let header = withUnsafeBytes(of: length) { Data($0) }
            let frame = header + payloadData

            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    print("❌ [Connection] Error enviando frame: \(error)")
                    self?.close(error: error)
                }
            })
        } catch {
            print("❌ [Connection] Error codificando payload: \(error)")
        }
    }

    /// Envía y espera a que el sistema procese el envío (o a que pase `timeout`).
    /// No cierra la conexión. Se usa para mensajes que NO pueden perderse (p. ej. `.unlink`):
    /// un `sleep` fijo no garantiza que el mensaje haya salido antes de cancelar el socket.
    func sendAndWait<T: Encodable>(payload: T, timeout: Duration = .milliseconds(1500)) async {
        guard isReady, !isClosed else { return }
        guard let data = try? JSONEncoder().encode(payload), data.count <= Self.maxFrameSize else { return }
        let header = withUnsafeBytes(of: UInt32(data.count).bigEndian) { Data($0) }
        let frame = header + data
        let gate = OneShot()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @MainActor @Sendable () -> Void = {
                guard !gate.fired else { return }
                gate.fired = true
                continuation.resume()
            }
            connection.send(content: frame, completion: .contentProcessed { _ in
                Task { @MainActor in finish() }
            })
            // Tope por si el callback nunca llega.
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish()
            }
        }
    }

    @MainActor
    private final class OneShot { var fired = false }

    // MARK: - Estado

    private func handleStateUpdate(_ state: NWConnection.State) {
        guard !isClosed else { return }

        switch state {
        case .ready:
            print("✅ [Connection] Túnel TLS establecido.")
            isReady = true
            onEvent?(.connected)
            readNextFrameHeader()

        case .waiting(let error):
            // Transitorio: la red puede volver. No se cierra; se avisa para que la UI lo muestre.
            print("⏳ [Connection] Esperando: \(error)")
            isReady = false
            onEvent?(.waiting(error))

        case .failed(let error):
            print("🔌 [Connection] Falló: \(error)")
            close(error: error)

        case .cancelled:
            close(error: nil)

        default:
            break
        }
    }

    /// Punto único de cierre: garantiza un solo `.disconnected` y libera los handlers.
    private func close(error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        isReady = false

        connection.stateUpdateHandler = nil
        connection.cancel()
        onEvent?(.disconnected(error))
    }

    // MARK: - Lectura (framing)

    /// Paso 1: lee exactamente 4 bytes con el tamaño del mensaje.
    private func readNextFrameHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, _, error in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }

                if let error {
                    self.close(error: error)
                    return
                }

                // Con minimumIncompleteLength = 4, recibir menos significa que el otro lado cerró.
                guard let content, content.count == 4 else {
                    self.close(error: nil)
                    return
                }

                // loadUnaligned: el Data recibido no garantiza alineación de 4 bytes.
                let length = Int(UInt32(bigEndian: content.withUnsafeBytes {
                    $0.loadUnaligned(as: UInt32.self)
                }))

                guard length <= Self.maxFrameSize else {
                    self.close(error: SyncConnectionError.frameTooLarge(length))
                    return
                }

                if length == 0 {
                    self.readNextFrameHeader()
                } else {
                    self.readFrameBody(length: length)
                }
            }
        }
    }

    /// Paso 2: lee el cuerpo según el tamaño del header.
    private func readFrameBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, _, error in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }

                if let error {
                    self.close(error: error)
                    return
                }

                guard let content else {
                    self.close(error: nil)
                    return
                }

                // Un cuerpo incompleto desincroniza el flujo: es mejor cerrar que seguir leyendo basura.
                guard content.count == length else {
                    self.close(error: SyncConnectionError.truncatedFrame)
                    return
                }

                self.onEvent?(.messageReceived(content))
                self.readNextFrameHeader()
            }
        }
    }
}
