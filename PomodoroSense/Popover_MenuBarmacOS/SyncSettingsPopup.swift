import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

//  Cambios respecto a la versión anterior:
//    · Al reabrir el popup estando ya vinculado, muestra "conectado"
//      (antes mostraba los botones de master/mirror aunque hubiera sesión).
//    · "Resume on relaunch": estado local sincronizado con SyncPersistence.
//      Leer/escribir el singleton dentro de un Binding no invalida la vista
//      si no es observable, y el switch parecía "volver" a su valor.
//    · LINK / QR: estado `isLinking` (sin toques dobles ni conexiones
//      duplicadas) + Enter en el campo para vincular.
//    · Mientras un peer conecta, se bloquean el resto de acciones y se
//      aplica un timeout de 15s que cancela el intento (no se reconecta
//      solo, coherente con "la activación la elige el usuario").
//    · Borrar un dispositivo vinculado pide confirmación.
//    · `.idle` ya no borra el mensaje de error (si no, el mensaje del
//      timeout se perdía al volver el engine a idle).
//    · CANCEL con estilo plano (en macOS salía como botón con borde).
//    · Escape cierra el popup (.cancelAction) y etiquetas de accesibilidad.
//  `generatedCode` y `hostingWaitingView` se conservan aunque hoy no se
//  lean/usen, por si los necesitás más adelante.

struct SyncSettingsPopup: View {

    @ObservedObject var timerVM: TimerViewModel
    
    @AppStorage("mirror_mode_enabled") private var isMirrorModeEnabled: Bool = false
    @AppStorage("sfx_volume") private var sfxVolume: Double = 0.8

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: () -> Void

    // MARK: - Estado Local P2P
    @State private var generatedCode: String? = nil
    @State private var inputCode: String = ""
    @State private var errorMessage: String? = nil
    @State private var flow: PairingFlow = .idle
    @State private var knownPeers: [KnownPeer] = []
    @State private var connectingPeerId: String?
    @State private var peerBeingRenamed: KnownPeer? = nil
    @State private var peerPendingDelete: KnownPeer? = nil
    @State private var renameDraft: String = ""
    @State private var isLinking: Bool = false
    @State private var resumeOnRelaunch: Bool = false

    /// Tiempo máximo esperando que un dispositivo vinculado responda.
    private static let reconnectTimeout: Duration = .seconds(15)

    /// Ramas del flujo de emparejamiento. El `syncState` del engine
    /// se mapea a estas ramas para que la UI no dependa de sus errores
    /// ni de sus transiciones internas.
    private enum PairingFlow: Equatable {
        case idle
        case hostingWithQR(code: String)
        case scanning
        case enteringCode
        case connected
    }

    /// Hay un intento de reconexión en curso.
    private var isBusy: Bool { connectingPeerId != nil }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.3).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider().background(dimmedColor.opacity(0.15))
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 22) {
                        // 1. RESUME ON RELAUNCH
                        resumeOnRelaunchToggle
                        
                        // 2. CONTROL DE VOLUMEN
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SFX & MUSIC VOLUME")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(dimmedColor.opacity(0.8))
                                Spacer()
                                Text("\(Int(sfxVolume * 100))%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(accentColor)
                            }
                            
                            Slider(value: $sfxVolume, in: 0...1, step: 0.05)
                                .tint(accentColor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))

                        // 3. TOGGLE MIRROR MODE
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("ENABLE MIRROR MODE")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(isMirrorModeEnabled ? accentColor : dimmedColor.opacity(0.8))
                                Spacer()
                                Toggle("", isOn: $isMirrorModeEnabled)
                                    .toggleStyle(.switch)
                                    .tint(accentColor)
                                    .controlSize(.small)
                                    .fixedSize()
                            }
                            Text("Link your devices to sync timers in real-time.")
                                .font(.system(size: 10))
                                .foregroundColor(dimmedColor.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))

                        // 4. SECCIÓN MIRROR (solo si está habilitado y con divisor)
                        if isMirrorModeEnabled {
                            Divider().background(dimmedColor.opacity(0.15))
                                .padding(.vertical, 4)
                            
                            mirrorModeSection
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .frame(maxHeight: 500)
            }
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        }
        .onChange(of: timerVM.syncState) { _, newState in
            handleSyncStateChange(newState)
        }
        .onChange(of: isMirrorModeEnabled) { _, enabled in
            if !enabled {
                Task { await timerVM.disableSync() }
                errorMessage = nil
                flow = .idle
            }
        }
        .onAppear {
            knownPeers = SyncPersistence.shared.knownPeers
            resumeOnRelaunch = SyncPersistence.shared.resumeSessionOnRelaunch
            // Si ya hay una sesión vinculada, reflejarla al abrir el popup.
            if case .connected = timerVM.syncState {
                flow = .connected
            }
        }
        .alert(
            "Rename Device",
            isPresented: Binding(
                get: { peerBeingRenamed != nil },
                set: { if !$0 { peerBeingRenamed = nil; renameDraft = "" } }
            )
        ) {
            TextField("Device name", text: $renameDraft)
                .autocorrectionDisabled()

            Button("Cancel", role: .cancel) {
                peerBeingRenamed = nil
                renameDraft = ""
            }

            Button("Save") {
                commitRename()
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a friendly name for this paired device.")
        }
        .confirmationDialog(
            "Remove this device?",
            isPresented: Binding(
                get: { peerPendingDelete != nil },
                set: { if !$0 { peerPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: peerPendingDelete
        ) { peer in
            Button("Remove \(peer.name)", role: .destructive) {
                deletePeer(peer)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You'll need to pair it again to reconnect.")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { flow == .scanning },
            set: { if !$0 && flow == .scanning { flow = .idle } }
        )) {
            QRScannerView(
                onScan: { raw in
                    guard let canonical = LocalSyncTransport.canonicalize(raw) else {
                        errorMessage = "Invalid QR code"
                        flow = .enteringCode
                        return
                    }
                    errorMessage = nil
                    inputCode = formatCode(canonical)
                    // Volvemos a la pantalla de código para mostrar el
                    // estado "LINKING…" mientras conecta.
                    flow = .enteringCode
                    isLinking = true
                    timerVM.startSyncAsMirror(pairingCode: canonical)
                },
                onCancel: { flow = .idle }
            )
            .ignoresSafeArea()
        }
        #endif
    }

    // MARK: - Mapeo de estado del engine → flujo de UI

    private func handleSyncStateChange(_ newState: LocalSyncEngine.State) {
        switch newState {
        case .idle:
            flow = .idle
            generatedCode = nil
            inputCode = ""
            // errorMessage NO se borra acá: lo limpia cada acción del
            // usuario, y así sobrevive un mensaje puesto justo antes de
            // que el engine vuelva a idle (por ejemplo tras un timeout).
            connectingPeerId = nil
            isLinking = false
            knownPeers = SyncPersistence.shared.knownPeers

        case .hosting:
            break

        case .connected:
            flow = .connected
            errorMessage = nil
            connectingPeerId = nil
            isLinking = false
            knownPeers = SyncPersistence.shared.knownPeers

        case .error(let err):
            errorMessage = err.localizedDescription
            flow = .idle
            connectingPeerId = nil
            isLinking = false

        case .browsing, .waiting:
            break
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accentColor)

            Text("CONFIGURATIONS")
                .font(.system(size: 13, weight: .bold))
                .tracking(3)
                .foregroundColor(accentColor)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Resume on relaunch

    private var resumeOnRelaunchToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RESUME ON RELAUNCH")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(
                        resumeOnRelaunch
                            ? accentColor
                            : dimmedColor.opacity(0.8)
                    )

                Spacer()

                Toggle(isOn: Binding(
                    get: { resumeOnRelaunch },
                    set: { newValue in
                        resumeOnRelaunch = newValue
                        SyncPersistence.shared.resumeSessionOnRelaunch = newValue
                    }
                )) { EmptyView() }
                    .toggleStyle(.switch)
                    .tint(accentColor)
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel("Resume on relaunch")
            }

            Text("Restore your active session if the app closes unexpectedly.")
                .font(.system(size: 10))
                .foregroundColor(dimmedColor.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Subvistas Mirror Mode (LocalSyncEngine)

    @ViewBuilder
    private var mirrorModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)

                Text("MIRROR MODE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(dimmedColor)
            }

            switch flow {
            case .idle:            idlePairingView
            case .hostingWithQR(let code): hostingQRView(code: code)
            case .scanning:        Color.clear.frame(height: 100)
            case .enteringCode:    enteringCodeView
            case .connected:       connectedView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: flow)
    }

    // MARK: - Idle: elegir rol (master o mirror)

    private var idlePairingView: some View {
        VStack(spacing: 16) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButton(
                title: "SHARE THIS TIMER (MASTER)",
                icon: "antenna.radiowaves.left.and.right",
                isPrimary: true
            ) {
                startAsMaster()
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)

            HStack {
                Rectangle().fill(dimmedColor.opacity(0.2)).frame(height: 1)
                Text("OR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(dimmedColor)
                Rectangle().fill(dimmedColor.opacity(0.2)).frame(height: 1)
            }

            actionButton(
                title: "CONNECT AS REMOTE (MIRROR)",
                icon: "link",
                isPrimary: false
            ) {
                errorMessage = nil
                flow = .enteringCode
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)

            // Peers guardados al fondo, separados por un divisor.
            if !knownPeers.isEmpty {
                HStack {
                    Rectangle().fill(dimmedColor.opacity(0.2)).frame(height: 1)
                    Text("PAIRED DEVICES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(dimmedColor)
                    Rectangle().fill(dimmedColor.opacity(0.2)).frame(height: 1)
                }
                .padding(.top, 6)

                VStack(spacing: 8) {
                    ForEach(knownPeers) { peer in
                        knownPeerRow(peer)
                    }
                }
            }
        }
    }

    private func knownPeerRow(_ peer: KnownPeer) -> some View {
        let isConnecting = connectingPeerId == peer.id

        return HStack(spacing: 8) {
            // Zona clickeable: conecta
            Button(action: { connectToKnownPeer(peer) }) {
                HStack(spacing: 10) {
                    ZStack {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(accentColor)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                    }
                    .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(peer.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(peer.roleLabel)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundColor(accentColor)

                            Text("·")
                                .font(.system(size: 9))
                                .foregroundColor(dimmedColor.opacity(0.5))

                            Text(peer.lastConnectedLabel)
                                .font(.system(size: 10))
                                .foregroundColor(dimmedColor)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            // Lápiz
            Button(action: { beginRename(peer) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dimmedColor.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("Rename device")

            // Tacho (pide confirmación)
            Button(action: { peerPendingDelete = peer }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("Remove device")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isConnecting ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isConnecting ? accentColor.opacity(0.5) : accentColor.opacity(0.12),
                    lineWidth: isConnecting ? 1.5 : 1
                )
        )
        .scaleEffect(isConnecting ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isConnecting)
    }

    private func beginRename(_ peer: KnownPeer) {
        peerBeingRenamed = peer
        renameDraft = peer.name
    }

    private func commitRename() {
        guard let peer = peerBeingRenamed else { return }
        SyncPersistence.shared.renameKnownPeer(id: peer.id, newName: renameDraft)
        peerBeingRenamed = nil
        renameDraft = ""
        knownPeers = SyncPersistence.shared.knownPeers
    }

    private func connectToKnownPeer(_ peer: KnownPeer) {
        guard !isBusy else { return }
        errorMessage = nil
        Haptics.impact(.medium, intensity: 0.7)
        let peerID = peer.id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            connectingPeerId = peerID
        }
        timerVM.reconnectToKnownPeer(peer)

        // Timeout: si el otro dispositivo no responde, cortamos el intento
        // (y lo cancelamos en el engine para que no se conecte solo más
        // tarde: la vinculación la decide el usuario).
        Task {
            try? await Task.sleep(for: Self.reconnectTimeout)
            guard connectingPeerId == peerID else { return }
            connectingPeerId = nil
            await timerVM.disableSync()
            errorMessage = "Couldn't reach \(peer.name). Make sure the other device is sharing its timer."
        }
    }

    private func deletePeer(_ peer: KnownPeer) {
        SyncPersistence.shared.removeKnownPeer(id: peer.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            knownPeers = SyncPersistence.shared.knownPeers
        }
    }

    // MARK: - Master: QR + copy

    private func hostingQRView(code: String) -> some View {
        VStack(spacing: 18) {
            Text("SCAN OR COPY THE CODE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(accentColor)

            QRCodeView(text: code)
                .frame(width: 220, height: 220)

            Button(action: {
                Clipboard.copy(code)
                Haptics.impact(.light, intensity: 0.6)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .bold))
                    Text("COPY CODE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                }
                .foregroundColor(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Text("On the other device, scan this QR\nor paste the copied code.")
                .font(.system(size: 11))
                .foregroundColor(dimmedColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            cancelButton
        }
    }

    // MARK: - Master: esperando conexión entrante
    // (No se usa hoy: el flujo master muestra directamente el QR.)

    private var hostingWaitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(accentColor)
                .scaleEffect(1.2)

            Text("WAITING FOR MIRROR…")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(accentColor)

            Text("Keep this screen open on both devices.")
                .font(.system(size: 11))
                .foregroundColor(dimmedColor)
                .multilineTextAlignment(.center)

            cancelButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Mirror: ingresar código a mano

    private var enteringCodeView: some View {
        VStack(spacing: 14) {
            #if os(iOS)
            actionButton(
                title: "SCAN QR",
                icon: "qrcode.viewfinder",
                isPrimary: true
            ) {
                errorMessage = nil
                flow = .scanning
            }
            .disabled(isLinking)
            .opacity(isLinking ? 0.5 : 1)

            Text("OR PASTE THE CODE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(dimmedColor)
            #else
            Text("PASTE THE CODE FROM THE OTHER DEVICE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(dimmedColor)
                .multilineTextAlignment(.center)
            #endif

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("XXXX-XXXX-XXXX-XXXX", text: $inputCode)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(accentColor)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.3), lineWidth: 1))
                #if os(iOS)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                #endif
                .disabled(isLinking)
                .onChange(of: inputCode) { _, newValue in
                    let formatted = formatCode(newValue)
                    if formatted != newValue { inputCode = formatted }
                }
                .onSubmit { linkWithTypedCode() }

            actionButton(
                title: isLinking ? "LINKING…" : "LINK",
                icon: "link",
                isPrimary: false
            ) {
                linkWithTypedCode()
            }
            .opacity(isValidTypedCode && !isLinking ? 1.0 : 0.5)
            .disabled(!isValidTypedCode || isLinking)

            cancelButton
        }
    }

    // MARK: - Conectado

    private var connectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text(timerVM.isMirror ? "ACTING AS REMOTE CONTROL" : "TRANSMITTING TO MIRROR")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            actionButton(title: "UNLINK", icon: "xmark.circle", isPrimary: false) {
                Task { await timerVM.disableSync() }
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Botón cancelar (reusado en todas las ramas)

    private var cancelButton: some View {
        Button("CANCEL") {
            Task { await timerVM.disableSync() }
            generatedCode = nil
            errorMessage = nil
            inputCode = ""
            isLinking = false
            flow = .idle
        }
        .buttonStyle(.plain) // en macOS, sin esto sale con borde de botón
        .font(.system(size: 11, weight: .bold))
        .tracking(1.5)
        .foregroundColor(.red.opacity(0.8))
        .padding(.top, 4)
    }

    // MARK: - Acciones del flujo

    private func startAsMaster() {
        errorMessage = nil
        do {
            let code = try timerVM.startSyncAsMasterHosting()
            generatedCode = code
            flow = .hostingWithQR(code: code)
        } catch {
            errorMessage = "Failed to start hosting: \(error.localizedDescription)"
        }
    }

    private func linkWithTypedCode() {
        guard !isLinking,
              let canonical = LocalSyncTransport.canonicalize(inputCode) else { return }
        errorMessage = nil
        isLinking = true
        timerVM.startSyncAsMirror(pairingCode: canonical)
    }

    // MARK: - Botón reutilizable

    private func actionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundColor(isPrimary ? backgroundColor : accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPrimary ? accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor.opacity(isPrimary ? 0 : 0.3), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers de código

    private var isValidTypedCode: Bool {
        LocalSyncTransport.canonicalize(inputCode) != nil
    }

    private func formatCode(_ raw: String) -> String {
        let upper = raw.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let allowed = Set(LocalSyncTransport.pairingAlphabet)
        let filtered = upper.filter { allowed.contains($0) }
        let limited = String(filtered.prefix(LocalSyncTransport.pairingCodeLength))

        var result = ""
        for (i, ch) in limited.enumerated() {
            if i > 0 && i % 4 == 0 { result.append("-") }
            result.append(ch)
        }
        return result
    }
}
