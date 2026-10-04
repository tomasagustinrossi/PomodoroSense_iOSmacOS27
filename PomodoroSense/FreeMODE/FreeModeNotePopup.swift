import SwiftUI

struct FreeModeNotePopup: View {
    let session: FreeModeSession

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color

    var onSave: (String?) -> Void
    var onDismiss: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        session: FreeModeSession,
        accentColor: Color,
        dimmedColor: Color,
        backgroundColor: Color,
        onSave: @escaping (String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.session = session
        self.accentColor = accentColor
        self.dimmedColor = dimmedColor
        self.backgroundColor = backgroundColor
        self.onSave = onSave
        self.onDismiss = onDismiss
        _text = State(initialValue: session.note ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                HStack {
                    Text("SESSION NOTE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(accentColor)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(dimmedColor)
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .frame(minHeight: 100, maxHeight: 180)
                    .cornerRadius(8)
                    .focused($isFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(accentColor.opacity(0.2), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button("CANCEL", action: onDismiss)
                        .foregroundColor(dimmedColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(dimmedColor.opacity(0.3), lineWidth: 1)
                        )

                    Button("SAVE") {
                        onSave(text.isEmpty ? nil : text)
                    }
                    .foregroundColor(backgroundColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accentColor))
                }
                .font(.system(size: 11, weight: .bold))
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true }
        }
    }
}