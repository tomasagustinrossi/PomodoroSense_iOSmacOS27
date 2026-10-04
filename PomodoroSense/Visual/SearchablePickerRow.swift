//
//  SearchablePickerRow.swift
//  PomodoroSense
//
//  Selector con dropdown + búsqueda opcional.
//  Reemplaza al `CyclicPickerRow` para listas largas (SOUND, WAVES).
//

import SwiftUI

struct SearchablePickerRow<T: Hashable>: View {
    var title: String
    @Binding var selection: T
    var options: [T]
    var accentColor: Color
    var dimmedColor: Color
    var searchable: Bool = true
    var label: (T) -> String

    @State private var isPresented = false
    @State private var query = ""

    private var filteredOptions: [T] {
        guard searchable, !query.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .tracking(2)
                .foregroundColor(dimmedColor)

            Spacer(minLength: 10)

            Button(action: {
                query = ""
                isPresented.toggle()
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            }) {
                HStack(spacing: 8) {
                    Text(label(selection))
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentColor.opacity(0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                pickerContent
                    .frame(width: 240)
            }
        }
    }

    // MARK: - Contenido del popover

    private var pickerContent: some View {
        VStack(spacing: 0) {
            if searchable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dimmedColor)

                    TextField("Search…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .autocorrectionDisabled()

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(dimmedColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()
            }

            if filteredOptions.isEmpty {
                Text("No matches.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            optionRow(option)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func optionRow(_ option: T) -> some View {
        let isSelected = option == selection

        return Button(action: {
            selection = option
            isPresented = false
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }) {
            HStack {
                Text(label(option))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}