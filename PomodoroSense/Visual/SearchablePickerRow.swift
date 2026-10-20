//
//  SearchablePickerRow.swift
//  PomodoroSense
//
//  Selector tipo "combobox": al cliquear el rectángulo se expande un
//  dropdown debajo, al mismo ancho, que permite elegir o buscar.
//  Mantiene la estética del `CyclicPickerRow` original (label + chevrons).
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

    @State private var isExpanded = false
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    /// Ancho del rectángulo (y del dropdown que se alinea debajo).
    private let boxWidth: CGFloat = 160
    /// Altura del rectángulo.
    private let boxHeight: CGFloat = 36
    /// Altura máxima del listado (con scroll interno).
    private let dropdownMaxHeight: CGFloat = 200

    private var filteredOptions: [T] {
        guard searchable, !query.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(2)
                    .foregroundColor(dimmedColor)

                Spacer(minLength: 10)

                selectBox
            }

            if isExpanded {
                dropdown
                    .frame(width: boxWidth)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
    }

    // MARK: - Rectángulo principal

    @ViewBuilder
    private var selectBox: some View {
        ZStack {
            // Fondo y borde (siempre presente).
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isExpanded ? 0.08 : 0.05))
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    accentColor.opacity(isExpanded ? 0.6 : 0.25),
                    lineWidth: 1
                )

            // Contenido: TextField cuando está expandido, label cuando no.
            if isExpanded && searchable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(dimmedColor)

                    TextField("", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1)
                        .foregroundColor(.white)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()

                    chevrons
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 6) {
                    Text(label(selection))
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    chevrons
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(width: boxWidth, height: boxHeight)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if !isExpanded { toggle() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
    }

    private var chevrons: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(accentColor)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
    }

    // MARK: - Dropdown

    private var dropdown: some View {
        VStack(spacing: 0) {
            if filteredOptions.isEmpty {
                Text("No matches.")
                    .font(.system(size: 11))
                    .foregroundColor(dimmedColor)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            optionRow(option)
                        }
                    }
                }
                .frame(maxHeight: dropdownMaxHeight)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    private func optionRow(_ option: T) -> some View {
        let isSelected = option == selection

        return Button(action: { selectOption(option) }) {
            HStack {
                Text(label(option))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Acciones

    private func toggle() {
        Haptics.selection()

        withAnimation {
            isExpanded.toggle()
            query = ""
            if isExpanded && searchable {
                // Pequeño delay para que el TextField esté en el árbol
                // antes de pedirle foco.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
            }
        }
    }

    private func selectOption(_ option: T) {
        selection = option
        Haptics.selection()

        withAnimation {
            isExpanded = false
            query = ""
            isSearchFocused = false
        }
    }
}
