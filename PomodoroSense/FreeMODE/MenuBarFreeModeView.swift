#if os(macOS)
import SwiftUI

struct MenuBarFreeModeView: View {
    @ObservedObject var viewModel: FreeModeViewModel
    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Header con botón de STOP
            HStack {
                Text("FREE MODE")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(accentColor)

                Spacer()

                Button(action: {
                    viewModel.finishSession()
                    onStop()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .black))
                        if !viewModel.isRunning {
                            Text("STOP")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.5)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.7, anchor: .trailing))
                                            .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.05)),
                                        removal: .opacity.combined(with: .scale(scale: 0.5, anchor: .trailing))
                                            .animation(.easeOut(duration: 0.15))
                                    )
                                )
                        }
                    }
                    .foregroundColor(viewModel.isRunning ? dimmedColor.opacity(0.35) : .white)
                    .padding(.horizontal, viewModel.isRunning ? 5 : 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(viewModel.isRunning ? Color.white.opacity(0.04) : Color.red.opacity(0.75))
                    )
                    .overlay(
                        Capsule()
                            .stroke(viewModel.isRunning ? Color.white.opacity(0.06) : Color.red.opacity(0.9), lineWidth: 0.5)
                    )
                    .shadow(color: viewModel.isRunning ? .clear : Color.red.opacity(0.35), radius: 4, x: 0, y: 1)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.isRunning)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Timer (tap para pausar/reanudar)
            HStack {
                Spacer()
                Text(viewModel.formattedElapsed)
                    .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(viewModel.isRunning ? .white : .gray)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: viewModel.formattedElapsed)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isRunning)
                    .frame(minWidth: 120)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleTimer() }
                Spacer()
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
    }
}
#endif