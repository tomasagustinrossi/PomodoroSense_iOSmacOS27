//
//  DayDetailPopup.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 18/10/2026.
//


import SwiftUI

struct DayDetailPopup: View {
    let day: Date
    let records: [PomodoroSessionRecord]
    let goal: DailyGoal?

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color

    var onSaveGoal: (String?) -> Void
    var onToggleGoal: () -> Void
    var onDismiss: () -> Void

    @State private var isEditingGoal: Bool = false
    @State private var goalDraft: String = ""
    @FocusState private var goalFocused: Bool

    // ── Datos derivados ──
    private var completedRecords: [PomodoroSessionRecord] {
        records.filter { $0.qualifiesForChips }
            .sorted { $0.timestamp < $1.timestamp }
    }
    private var skippedCount: Int {
        records.filter { $0.wasSkipped }.count
    }
    private var totalMinutes: Int {
        completedRecords.reduce(0) { $0 + $1.focusMinutes }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().background(dimmedColor.opacity(0.15))

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 18) {
                        historySection
                        if (goal != nil || isEditingGoal) && !completedRecords.isEmpty {
                            Divider().background(dimmedColor.opacity(0.12))
                        }
                        if goal != nil || isEditingGoal {
                            goalSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .frame(maxHeight: 420)

                if goal == nil && !isEditingGoal {
                    addGoalButton
                }
            }
            .frame(maxWidth: 380)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedDay)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundColor(accentColor)

                Text(daySummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(dimmedColor)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var formattedDay: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMMM"
        return fmt.string(from: day).uppercased()
    }

    private var daySummary: String {
        var parts: [String] = []
        if totalMinutes > 0 {
            let hours = Double(totalMinutes) / 60.0
            if hours >= 1 {
                parts.append(String(format: "%.1fh focus", hours))
            } else {
                parts.append("\(totalMinutes)m focus")
            }
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        if parts.isEmpty { return "No activity" }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSION HISTORY")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            if completedRecords.isEmpty {
                Text("No completed pomodoros")
                    .font(.system(size: 12))
                    .foregroundColor(dimmedColor.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: completedRecords.count > 3) {
                    LazyVStack(spacing: 8) {
                        ForEach(completedRecords) { record in
                            recordRow(record)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func recordRow(_ record: PomodoroSessionRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Hora
            Text(timeString(record.timestamp))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .frame(width: 48, alignment: .leading)

            // Configuración: "30F · 10B · 4S"
            VStack(alignment: .leading, spacing: 2) {
                Text(configString(record))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accentColor.opacity(0.9))

                Text("\(record.focusMinutes)m focus  ·  quality \(record.effectiveQuality)")
                    .font(.system(size: 10))
                    .foregroundColor(dimmedColor.opacity(0.75))
            }

            Spacer(minLength: 6)

            // Marcador de skip individual (no debería aparecer — filtramos por qualifiesForChips)
            if record.wasSkipped {
                Text("SKIP")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.red.opacity(0.12)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    /// "30F · 10B · 4S" (o "30F · 4S" si no hay breakMinutes por records viejos)
    private func configString(_ record: PomodoroSessionRecord) -> String {
        var parts: [String] = []
        parts.append("\(record.focusMinutes)F")
        if let b = record.breakMinutes { parts.append("\(b)B") }
        parts.append("\(record.totalSessions)S")
        return parts.joined(separator: " · ")
    }

    // MARK: - Goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GOAL")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            if isEditingGoal {
                goalEditor
            } else if let goal {
                goalView(goal)
            }
        }
    }

    private func goalView(_ goal: DailyGoal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleGoal) {
                Image(systemName: goal.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(goal.completed ? accentColor : dimmedColor.opacity(0.6))
            }
            .buttonStyle(.plain)

            Text(goal.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(goal.completed ? dimmedColor.opacity(0.6) : .white)
                .strikethrough(goal.completed, color: dimmedColor.opacity(0.5))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                goalDraft = goal.text
                isEditingGoal = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    goalFocused = true
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dimmedColor.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What do you want to achieve?", text: $goalDraft, axis: .vertical)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .tint(accentColor)
                .autocorrectionDisabled()
                .focused($goalFocused)
                .lineLimit(2...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(accentColor.opacity(0.4), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("CANCEL") {
                    isEditingGoal = false
                    goalDraft = ""
                    goalFocused = false
                }
                .foregroundColor(dimmedColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(dimmedColor.opacity(0.3), lineWidth: 1)
                )

                Button("SAVE") {
                    onSaveGoal(goalDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingGoal = false
                    goalDraft = ""
                    goalFocused = false
                }
                .foregroundColor(backgroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(accentColor)
                )
            }
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .buttonStyle(.plain)
        }
    }

    private var addGoalButton: some View {
        Button {
            goalDraft = ""
            isEditingGoal = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                goalFocused = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("SET A GOAL FOR THIS DAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundColor(accentColor.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}