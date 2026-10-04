//
//  SimpleSyncMessage 2.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 14/10/2026.
//


import Foundation
import Network
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Mensaje (una línea de JSON por mensaje)

struct SimpleSyncMessage: Codable {
    var kind: String            // "hello" | "ping" | "state"
    var text: String = ""
    var seconds: Int = 0
    var isRunning: Bool = false
}

// MARK: - Sync mínimo

@MainActor
final class SimpleSync: ObservableObject {

    enum Role: Equatable { case none, master, mirror }

    enum Status: Equatable {
        case idle
        case waiting
        case connecting
        case connected(String)
        case failed(String)
    }

    static let shared = SimpleSync()
    private init() {}

    private let serviceType = "_pomodoro-sync._tcp"
    private let namePrefix = "PSMirror-"

    @Published private(set) var role: Role = .none
    @Published private(set) var status: Status = .idle
    @Published private(set) var log: [String] = []
    @Published private(set) var lastMessage: SimpleSyncMessage?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private var retryTask: Task<Void, Never>?

    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    // MARK: - API

    func startAsMaster() {
        stop()
        role = .master
        status = .waiting
        add("Principal: iniciando listener…")
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let l = try NWListener(using: params)
            let name = namePrefix + String(UUID().uuidString.prefix(6))
            l.service = NWListener.Service(name: name, type: serviceType)
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in self?.listenerState(s) }
            }
            l.newConnectionHandler = { [weak self] c in
                Task { @MainActor in self?.accept(c) }
            }
            l.start(queue: .main)
            listener = l
            add("Principal: anunciado como \(name)")
        } catch {
            fail("No se pudo crear el listener: \(error)")
        }
    }

    func startAsMirror() {
        stop()
        role = .mirror
        status = .waiting
        add("Espejo: buscando principal…")
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        b.stateUpdateHandler = { [weak self] s in
            Task { @MainActor in self?.browserState(s) }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.browseResults(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        retryTask?.cancel(); retryTask = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        buffer.removeAll()
        role = .none
        status = .idle
    }

    func sendPing() {
        send(SimpleSyncMessage(kind: "ping", text: "ping desde \(deviceName)"))
    }

    func sendTimerState(seconds: Int, isRunning: Bool) {
        send(SimpleSyncMessage(kind: "state", seconds: seconds, isRunning: isRunning))
    }

    // MARK: - Listener / Browser

    private func listenerState(_ s: NWListener.State) {
        switch s {
        case .ready:
            add("Principal: listener listo")
        case .waiting(let e):
            add("Principal: listener esperando: \(e)")
        case .failed(let e):
            fail("Listener falló: \(e)")
        default:
            break
        }
    }

    private func browserState(_ s: NWBrowser.State) {
        switch s {
        case .ready:
            add("Espejo: buscador listo")
        case .waiting(let e):
            add("Espejo: buscador esperando: \(e)")
        case .failed(let e):
            fail("Buscador falló: \(e)")
        default:
            break
        }
    }

    private func browseResults(_ results: Set<NWBrowser.Result>) {
        add("Espejo: \(results.count) resultado(s)")
        guard connection == nil else { return }
        for r in results {
            if case let .service(name, _, _, _) = r.endpoint, name.hasPrefix(namePrefix) {
                add("Espejo: encontré \(name), conectando…")
                browser?.cancel(); browser = nil
                status = .connecting
                let params = NWParameters.tcp
                params.includePeerToPeer = false
                adopt(NWConnection(to: r.endpoint, using: params))
                return
            }
        }
    }

    // MARK: - Conexión

    private func accept(_ c: NWConnection) {
        add("Principal: llegó una conexión")
        status = .connecting
        adopt(c)
    }

    private func adopt(_ c: NWConnection) {
        connection?.cancel()
        connection = c
        buffer.removeAll()
        c.stateUpdateHandler = { [weak self, weak c] s in
            Task { @MainActor in
                guard let self, let c, c === self.connection else { return }
                self.connectionState(s)
            }
        }
        c.start(queue: .main)
        receive(on: c)
    }

    private func connectionState(_ s: NWConnection.State) {
        switch s {
        case .ready:
            add("Conexión lista")
            status = .connected("otro dispositivo")
            send(SimpleSyncMessage(kind: "hello", text: deviceName))
        case .waiting(let e):
            add("Conexión esperando: \(e)")
        case .failed(let e):
            dropped("Conexión falló: \(e)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func dropped(_ reason: String) {
        add(reason)
        connection?.cancel()
        connection = nil
        buffer.removeAll()
        status = .failed(reason)

        if role == .mirror {
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if self.role == .mirror { self.startAsMirror() }
            }
        } else if role == .master {
            status = .waiting
        }
    }

    // MARK: - Recepción / envío (un mensaje JSON por línea)

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, c === self.connection else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drain()
                }
                if let error {
                    self.dropped("Error de recepción: \(error)")
                    return
                }
                if isComplete {
                    self.dropped("El otro dispositivo cerró la conexión")
                    return
                }
                self.receive(on: c)
            }
        }
    }

    private func drain() {
        while let idx = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard !line.isEmpty else { continue }
            if let msg = try? JSONDecoder().decode(SimpleSyncMessage.self, from: line) {
                handle(msg)
            } else {
                add("Mensaje ilegible (\(line.count) bytes)")
            }
        }
    }

    private func handle(_ msg: SimpleSyncMessage) {
        lastMessage = msg
        switch msg.kind {
        case "hello":
            status = .connected(msg.text)
            add("Conectado con \(msg.text)")
        case "ping":
            add("Recibí: \(msg.text)")
        case "state":
            add("Estado recibido: \(msg.seconds)s, corriendo=\(msg.isRunning)")
        default:
            add("Mensaje desconocido: \(msg.kind)")
        }
    }

    private func send(_ msg: SimpleSyncMessage) {
        guard let c = connection, var data = try? JSONEncoder().encode(msg) else { return }
        data.append(0x0A)
        c.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                Task { @MainActor in self?.add("Error al enviar: \(error)") }
            }
        })
    }

    // MARK: - Utilidades

    private func fail(_ message: String) {
        add("❌ \(message)")
        status = .failed(message)
    }

    private func add(_ line: String) {
        print("🔁 [SimpleSync] \(line)")
        log.append(line)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }
}

// MARK: - Vista de prueba

struct SimpleSyncTestView: View {
    @ObservedObject private var sync = SimpleSync.shared

    private var statusText: String {
        switch sync.status {
        case .idle: return "Apagado"
        case .waiting:
            return sync.role == .master ? "Esperando al espejo…" : "Buscando al principal…"
        case .connecting: return "Conectando…"
        case .connected(let name): return "Conectado con \(name)"
        case .failed(let reason): return "Error: \(reason)"
        }
    }

    private var statusColor: Color {
        if case .connected = sync.status { return .green }
        if case .failed = sync.status { return .red }
        return .secondary
    }

    private var isConnected: Bool {
        if case .connected = sync.status { return true }
        return false
    }

    private var roleText: String {
        switch sync.role {
        case .none: return "—"
        case .master: return "PRINCIPAL"
        case .mirror: return "ESPEJO"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ROL:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(roleText)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            Text(statusText)
                .font(.headline)
                .foregroundStyle(statusColor)

            HStack(spacing: 8) {
                Button("Ser principal") { sync.startAsMaster() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                Button("Ser espejo") { sync.startAsMirror() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                Button("Apagar") { sync.stop() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

            Button("Enviar ping") { sync.sendPing() }
                .buttonStyle(.bordered)
                .disabled(!isConnected)

            Divider()

            Text("LOG")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sync.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 400)
    }
}