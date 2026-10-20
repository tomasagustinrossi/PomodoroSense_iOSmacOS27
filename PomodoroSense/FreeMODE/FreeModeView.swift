import SwiftUI

struct FreeModeView: View {
    @ObservedObject var viewModel: FreeModeViewModel
    var onBack: () -> Void

    @State private var showHistory = false
    @State private var showDiscardConfirm = false
    @State private var showEqualizer = false
    @State private var noteSession: FreeModeSession? = nil

    /// `true` si hay cualquier popup encima del Free Mode.
    private var isAnyPopupOpen: Bool {
        showHistory || showDiscardConfirm || showEqualizer || noteSession != nil
    }

    @Environment(\.scenePhase) private var scenePhase

    private let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    private let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    private let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)

    var body: some View {
        ZStack {
            workBackground.ignoresSafeArea()

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 32)
                        timerDisplay
                        Spacer(minLength: 32)
                        controls
                        Spacer(minLength: 32)
                        audioSection
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .overlay { historyOverlay }
        .overlay { equalizerOverlay }
        .overlay { noteOverlay }
        .confirmationDialog(
            "Discard this session?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { viewModel.discardSession() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The current time won't be saved to your history.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.restartTickerIfNeeded() }
        }
        .gesture(backSwipeGesture)
    }

    // MARK: - Swipe de salida
    // iOS: swipe UP → volver.
    // macOS: swipe LEFT → volver.
    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !isAnyPopupOpen else { return }
                #if os(iOS)
                if value.translation.height < -60 { onBack() }
                #else
                if value.translation.width > 60 { onBack() }
                #endif
            }
    }

    // MARK: - Header

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(textDimmedWork)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.pressable)

            Spacer()

            Text("FREE MODE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(4)
                .foregroundColor(textDimmedWork)

            Spacer()

            Button {
                Haptics.impact(.light, intensity: 0.6)
                withAnimation(HIGMotion.state) {
                    showHistory = true
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDimmedWork)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Session history")
        }
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        VStack(spacing: 16) {
            Text(viewModel.formattedElapsed)
                .font(.system(size: 88, weight: .ultraLight, design: .default))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText(countsDown: false))
                .animation(HIGMotion.numeric, value: viewModel.formattedElapsed)
                .padding(.horizontal, 10)

            Text(statusLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundColor(workAccent)
                .contentTransition(.opacity)
                .animation(HIGMotion.state, value: statusLabel)
        }
    }

    private var statusLabel: String {
        if viewModel.isRunning { return "FOCUS" }
        if viewModel.elapsed > 0 { return "PAUSED" }
        return "READY"
    }

    // MARK: - Controles

    private var controls: some View {
        VStack(spacing: 24) {
            Button(action: { viewModel.toggleTimer() }) {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(workBackground)
                    .frame(width: 80, height: 80)
                    .background(workAccent)
                    .clipShape(Circle())
                    .shadow(color: workAccent.opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.pressable)
            // HIG: la respuesta háptica se dispara con el cambio de estado, no con el tap
            .onChange(of: viewModel.isRunning) { _, running in
                Haptics.impact(running ? .medium : .soft, intensity: 0.85)
            }

            if viewModel.elapsed > 0 {
                HStack(spacing: 16) {
                    Button(action: {
                        Haptics.warning()
                        showDiscardConfirm = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            Text("DISCARD").font(.system(size: 11, weight: .bold)).tracking(1.5)
                        }
                        .foregroundColor(textDimmedWork)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(textDimmedWork.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.pressable)

                    Button(action: {
                        // Éxito solo si la sesión se guardó (≥ 5 min); si no, un toque suave.
                        if viewModel.finishSession() != nil {
                            Haptics.success()
                        } else {
                            Haptics.impact(.soft, intensity: 0.6)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            Text("FINISH").font(.system(size: 11, weight: .bold)).tracking(1.5)
                        }
                        .foregroundColor(workBackground)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(workAccent)
                        )
                    }
                    .buttonStyle(.pressable)
                }
                // HIG: entrada física con spring, no fade plano
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        // HIG: spring > easeInOut para cambios de estado visibles
        .animation(HIGMotion.state, value: viewModel.elapsed > 0)
    }

    // MARK: - Audio

    private var audioSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AUDIO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(textDimmedWork)

                Text(audioSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Haptics.selection()
                withAnimation(HIGMotion.overlay) { showEqualizer = true }
            } label: {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(workAccent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(workAccent.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Audio settings")
        }
    }

    private var audioSummary: String {
        let noise = AmbientSound.from(id: viewModel.noiseId).displayName
        let freq: String
        switch viewModel.freqId {
        case 1: freq = "40 HZ"
        case 2: freq = "15 HZ"
        case 3: freq = "10 HZ"
        case 4: freq = "6 HZ"
        default: freq = ""
        }
        if freq.isEmpty { return noise }
        return "\(freq) · \(noise)"
    }

    // MARK: - Overlays

    @ViewBuilder
    private var historyOverlay: some View {
        if showHistory {
            FreeModeHistoryPopup(
                sessions: viewModel.sessions,
                onDelete: { viewModel.deleteSession(id: $0) },
                onClearAll: { viewModel.clearHistory() },
                onEditNote: { session in
                    withAnimation(HIGMotion.overlay) {
                        noteSession = session
                    }
                },
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                onDismiss: {
                    withAnimation(HIGMotion.state) { showHistory = false }
                }
            )
        }
    }

    @ViewBuilder
    private var equalizerOverlay: some View {
        if showEqualizer {
            ZStack {
                HIGScrim {
                    withAnimation(HIGMotion.overlay) { showEqualizer = false }
                }
                .transition(.opacity)

                EqualizerSheetView(
                    initialNoiseId: viewModel.noiseId,
                    initialFreqId: viewModel.freqId,
                    accentColor: workAccent,
                    dimmedColor: textDimmedWork,
                    backgroundColor: workBackground,
                    onNoiseChanged: { viewModel.updateNoiseId($0) },
                    onFreqChanged: { viewModel.updateFreqId($0) },
                    onDismiss: {
                        withAnimation(HIGMotion.overlay) { showEqualizer = false }
                    }
                )
                .frame(maxWidth: 460, maxHeight: 520)
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 12)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var noteOverlay: some View {
        if let session = noteSession {
            FreeModeNotePopup(
                session: session,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                onSave: { newNote in
                    viewModel.updateNote(for: session.id, note: newNote)
                    withAnimation(HIGMotion.overlay) { noteSession = nil }
                },
                onDismiss: {
                    withAnimation(HIGMotion.overlay) { noteSession = nil }
                }
            )
        }
    }
}
