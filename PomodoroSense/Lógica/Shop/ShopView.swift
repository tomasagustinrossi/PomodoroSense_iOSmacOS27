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

    @AppStorage("shop.debug.hideLockedContent") private var hideLockedContent: Bool = true

    @State private var currentIndex: Int = 0
    @State private var detailItemId: String? = nil

    private var wallet: CurrencyWallet { SessionStore.shared.wallet }

    // MARK: - Categorías visibles
    private var visibleCategories: [ShopCategory] {
        #if DEBUG
        return ShopCategory.allCases
        #else
        if !hideLockedContent { return ShopCategory.allCases }
        return ShopCategory.allCases.filter { cat in
            switch cat {
            case .bronze: return true
            case .silver: return wallet.isUnlocked(.silver) || wallet.silver > 0
            case .gold:   return wallet.isUnlocked(.gold)   || wallet.gold > 0
            }
        }
        #endif
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
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                categoryPage
                Spacer(minLength: 0)
            }
        }
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
            if currentIndex >= visibleCategories.count { currentIndex = 0 }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(dimmedColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("SHOP")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(accentColor)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Category Page
    private var categoryPage: some View {
        VStack(spacing: 14) {
            navigationStrip
            walletBanner
            itemGrid
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(canPrev ? tint : dimmedColor.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)

            VStack(spacing: 2) {
                Text(currentCategory.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundColor(tint)
                Text(currentCategory.subtitle)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .id(currentCategory)   // fuerza re-render al cambiar
            .transition(.opacity)

            Button {
                guard canNext else { return }
                Haptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    currentIndex += 1
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(canNext ? tint : dimmedColor.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
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
        let amount = wallet[tier]

        return HStack(spacing: 10) {
            Image(systemName: tier.iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(tier.tintColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(amount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(tier.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(tier.tintColor.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tier.tintColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tier.tintColor.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Grid de items
    private var itemGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items, id: \.id) { item in
                    itemCard(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func itemCard(_ item: any ShopItem) -> some View {
        let tint = item.category.tier.tintColor
        let owned = wallet.purchasedItemIds.contains(item.id)
        let canBuy = ShopCatalog.canAfford(item, wallet: wallet) && !owned

        return Button {
            Haptics.selection()
            withAnimation(HIGMotion.overlay) { detailItemId = item.id }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ShopItemPreviewView(
                        item: item,
                        size: 70,
                        autoRotate: false,
                        tint: owned ? tint.opacity(0.5) : tint,
                        interactive: false
                    )
                    .frame(maxWidth: .infinity)

                    // Badge estado en la esquina
                    if owned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(tint)
                            .background(
                                Circle()
                                    .fill(tint.opacity(0.15))
                                    .frame(width: 18, height: 18)
                            )
                            .padding(2)
                    } else if !canBuy {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(dimmedColor.opacity(0.5))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 16, height: 16)
                            )
                            .padding(2)
                    }
                }

                Text(item.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(owned ? dimmedColor.opacity(0.7) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 2) {
                    Image(systemName: item.category.tier.iconName)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(tint)
                    Text("\(item.cost[item.category.tier] ?? 0)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(tint.opacity(0.85))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(owned ? 0.25 : 0.1), lineWidth: 1)
            )
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

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.4).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 18) {
                // Close
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(dimmedColor)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                // Preview grande rotable
                ShopItemPreviewView(
                    item: item,
                    size: 240,
                    autoRotate: true,
                    tint: item.category.tier.tintColor
                )

                // Nombre + descripción
                VStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)

                    Text(item.description)
                        .font(.system(size: 12))
                        .foregroundColor(dimmedColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 320)
                }

                purchaseButton
            }
            .padding(24)
            .frame(maxWidth: 360)
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

    private var purchaseButton: some View {
        let tint = item.category.tier.tintColor
        let owned = wallet.purchasedItemIds.contains(item.id)
        let canBuy = ShopCatalog.canAfford(item, wallet: wallet) && !owned
        let cost = item.cost[item.category.tier] ?? 0

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.category.tier.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
                Text("\(cost)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(item.category.tier.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(tint.opacity(0.7))
            }

            Button {
                onPurchase()
            } label: {
                Text(owned ? "OWNED" : (canBuy ? "PURCHASE" : "NOT ENOUGH"))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(owned || !canBuy ? dimmedColor.opacity(0.6) : backgroundColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(owned || !canBuy ? Color.clear : tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(owned || !canBuy ? dimmedColor.opacity(0.25) : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)
        }
    }
}
