//
//  ShopItem.swift
//  PomodoroSense
//

import Foundation

enum ShopCategory: String, Codable, CaseIterable, Identifiable {
    case bronze
    case silver
    case gold

    var id: String { rawValue }

    var tier: CurrencyTier {
        switch self {
        case .bronze: return .bronze
        case .silver: return .silver
        case .gold:   return .gold
        }
    }

    var displayName: String {
        switch self {
        case .bronze: return "BRONZE"
        case .silver: return "SILVER"
        case .gold:   return "GOLD"
        }
    }

    var subtitle: String {
        switch self {
        case .bronze: return "STARTING ITEMS"
        case .silver: return "PREMIUM ITEMS"
        case .gold:   return "LEGENDARY ITEMS"
        }
    }
}

protocol ShopItem: Identifiable, Codable {
    var id: String { get }
    var category: ShopCategory { get }
    var displayName: String { get }
    var description: String { get }
    var cost: [CurrencyTier: Int] { get }
    var iconName: String { get }
    var visual: ShopItemVisual { get }
}

struct ShopItemDefinition: ShopItem {
    let id: String
    let category: ShopCategory
    let displayName: String
    let description: String
    let cost: [CurrencyTier: Int]
    let iconName: String
    let visual: ShopItemVisual

    init(
        id: String,
        category: ShopCategory,
        displayName: String,
        description: String,
        cost: Int,
        iconName: String,
        visual: ShopItemVisual? = nil
    ) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.description = description
        self.cost = [category.tier: cost]
        self.iconName = iconName
        self.visual = visual ?? .icon(systemName: iconName)
    }
}

enum ShopCatalog {

    /// El catálogo sale de ShopCatalog.json (ver ShopCatalogLoader).
    /// Para agregar o quitar items: editá solo el JSON.
    static let allItems: [any ShopItem] = ShopCatalogLoader.load()

    static var totalCost: [CurrencyTier: Int] {
        allItems.reduce(into: [CurrencyTier: Int]()) { acc, item in
            for (tier, amount) in item.cost {
                acc[tier, default: 0] += amount
            }
        }
    }

    static func items(in category: ShopCategory) -> [any ShopItem] {
        allItems.filter { $0.category == category }
    }

    static func ownedItems(in wallet: CurrencyWallet) -> [any ShopItem] {
        allItems.filter { wallet.purchasedItemIds.contains($0.id) }
    }

    static func ownedCategories(in wallet: CurrencyWallet) -> [ShopCategory] {
        ShopCategory.allCases.filter { cat in
            allItems.contains {
                $0.category == cat && wallet.purchasedItemIds.contains($0.id)
            }
        }
    }

    static func canAfford(_ item: any ShopItem, wallet: CurrencyWallet) -> Bool {
        item.cost.allSatisfy { tier, amount in wallet[tier] >= amount }
    }

    static func purchase(_ item: any ShopItem, wallet: CurrencyWallet) -> CurrencyWallet? {
        guard canAfford(item, wallet: wallet) else { return nil }
        guard !wallet.purchasedItemIds.contains(item.id) else { return nil }

        var newWallet = wallet
        for (tier, amount) in item.cost {
            newWallet[tier] -= amount
        }
        newWallet.purchasedItemIds.insert(item.id)
        return newWallet
    }
}
