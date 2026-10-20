//
//  OwnedItemsView.swift
//  PomodoroSense
//

import SwiftUI

struct OwnedItemsView: View {
    var dimmedColor: Color
    var onBack: () -> Void

    // MARK: - Estado
    @State private var currentIndex: Int = 0
    @State private var listPresented: Bool = false
    @Namespace private var heroNamespace

    // MARK: - Música de la Colección
    private let ownedSongName = "Beat Rap Jazz Boom Bap \" Sonido Infinito \" Boom Bap Type Beat"
    @AppStorage("owned_bgm_volume") private var bgmVolume: Double = 0.4
    @AppStorage("owned_bgm_is_playing") private var isBgmPlaying: Bool = true
    @State private var dragStartVolume: Double? = nil
    @State private var isDraggingVolume: Bool = false

    // MARK: - Paleta
    private let backgroundColor = Color(red: 0.05, green: 0.05, blue: 0.06)

    // MARK: - Datos
    private var wallet: CurrencyWallet { SessionStore.shared.wallet }

    private var ownedCategories: [ShopCategory] {
        ShopCatalog.ownedCategories(in: wallet)
    }

    private var allOwnedItems: [any ShopItem] {
        ShopCatalog.ownedItems(in: wallet)
    }

    private var items: [any ShopItem] {
        allOwnedItems
    }

    private var currentItem: (any ShopItem)? {
        guard !items.isEmpty else { return nil }
        return items[min(max(currentIndex, 0), items.count - 1)]
    }

    // MARK: - Estilo según la categoría actual
    private var stageCategory: ShopCategory {
        currentItem?.category ?? .gold
    }

    private var stageTint: Color {
        stageCategory.tier.tintColor
    }

    private var stageDim: Color {
        switch stageCategory {
        case .bronze, .gold:
            return Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.55)
        case .silver:
            return Color(red: 0.82, green: 0.86, blue: 0.92).opacity(0.55)
        }
    }

    private var stageGlow: Double {
        switch stageCategory {
        case .bronze: return 0.10
        case .silver: return 0.12
        case .gold:   return 0.16
        }
    }

    private func category(at index: Int) -> ShopCategory? {
        guard !items.isEmpty else { return nil }
        return items[min(max(index, 0), items.count - 1)].category
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            stageBackground

            VStack(spacing: 0) {
                header
                heroStage
                bottomBar
            }
        }
        .overlay {
            if listPresented {
                collectionList
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            if isBgmPlaying && !AudioManager.shared.isTimerAudioPlaying {
                AudioManager.shared.playOwnedBGM()
            }
        }
        .onDisappear {
            AudioManager.shared.stopOwnedBGM()
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            if category(at: oldValue) != category(at: newValue) {
                Haptics.success()
            } else {
                Haptics.selection()
            }
        }
    }

    // MARK: - Fondo de vitrina
    private var stageBackground: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ZStack {
                RadialGradient(
                    colors: [
                        stageTint.opacity(stageGlow),
                        stageTint.opacity(stageGlow * 0.3),
                        .clear
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 420
                )

                LinearGradient(
                    colors: [stageTint.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
            .id(stageCategory)
            .transition(.opacity)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(stageDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("MY COLLECTION")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(stageTint)

            Spacer()

            // Controles de música
            HStack(spacing: 8) {
                Text(ownedSongName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(stageDim.opacity(0.5))
                    .lineLimit(1)

                ZStack {
                    Image(systemName: isBgmPlaying ? "speaker.wave.1.fill" : "speaker.slash.fill")
                        .font(.system(size: 12, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundColor(isBgmPlaying ? stageTint : stageDim.opacity(0.5))
                        .minTapTarget(32)
                        .background(
                            Circle()
                                .fill(stageTint.opacity(0.1))
                                .frame(width: 32, height: 32)
                                .opacity(isDraggingVolume ? 1 : 0)
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartVolume == nil { dragStartVolume = bgmVolume }
                            if abs(value.translation.width) > 3 { isDraggingVolume = true }
                            
                            if isDraggingVolume {
                                let delta = -value.translation.width / 100.0
                                let newVol = min(max((dragStartVolume ?? bgmVolume) + delta, 0), 1.0)
                                if abs(newVol - bgmVolume) > 0.01 {
                                    bgmVolume = newVol
                                    AudioManager.shared.setOwnedBGMVolume(Float(newVol))
                                    Haptics.selection()
                                }
                            }
                        }
                        .onEnded { _ in
                            if !isDraggingVolume {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isBgmPlaying.toggle()
                                }
                                if isBgmPlaying {
                                    AudioManager.shared.resumeOwnedBGM()
                                } else {
                                    AudioManager.shared.pauseOwnedBGM()
                                }
                            }
                            dragStartVolume = nil
                            isDraggingVolume = false
                        }
                )
            }

            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    listPresented.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(stageTint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(stageTint.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open collection list")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.6), value: stageCategory)
    }

    // MARK: - Vitrina (objeto grande)
    @ViewBuilder
    private var heroStage: some View {
        if let item = currentItem {
            let tint = item.category.tier.tintColor
            let preview = isPreview(item)

            GeometryReader { geo in
                let heroSize = min(340, geo.size.width * 0.72)

                ZStack {
                    // Sombra de piso
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.black.opacity(0.7),
                                    Color.black.opacity(0.25),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 220
                            )
                        )
                        .frame(width: heroSize * 1.1, height: heroSize * 0.35)
                        .blur(radius: 30)
                        .offset(y: heroSize * 0.55)

                    // Charco de luz del tier sobre el piso
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [tint.opacity(preview ? 0.08 : 0.16), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 160
                            )
                        )
                        .frame(width: heroSize * 0.9, height: heroSize * 0.22)
                        .blur(radius: 22)
                        .offset(y: heroSize * 0.55)
                        .allowsHitTesting(false)

                    // Halo suave detrás del objeto
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tint.opacity(preview ? 0.07 : 0.15), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: heroSize * 0.6
                            )
                        )
                        .frame(width: heroSize * 1.3, height: heroSize * 1.3)
                        .allowsHitTesting(false)

                    // Objeto rotable
                    ShopItemPreviewView(
                        item: item,
                        size: heroSize,
                        autoRotate: true,
                        tint: preview ? tint.opacity(0.6) : tint,
                        depth: 18
                    )
                    .matchedGeometryEffect(
                        id: "item-\(item.id)",
                        in: heroNamespace,
                        isSource: !listPresented
                    )

                    // Nombre + categoría
                    VStack(spacing: 4) {
                        Spacer()
                        Text(item.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .tracking(3)
                            .foregroundColor(preview ? stageDim : .white)
                            .contentTransition(.opacity)

                        // Categoría con dos líneas finas a los costados
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(tint.opacity(0.35))
                                .frame(width: 14, height: 0.5)
                            Text(item.category.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .tracking(4)
                                .foregroundColor(tint.opacity(0.75))
                            Rectangle()
                                .fill(tint.opacity(0.35))
                                .frame(width: 14, height: 0.5)
                        }
                        .padding(.top, 2)
                        
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(preview ? stageDim.opacity(0.8) : .white.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: 280)
                                .padding(.top, 6)
                                .contentTransition(.opacity)
                        }

                        if preview {
                            Text("PREVIEW — NOT OWNED")
                                .font(.system(size: 7, weight: .heavy))
                                .tracking(1.5)
                                .foregroundColor(stageDim.opacity(0.5))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Barra inferior (navegación)
    @ViewBuilder
    private var bottomBar: some View {
        if let item = currentItem {
            HStack(spacing: 16) {
                // Flecha izquierda
                Button {
                    guard currentIndex > 0 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(currentIndex > 0 ? stageDim : stageDim.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)

                // Contador
                VStack(spacing: 2) {
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(item.category.tier.tintColor.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .id("bottom-\(item.id)")
                .transition(.opacity)

                // Flecha derecha
                Button {
                    guard currentIndex < items.count - 1 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentIndex += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(currentIndex < items.count - 1 ? stageDim : stageDim.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= items.count - 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let h = value.translation.width
                        if h < -50, currentIndex < items.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentIndex += 1
                            }
                        } else if h > 50, currentIndex > 0 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentIndex -= 1
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Lista de colección
    private var collectionList: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        listPresented = false
                    }
                }

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(stageDim.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                Text("COLLECTION")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(4)
                    .foregroundColor(stageTint)
                    .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            listRow(item, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .frame(maxHeight: 420)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [stageTint.opacity(0.3), stageTint.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: -20)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func listRow(_ item: any ShopItem, index: Int) -> some View {
        let isSelected = index == currentIndex
        let preview = isPreview(item)
        let tint = item.category.tier.tintColor

        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                currentIndex = index
                listPresented = false
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                // Miniatura
                ShopItemPreviewView(
                    item: item,
                    size: 32,
                    autoRotate: false,
                    tint: preview ? tint.opacity(0.5) : tint,
                    depth: 4
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                        .lineLimit(1)

                    Text(item.category.displayName)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(tint.opacity(0.6))
                }

                Spacer()

                if preview {
                    Text("PREVIEW")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(stageDim.opacity(0.5))
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tint.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(stageDim.opacity(0.4))
            Text("Nothing owned yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(stageDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
    private func isPreview(_ item: any ShopItem) -> Bool {
        !wallet.purchasedItemIds.contains(item.id)
    }
}
