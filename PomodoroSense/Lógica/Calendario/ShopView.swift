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

    /// Modo debug: si `false` (default), muestra todo. Si `true`,
    /// oculta las categorías que todavía no tienen moneda y oculta la
    /// tienda entera si el usuario nunca recibió currency.
    @AppStorage("shop.debug.hideLockedContent") private var hideLockedContent: Bool = false

    @State private var selectedCategory: ShopCategory = .bronze
    @State private var selectedItemId: String? = nil

    private var wallet: CurrencyWallet { SessionStore.shared.wallet }

    // MARK: - Categorías visibles
    private var visibleCategories: [ShopCategory] {
        if !hideLockedContent {
            return ShopCategory.allCases
        }
        return ShopCategory.allCases.filter { cat in
            switch cat {
            case .bronze: return true
            case .silver: return wallet.isUnlocked(.silver) || wallet.silver > 0
            case .gold:   return wallet.isUnlocked(.gold)   || wallet.gold > 0
            }
        }
    }

    private var items: [any ShopItem] {
        ShopCatalog.items(in: selectedCategory)
    }

    private var selectedItem: (any ShopItem)? {
        if let id = selectedItemId,
           let found = items.first(where: { $0.id == id }) {
            return found
        }
        return items.first
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(dimmedColor.opacity(0.15))
                walletStrip
                Divider().background(dimmedColor.opacity(0.15))
                categoryTabs

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        heroSection
                        itemCarousel
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .onAppear {
            if !visibleCategories.contains(selectedCategory),
               let first = visibleCategories.first {
                selectedCategory = first
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedItemId = items.first?.id
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(dimmedColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("SHOP")
                .font(.system(size: 14, weight: .bold))
                .tracking(4)
                .foregroundColor(accentColor)

            Spacer()

            // Debug toggle
            Toggle(isOn: $hideLockedContent) {
                Text("STRICT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(dimmedColor)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(accentColor)
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    // MARK: - Wallet
    private var walletStrip: some View {
        HStack(spacing: 12) {
            walletChip(tier: .bronze, amount: wallet.bronze)
            walletChip(tier: .silver, amount: wallet.silver)
            walletChip(tier: .gold, amount: wallet.gold)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func walletChip(tier: CurrencyTier, amount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tier.iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tier.tintColor)
            Text("\(amount)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(tier.displayName)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundColor(tier.tintColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tier.tintColor.opacity(0.06))
        )
    }

    // MARK: - Category tabs
    private var categoryTabs: some View {
        HStack(spacing: 6) {
            ForEach(visibleCategories) { cat in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedCategory = cat
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(cat.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(selectedCategory == cat ? cat.tier.tintColor : dimmedColor.opacity(0.6))
                        Text(cat.subtitle)
                            .font(.system(size: 7, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(dimmedColor.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedCategory == cat
                                  ? cat.tier.tintColor.opacity(0.1)
                                  : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedCategory == cat
                                    ? cat.tier.tintColor.opacity(0.4)
                                    : Color.clear,
                                    lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Hero (item seleccionado grande)
    @ViewBuilder
    private var heroSection: some View {
        if let item = selectedItem {
            let tint = item.category.tier.tintColor
            VStack(spacing: 16) {
                ShopItemPreviewView(
                    item: item,
                    size: 260,
                    autoRotate: true,
                    tint: tint
                )

                VStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)

                    Text(item.description)
                        .font(.system(size: 12))
                        .foregroundColor(dimmedColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 320)
                }

                purchasePanel(for: item, tint: tint)
            }
            .padding(.horizontal, 24)
        } else {
            Text("No items in this category.")
                .font(.system(size: 12))
                .foregroundColor(dimmedColor)
                .padding(.vertical, 60)
        }
    }

    private func purchasePanel(for item: any ShopItem, tint: Color) -> some View {
        let owned = wallet.purchasedItemIds.contains(item.id)
        let cost = item.cost[item.category.tier] ?? 0
        let canBuy = ShopCatalog.canAfford(item, wallet: wallet) && !owned

        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: item.category.tier.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
                Text("\(cost)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(item.category.tier.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(tint.opacity(0.7))
            }

            Button {
                handlePurchase(item)
            } label: {
                Text(owned ? "OWNED" : (canBuy ? "PURCHASE" : "NOT ENOUGH"))
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(owned || !canBuy ? dimmedColor.opacity(0.6) : backgroundColor)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(owned || !canBuy ? Color.clear : tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(owned || !canBuy ? dimmedColor.opacity(0.25) : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)
        }
    }

    // MARK: - Carousel de items
    private var itemCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items, id: \.id) { item in
                    itemThumbnail(item)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func itemThumbnail(_ item: any ShopItem) -> some View {
        let isSelected = selectedItem?.id == item.id
        let tint = item.category.tier.tintColor
        let owned = wallet.purchasedItemIds.contains(item.id)

        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedItemId = item.id
            }
        } label: {
            VStack(spacing: 6) {
                ShopItemPreviewView(
                    item: item,
                    size: 70,
                    autoRotate: false,
                    tint: owned ? tint.opacity(0.5) : tint
                )

                Text(item.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(isSelected ? tint : dimmedColor.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(tint.opacity(0.7))
                }
            }
            .frame(width: 90)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tint.opacity(0.08) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tint.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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
