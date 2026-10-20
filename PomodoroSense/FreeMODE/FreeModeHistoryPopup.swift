//
//  FreeModeHistoryPopup.swift
//  PomodoroSense
//

import SwiftUI

struct FreeModeHistoryPopup: View {
    let sessions: [FreeModeSession]
    var onDelete: ((UUID) -> Void)? = nil
    var onClearAll: (() -> Void)? = nil
    var onEditNote: ((FreeModeSession) -> Void)? = nil

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: () -> Void

    @State private var showClearConfirm = false

    private var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.3).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().background(dimmedColor.opacity(0.15))

                if sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sessions) { session in
                                sessionRow(session)
                                Divider().background(dimmedColor.opacity(0.08))
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }

                if !sessions.isEmpty { footer }
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
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { onClearAll?() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("SESSION HISTORY")
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(dimmedColor.opacity(0.5))
            Text("No sessions yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(dimmedColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Row

    private func sessionRow(_ session: FreeModeSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDuration(session.duration))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)

                Text(formatDateRange(session))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(dimmedColor)

                if let note = session.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(dimmedColor.opacity(0.85))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    onEditNote?(session)
                } label: {
                    Image(systemName: session.note == nil
                          ? "note.text.badge.plus"
                          : "note.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(session.note == nil
                                         ? dimmedColor.opacity(0.5)
                                         : accentColor.opacity(0.85))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.note == nil ? "Add note" : "Edit note")

                Button {
                    onDelete?(session.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(dimmedColor.opacity(0.5))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete session")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().background(dimmedColor.opacity(0.15))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(dimmedColor)
                    Text(formatDuration(totalDuration))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }

                Spacer()

                Button("CLEAR") { showClearConfirm = true }
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.red.opacity(0.75))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Formatos

    private func formatDuration(_ d: TimeInterval) -> String {
        let total = Int(d)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatDateRange(_ session: FreeModeSession) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: session.startedAt)) – \(fmt.string(from: session.endedAt))"
    }
}
