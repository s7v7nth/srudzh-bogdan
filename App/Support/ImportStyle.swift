import Foundation

/// Иконки и цвета для категорий из импортированного файла: сначала по названию, потом по имени иконки из файла.
enum ImportStyle {
    private static let byName: [(words: [String], symbol: String)] = [
        (["продукт", "food", "grocer", "магазин"], "cart"),
        (["транспорт", "transport", "метро", "такси"], "bus"),
        (["авто", "car", "машин"], "car"),
        (["топлив", "бензин", "fuel"], "fuelpump"),
        (["ресторан", "кафе", "restaurant", "cafe"], "fork.knife"),
        (["напит", "кофе", "drink", "coffee"], "cup.and.saucer"),
        (["алкогол", "бар", "alcohol"], "wineglass"),
        (["здоров", "health", "аптек", "врач", "medic"], "cross.case"),
        (["покупк", "одежд", "shopping", "clothes"], "bag"),
        (["кредит", "loan", "credit"], "creditcard"),
        (["жиль", "жил", "квартир", "аренд", "rent", "housing"], "house"),
        (["развлеч", "fun", "entertain", "игр"], "gamecontroller"),
        (["кот", "кош", "собак", "pet", "животн"], "pawprint"),
        (["gift", "подар"], "gift"),
        (["работ", "work", "business", "бизнес"], "briefcase"),
        (["платеж", "платёж", "bills", "коммунал"], "doc.text"),
        (["зарплат", "salary", "доход", "income"], "banknote"),
        (["продаж", "sales"], "storefront"),
    ]

    private static let byIcon: [String: String] = [
        "salary": "banknote", "gifts": "gift", "business": "storefront", "woman": "person", "cash": "banknote",
        "bonus": "star", "bank": "building.columns", "savings": "building.columns", "entertainment": "gamecontroller",
        "shoppingbag": "bag", "car": "car", "miscellaneous": "ellipsis.circle", "books": "book",
        "wrench": "wrench.and.screwdriver", "transport": "bus", "eating": "fork.knife", "forkandknife": "cart",
        "bars": "wineglass", "medical": "cross.case",
    ]

    static func symbol(icon: String, name: String) -> String {
        let n = name.lowercased()
        if let hit = byName.first(where: { $0.words.contains(where: n.contains) }) { return hit.symbol }
        return byIcon[icon.lowercased()] ?? "tag"
    }

    /// Цвета по кругу, чтобы соседние категории отличались.
    static func color(index: Int) -> String {
        let palette = ["green", "blue", "orange", "purple", "red", "teal", "pink", "indigo", "yellow", "mint", "brown"]
        return palette[index % palette.count]
    }

    /// Обязательные траты для раскладки бюджета; всё остальное идёт в «желания».
    static func isNeed(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["продукт", "транспорт", "жиль", "жил", "здоров", "health", "кредит", "платеж", "платёж", "авто", "топлив", "аренд", "коммунал"]
            .contains(where: n.contains)
    }
}
