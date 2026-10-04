//
//  FreeModeView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  FreeModeView.swift
//  PomodoroSense
//

import SwiftUI
import UniformTypeIdentifiers

struct FreeModeView: View {
    @ObservedObject var viewModel: FreeModeViewModel
    var onBack: () -> Void

    @State private var showHistory = false
    @State private var showMusicImporter = false
    @State private var showDiscardConfirm = false

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
                        Spacer(minLength: 30)
                        timerDisplay
                        Spacer(minLength: 30)
                        controls
                        Spacer(minLength: 30)
                        musicSection
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .overlay { historyOverlay }
        .fileImporter(
            isPresented: $showMusicImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.importMusic(from: url) }
            case .failure(let error):
                print("[FreeMode] Importer error: \(error)")
            }
        }
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(textDimmedWork)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("FREE MODE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(4)
                .foregroundColor(textDimmedWork)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showHistory = true }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDimmedWork)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Session history")
        }
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        VStack(spacing: 12) {
            Text(viewModel.formattedElapsed)
                .font(.system(size: 88, weight: .ultraLight, design: .default))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 10)

            Text(statusLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundColor(workAccent)
        }
    }

    private var statusLabel: String {
        if viewModel.isRunning { return "RUNNING" }
        if viewModel.elapsed > 0 { return "PAUSED" }
        return "READY"
    }

    // MARK: - Controles

    private var controls: some View {
        VStack(spacing: 18) {
            Button(action: { viewModel.toggleTimer() }) {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(workBackground)
                    .frame(width: 80, height: 80)
                    .background(workAccent)
                    .clipShape(Circle())
                    .shadow(color: workAccent.opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isRunning ? "Pause timer" : "Start timer")

            if viewModel.elapsed > 0 {
                HStack(spacing: 12) {
                    Button(action: { showDiscardConfirm = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("DISCARD")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                        }
                        .foregroundColor(textDimmedWork)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(textDimmedWork.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { _ = viewModel.finishSession() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("FINISH")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                        }
                        .foregroundColor(workBackground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(workAccent)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.elapsed > 0)
    }

    // MARK: - Música

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MUSIC")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(textDimmedWork)

                Spacer()

                if viewModel.musicTitle != nil {
                    Button { viewModel.removeMusic() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(textDimmedWork.opacity(0.6))
                            .contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let title = viewModel.musicTitle {
                HStack(spacing: 12) {
                    Button { viewModel.toggleMusic() } label: {
                        Image(systemName: viewModel.isMusicPlaying
                              ? "pause.circle.fill"
                              : "play.circle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(workAccent)
                    }
                    .buttonStyle(.plain)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    Button { showMusicImporter = true } label: {
                        Text("CHANGE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(textDimmedWork)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                Button { showMusicImporter = true } label: {
                    HStack {
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .semibold))
                        Text("ADD MUSIC")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                        Spacer()
                    }
                    .foregroundColor(workAccent)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(workAccent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Overlay historial

    @ViewBuilder
    private var historyOverlay: some View {
        if showHistory {
            FreeModeHistoryPopup(
                sessions: viewModel.sessions,
                onDelete: { viewModel.deleteSession(id: $0) },
                onClearAll: { viewModel.clearHistory() },
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) { showHistory = false }
                }
            )
        }
    }
}