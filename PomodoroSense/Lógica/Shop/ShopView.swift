//
//  ShopView.swift
//  PomodoroSense
//

import SwiftUI

struct ShopView: View {
    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onBack: () -> Void
    // ⚠️ ACÁ PONÉS EL NOMBRE DE LA CANCIÓN QUE QUIERAS MOSTRAR
    private let shopSongName = "Sweeps - just feel it"
    
    @ObservedObject private var store = SessionStore.shared
    @State private var dragStartVolume: Double? = nil
    @State private var isDraggingVolume: Bool = false
    
    @AppStorage("shop_bgm_volume") private var bgmVolume: Double = 0.4
    @AppStorage("shop.debug.hideLockedContent") private var hideLockedContent: Bool = true
    @AppStorage("shop_bgm_is_playing") private var isBgmPlaying: Bool = true
    
    @State private var currentIndex: Int = 0
    @State private var detailItemId: String? = nil
    
    @State private var isGoldMode = false
    
    // Guarda si el usuario ya descubrió el oro alguna vez
    @AppStorage("shop_has_discovered_gold") private var hasDiscoveredGold = false

    private var wallet: CurrencyWallet { store.wallet }

    /// Modo premium: se activa al desbloquear / descubrir el oro y
    /// se aplica a TODAS las pestañas (bronze, silver y gold).
    private var isPremium: Bool {
        wallet.isUnlocked(.gold) || hasDiscoveredGold
    }

    // MARK: - Categorías visibles
    private var visibleCategories: [ShopCategory] {
        if !hideLockedContent { return ShopCategory.allCases }
        return ShopCategory.allCases.filter { cat in
            switch cat {
            case .bronze: return true
            case .silver: return wallet.isUnlocked(.silver) || wallet.silver > 0
            case .gold:   return wallet.isUnlocked(.gold)   || wallet.gold > 0
            }
        }
    }

    private var currentCategory: ShopCategory {
        guard !visibleCategories.isEmpty else { return .bronze }
        return visibleCategories[min(max(currentIndex, 0), visibleCategories.count - 1)]
    }

    private var items: [any ShopItem] {
        ShopCatalog.items(in: currentCategory)
    }

    private var detailItem: (any ShopItem)? {
        guard let id = detailItemId else { return nil }
        return items.first(where: { $0.id == id })
    }

    // 3 columnas en iOS, 4 en macOS → cards más chicas
    private var columns: [GridItem] {
        #if os(macOS)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        #else
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        #endif
    }

    var body: some View {
        ZStack {
            // Fondo base
            backgroundColor.ignoresSafeArea()
            
            // Fondo premium (bronze / silver / gold) con el color de cada pestaña
            if isPremium {
                PremiumBackdrop(tint: currentCategory.tier.tintColor)
                    .ignoresSafeArea()
                    .id(currentCategory)
                    .transition(.opacity)
            }
            
            // Fondo especial para Gold
            if isGoldMode {
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.10, blue: 0.03), // Dorado oscuro arriba
                        backgroundColor,                            // Fondo normal en el medio
                        Color(red: 0.15, green: 0.10, blue: 0.03)  // Dorado oscuro abajo
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                header
                categoryPage
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: isPremium)
        .overlay {
            if let item = detailItem {
                ShopItemDetailPopup(
                    item: item,
                    accentColor: accentColor,
                    dimmedColor: dimmedColor,
                    backgroundColor: backgroundColor,
                    onPurchase: { handlePurchase(item) },
                    onDismiss: {
                        withAnimation(HIGMotion.overlay) { detailItemId = nil }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .onAppear {
                    // Si ya descubrió el oro, la música no está pausada
                    // Y el timer no está sonando -> suena la música.
                    if hasDiscoveredGold && isBgmPlaying && !AudioManager.shared.isTimerAudioPlaying {
                        AudioManager.shared.playShopBGM()
                    }
                }
        .onDisappear {
            // Siempre se corta al salir de la tienda.
            AudioManager.shared.stopShopBGM()
        }
        .onChange(of: isPremium) { oldValue, newValue in
            guard newValue, !oldValue else { return }
            Haptics.success()
        }
        .onChange(of: currentCategory) { _, newCategory in
            if newCategory == .gold {
                Haptics.success()
                
                // Si es la primera vez que entra al Oro:
                if !hasDiscoveredGold {
                    hasDiscoveredGold = true
                    isBgmPlaying = true // Forzamos a que la música arranque
                    AudioManager.shared.playShopBGM()
                }
                
                withAnimation(.easeInOut(duration: 0.6)) {
                    isGoldMode = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isGoldMode = false
                }
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(dimmedColor.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("SHOP")
                .font(.system(size: 12, weight: .heavy))
                .tracking(4)
                .foregroundColor(accentColor.opacity(0.9))

            Spacer()

            // Controles de música (solo si descubrió el oro)
            if hasDiscoveredGold {
                HStack(spacing: 8) {
                    // Nombre de la canción
                    Text(shopSongName)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(dimmedColor.opacity(0.5))
                        .lineLimit(1)

                    // Ícono + Control deslizante invisible
                    ZStack {
                        Image(systemName: isBgmPlaying ? "speaker.wave.1.fill" : "speaker.slash.fill")
                            .font(.system(size: 12, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundColor(isBgmPlaying ? accentColor : dimmedColor.opacity(0.5))
                            .minTapTarget(32)
                            .background(
                                Circle()
                                    .fill(accentColor.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                    .opacity(isDraggingVolume ? 1 : 0)
                            )
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartVolume == nil {
                                    dragStartVolume = bgmVolume
                                }
                                if abs(value.translation.width) > 3 {
                                    isDraggingVolume = true
                                }
                                if isDraggingVolume {
                                    let delta = -value.translation.width / 100.0
                                    let newVol = min(max((dragStartVolume ?? bgmVolume) + delta, 0), 1.0)
                                    if abs(newVol - bgmVolume) > 0.01 {
                                        bgmVolume = newVol
                                        AudioManager.shared.setShopBGMVolume(Float(newVol))
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
                                        AudioManager.shared.resumeShopBGM()
                                    } else {
                                        AudioManager.shared.pauseShopBGM()
                                    }
                                }
                                dragStartVolume = nil
                                isDraggingVolume = false
                            }
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Category Page
    private var categoryPage: some View {
        ZStack {
            // Fondo especial para Gold
            if isGoldMode {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.08, blue: 0.02),
                        Color.black,
                        Color(red: 0.12, green: 0.08, blue: 0.02)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 14) {
                if visibleCategories.count > 1 {
                    navigationStrip
                        .foregroundColor(isGoldMode ? CurrencyTier.gold.tintColor : accentColor)
                }
                
                walletBanner
                itemGrid
            }
        }
    }

    // MARK: - Navigation (flechas + nombre)
    private var navigationStrip: some View {
        let tint = currentCategory.tier.tintColor
        let canPrev = currentIndex > 0
        let canNext = currentIndex < visibleCategories.count - 1

        return HStack(spacing: 10) {
            Button {
                guard canPrev else { return }
                Haptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    currentIndex -= 1
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tint.opacity(0.8))
                    .opacity(canPrev ? 1 : 0) // <-- Desaparece si no puede ir atrás
                    .minTapTarget(44)
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)

            // Nombre de la categoría: tipografía tranquila
            Text(currentCategory.displayName)
                .font(.system(size: 11, weight: .medium))
                .tracking(4)
                .foregroundColor(tint.opacity(0.8))
                .frame(maxWidth: .infinity)
                .id(currentCategory)
                .transition(.opacity)

            Button {
                guard canNext else { return }
                Haptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    currentIndex += 1
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tint.opacity(0.8))
                    .opacity(canNext ? 1 : 0) // <-- Desaparece si no puede ir adelante
                    .minTapTarget(44)
            }
            .buttonStyle(.plain)
            .disabled(!canNext)
        }
        .padding(.horizontal, 20)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let h = value.translation.width
                    if h < -40, currentIndex < visibleCategories.count - 1 {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            currentIndex += 1
                        }
                    } else if h > 40, currentIndex > 0 {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            currentIndex -= 1
                        }
                    }
                }
        )
    }

    // MARK: - Wallet banner (solo el tier actual, grande)
    private var walletBanner: some View {
        let tier = currentCategory.tier
        let tint = tier.tintColor
        let amount = wallet[tier]
        let isSingleCategory = visibleCategories.count == 1

        return HStack(spacing: 10) {
            if isSingleCategory { Spacer() } // Centra si es la única categoría

            Image(systemName: tier.iconName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint.opacity(isPremium ? 0.95 : 0.8))
                .shadow(color: isPremium ? tint.opacity(0.4) : .clear, radius: 6)
                .symbolEffect(.bounce, value: currentCategory)

            VStack(alignment: isSingleCategory ? .center : .leading, spacing: 1) {
                Text("\(amount)")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: amount)
                
                // tier.displayName para Bronze es "CHIPS", así que cumplimos la regla de no decir "BRONZE"
                Text(tier.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(tint.opacity(isPremium ? 0.75 : 0.6))
            }

            if isSingleCategory { Spacer() } // Centra si es la única categoría
            else { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isPremium
                        ? LinearGradient(
                            colors: [tint.opacity(0.10), tint.opacity(0.02)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.02), Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                )
        )
        .overlay {
            if isPremium {
                PremiumHairline(tint: tint, cornerRadius: 12)
                    .transition(.opacity)
            }
        }
        .shadow(color: isPremium ? tint.opacity(0.12) : .clear, radius: 12, y: 4)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.6), value: isPremium)
    }

    // MARK: - Grid de items
    private var itemGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    itemCard(item)
                        .modifier(PremiumEntrance(index: index, active: isPremium))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            // Al cambiar de pestaña se re-dispara la entrada escalonada
            .id(currentCategory)
        }
    }

    private func itemCard(_ item: any ShopItem) -> some View {
        let tint = item.category.tier.tintColor
        let owned = wallet.purchasedItemIds.contains(item.id)
        let canBuy = ShopCatalog.canAfford(item, wallet: wallet) && !owned
        
        // Rotación: solo una vez alcanzado el modo gold
        // (en bronze y silver recién cuando ya se desbloqueó/descubrió el oro).
        let rotates = isPremium || item.category == .gold
        // Arrastrar el item dentro de la card: solo en gold (como era originalmente).
        // En bronze/silver el 3D no intercepta toques → toda la card responde al clic.
        let canInteract = item.category == .gold
        // Antes del modo gold, bronze se ve plano.
        let isFlat = !rotates && item.category == .bronze

        return Button {
            Haptics.selection()
            withAnimation(HIGMotion.overlay) { detailItemId = item.id }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    // Halo suave detrás del item (solo premium)
                    if isPremium {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [tint.opacity(owned ? 0.08 : 0.16), .clear],
                                    center: .center, startRadius: 0, endRadius: 44
                                )
                            )
                            .frame(width: 88, height: 88)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                    
                    ShopItemPreviewView(
                        item: item,
                        size: 70,
                        autoRotate: rotates,
                        interactive: canInteract,
                        flat: isFlat,
                        dimmed: owned
                    )
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(canInteract)

                    if owned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(tint.opacity(0.8))
                            .padding(4)
                            .symbolEffect(.bounce, value: owned)
                    } else if !canBuy {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(dimmedColor.opacity(0.4))
                            .padding(4)
                    }
                }

                Text(item.displayName)
                    .font(.system(size: 9, weight: .light))
                    .tracking(1)
                    .foregroundColor(owned ? dimmedColor.opacity(0.4) : .white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 3) {
                    Image(systemName: item.category.tier.iconName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(tint.opacity(0.6))
                    Text("\(item.cost[item.category.tier] ?? 0)")
                        .font(.system(size: 11, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(tint.opacity(0.8))
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isPremium
                            ? LinearGradient(
                                colors: [tint.opacity(0.08), tint.opacity(0.015)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.03), Color.white.opacity(0.03)],
                                startPoint: .top, endPoint: .bottom
                            )
                    )
            )
            .overlay {
                if isPremium {
                    PremiumHairline(tint: tint, cornerRadius: 12, intensity: owned ? 1 : 0.75)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(owned ? 0.25 : 0.1), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Acción
    private func handlePurchase(_ item: any ShopItem) {
        if SessionStore.shared.purchaseItem(item) {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }
}

// MARK: - Detalle del item (popup al tocar una card)
struct ShopItemDetailPopup: View {
    let item: any ShopItem
    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onPurchase: () -> Void
    var onDismiss: () -> Void

    private var wallet: CurrencyWallet { SessionStore.shared.wallet }

    @ObservedObject private var store = SessionStore.shared // <-- Para actualizar en vivo
    @AppStorage("shop_has_discovered_gold") private var hasDiscoveredGold = false
    
    @State private var appeared = false
    
    private var isPremium: Bool {
        store.wallet.isUnlocked(.gold) || hasDiscoveredGold
    }

    var body: some View {
        let tint = item.category.tier.tintColor
        
        return ZStack {
            // Fondo oscuro translúcido
            Color.black.opacity(appeared ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                // Header minimalista
                HStack {
                    Text(item.category.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(4)
                        .foregroundColor(tint.opacity(isPremium ? 0.85 : 0.7))
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(dimmedColor.opacity(0.7))
                            .minTapTarget(40)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .popupStagger(appeared, 0)

                // Preview 3D: gira y se puede arrastrar solo en modo premium (o en gold)
                let rotates = isPremium || item.category == .gold
                
                ZStack {
                    if isPremium {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [tint.opacity(0.22), tint.opacity(0.05), .clear],
                                    center: .center, startRadius: 0, endRadius: 130
                                )
                            )
                            .frame(width: 260, height: 260)
                            .allowsHitTesting(false)
                    }
                    
                    ShopItemPreviewView(
                        item: item,
                        size: 200,
                        autoRotate: rotates,
                        tint: tint, interactive: item.category == .gold,
                        straight: !rotates
                    )
                }
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.06), value: appeared)

                // Nombre + descripción
                VStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(size: 16, weight: .light))
                        .tracking(2)
                        .foregroundColor(.white)

                    Text(item.description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(dimmedColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 280)
                }
                .popupStagger(appeared, 2)

                purchaseButton
                    .popupStagger(appeared, 3)
            }
            .padding(30)
            .frame(maxWidth: 340)
            .background(
                // Fondo metálico si es premium
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        isPremium
                            ? LinearGradient(
                                colors: [
                                    tint.opacity(0.14),
                                    Color(red: 0.12, green: 0.11, blue: 0.10),
                                    tint.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color(red: 0.12, green: 0.11, blue: 0.10), Color(red: 0.12, green: 0.11, blue: 0.10)],
                                startPoint: .top, endPoint: .bottom
                            )
                    )
                    .overlay {
                        if isPremium {
                            PremiumHairline(tint: tint, cornerRadius: 24)
                        } else {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                    }
                    // La sombra va en el fondo (estático), no sobre el 3D que gira
                    .shadow(color: isPremium ? tint.opacity(0.2) : .black.opacity(0.4), radius: 30, x: 0, y: 15)
            )
            .scaleEffect(appeared ? 1 : 0.94)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private var purchaseButton: some View {
        let tint = item.category.tier.tintColor
        let owned = store.wallet.purchasedItemIds.contains(item.id)
        let canBuy = ShopCatalog.canAfford(item, wallet: store.wallet) && !owned
        let cost = item.cost[item.category.tier] ?? 0

        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: item.category.tier.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint.opacity(0.8))
                Text("\(cost)")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(item.category.tier.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(tint.opacity(0.5))
            }

            Button {
                onPurchase()
            } label: {
                HStack(spacing: 6) {
                    if owned {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .symbolEffect(.bounce, value: owned)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(owned ? "OWNED" : (canBuy ? "PURCHASE" : "NOT ENOUGH"))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(2)
                        .contentTransition(.interpolate)
                }
                .foregroundColor(owned || !canBuy ? dimmedColor.opacity(0.4) : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(owned || !canBuy ? Color.white.opacity(0.03) : tint)
                )
                // Brillo extra en el botón si es premium y se puede comprar
                .shadow(color: isPremium && canBuy ? tint.opacity(0.35) : .clear, radius: 10)
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: owned)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: canBuy)
        }
    }
}

// MARK: - Premium building blocks
// Piezas del estilo premium: todas estáticas y sutiles, sin loops.

private extension View {
    /// Entrada escalonada de los elementos del popup.
    func popupStagger(_ shown: Bool, _ order: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.85).delay(0.05 * Double(order) + 0.08),
                value: shown
            )
    }
}

/// Borde fino con degradé estático (más claro arriba-izquierda, se desvanece abajo-derecha).
private struct PremiumHairline: View {
    var tint: Color
    var cornerRadius: CGFloat
    var intensity: Double = 1
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [tint.opacity(0.45 * intensity), tint.opacity(0.08 * intensity)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

/// Fondo ambiental estático: un velo del color del tier arriba y abajo.
private struct PremiumBackdrop: View {
    var tint: Color
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.12), .clear, tint.opacity(0.07)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [tint.opacity(0.16), .clear],
                center: .top, startRadius: 0, endRadius: 380
            )
        }
        .allowsHitTesting(false)
    }
}

/// Entrada escalonada y suave de las cards (solo en premium).
private struct PremiumEntrance: ViewModifier {
    var index: Int
    var active: Bool
    
    @State private var shown = false
    
    func body(content: Content) -> some View {
        content
            .opacity(active ? (shown ? 1 : 0) : 1)
            .offset(y: active ? (shown ? 0 : 10) : 0)
            .onAppear {
                guard !shown else { return }
                if active {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.04)) {
                        shown = true
                    }
                } else {
                    shown = true
                }
            }
    }
}
