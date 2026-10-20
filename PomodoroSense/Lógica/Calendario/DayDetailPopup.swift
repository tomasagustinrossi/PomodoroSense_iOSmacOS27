//
//  DayDetailPopup.swift
//  PomodoroSense
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
    var focusTimeForGoal: (DailyGoal) -> Int // <-- AGREGADO

    @State private var isEditingGoal: Bool = false
    @State private var goalDraft: String = ""
    @FocusState private var goalFocused: Bool

    // Fondo cálido minimalista
    private let popupBackground = Color(red: 0.12, green: 0.11, blue: 0.10)

    private var isPastDay: Bool {
        Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: Date())
    }

    private var completedRecords: [PomodoroSessionRecord] {
        records.filter { $0.qualifiesForChips }
            .sorted { $0.timestamp < $1.timestamp }
    }
    private var skippedRecords: [PomodoroSessionRecord] {
        records.filter { $0.wasSkipped }
    }
    private var interruptedRecords: [PomodoroSessionRecord] {
        records.filter { $0.wasInterrupted }
    }
    private var totalMinutes: Int {
        completedRecords.reduce(0) { $0 + $1.focusMinutes }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.05))

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 20) {
                        historySection
                        if (goal != nil || isEditingGoal) && !completedRecords.isEmpty {
                            Divider().background(Color.white.opacity(0.05))
                        }
                        if goal != nil || isEditingGoal {
                            goalSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .frame(maxHeight: 420)

                if goal == nil && !isEditingGoal && !isPastDay {
                    addGoalButton
                }
            }
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(popupBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDay)
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(accentColor.opacity(0.9))

                Text(daySummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(dimmedColor.opacity(0.6))
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(dimmedColor.opacity(0.7))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var formattedDay: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMMM"
        return fmt.string(from: day).uppercased()
    }

    private var daySummary: String {
        var parts: [String] = []
        if totalMinutes > 0 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if hours > 0 {
                parts.append("\(hours)h \(mins)m focus")
            } else {
                parts.append("\(mins)m focus")
            }
        }
        if skippedRecords.count > 0 {
            parts.append("\(skippedRecords.count) skipped")
        }
        if interruptedRecords.count > 0 {
            parts.append("\(interruptedRecords.count) interrupted")
        }
        if parts.isEmpty { return "No activity" }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SESSION HISTORY")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(dimmedColor.opacity(0.5))

            if completedRecords.isEmpty {
                Text("No completed pomodoros")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(dimmedColor.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: completedRecords.count > 3) {
                    LazyVStack(spacing: 6) {
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
            Text(timeString(record.timestamp))
                .font(.system(size: 13, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(configString(record))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(accentColor.opacity(0.8))

                Text("\(record.focusMinutes)m focus")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(dimmedColor.opacity(0.6))
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.02))
        )
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func configString(_ record: PomodoroSessionRecord) -> String {
        var parts: [String] = []
        parts.append("\(record.focusMinutes)F")
        if let b = record.breakMinutes { parts.append("\(b)B") }
        parts.append("\(record.totalSessions)S")
        return parts.joined(separator: " · ")
    }

    // MARK: - Goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(dimmedColor.opacity(0.5))

            if isEditingGoal {
                goalEditor
            } else if let goal {
                goalView(goal)
            }
        }
    }

    private func goalView(_ goal: DailyGoal) -> some View {
        let minutes = focusTimeForGoal(goal)
        
        return HStack(alignment: .top, spacing: 10) {
            // Zona clickeable para tachar
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: goal.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(goal.completed ? accentColor : dimmedColor.opacity(0.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.text)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(goal.completed ? dimmedColor.opacity(0.4) : .white.opacity(0.9))
                        .strikethrough(goal.completed, color: dimmedColor.opacity(0.5))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Tiempo de focus acumulado
                    Text("\(minutes / 60)h \(minutes % 60)m focus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.impact(.light, intensity: 0.6)
                onToggleGoal()
            }

            // Botón editar
            Button {
                goalDraft = goal.text
                isEditingGoal = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    goalFocused = true
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(dimmedColor.opacity(0.7))
                    .minTapTarget(36)
            }
            .buttonStyle(.plain)

            // Botón eliminar
            Button {
                Haptics.impact(.light, intensity: 0.6)
                withAnimation(.easeInOut(duration: 0.2)) {
                    onSaveGoal(nil)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red.opacity(0.7))
                    .minTapTarget(36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What do you want to achieve?", text: $goalDraft, axis: .vertical)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.white)
                .tint(accentColor)
                .autocorrectionDisabled()
                .focused($goalFocused)
                .onSubmit {
                    onSaveGoal(goalDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingGoal = false
                    goalDraft = ""
                    goalFocused = false
                }
                .lineLimit(2...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )

            HStack(spacing: 10) {
                Button("CANCEL") {
                    isEditingGoal = false
                    goalDraft = ""
                    goalFocused = false
                }
                .foregroundColor(dimmedColor.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.03))
                )

                Button("SAVE") {
                    onSaveGoal(goalDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingGoal = false
                    goalDraft = ""
                    goalFocused = false
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(accentColor)
                )
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 10, weight: .bold))
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
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("SET A GOAL FOR THIS DAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundColor(accentColor.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}
