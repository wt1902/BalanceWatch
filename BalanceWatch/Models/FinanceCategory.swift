import SwiftUI

struct FinanceCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let emoji: String
    let colorName: String

    var tint: Color { Self.color(named: colorName) }

    init(
        id: String,
        name: String,
        icon: String,
        emoji: String = "",
        colorName: String
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.emoji = emoji
        self.colorName = colorName
    }

    static let expenseCategories: [FinanceCategory] = [
        .init(id: "food", name: "Продукты", icon: "cart.fill", colorName: "orange"),
        .init(id: "transport", name: "Транспорт", icon: "car.fill", colorName: "blue"),
        .init(id: "home", name: "Дом", icon: "house.fill", colorName: "indigo"),
        .init(id: "entertainment", name: "Развлечения", icon: "gamecontroller.fill", colorName: "pink"),
        .init(id: "health", name: "Здоровье", icon: "cross.case.fill", colorName: "red"),
        .init(id: "shopping", name: "Покупки", icon: "bag.fill", colorName: "purple"),
        .init(id: "subscriptions", name: "Подписки", icon: "repeat", colorName: "cyan"),
        .init(id: "education", name: "Образование", icon: "book.fill", colorName: "mint"),
        .init(id: "other-expense", name: "Другое", icon: "ellipsis.circle.fill", colorName: "gray")
    ]

    static let incomeCategories: [FinanceCategory] = [
        .init(id: "salary", name: "Зарплата", icon: "banknote.fill", colorName: "green"),
        .init(id: "freelance", name: "Подработка", icon: "laptopcomputer", colorName: "teal"),
        .init(id: "investments", name: "Инвестиции", icon: "chart.line.uptrend.xyaxis", colorName: "blue"),
        .init(id: "gift", name: "Подарок", icon: "gift.fill", colorName: "pink"),
        .init(id: "other-income", name: "Другое", icon: "plus.circle.fill", colorName: "gray")
    ]

    static func categories(for kind: TransactionKind) -> [FinanceCategory] {
        kind == .expense ? expenseCategories : incomeCategories
    }

    static func find(named name: String) -> FinanceCategory? {
        (expenseCategories + incomeCategories).first { $0.name == name }
    }

    static func color(named name: String) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "gray": .gray
        case "coral": Color(red: 0.98, green: 0.38, blue: 0.38)
        case "peach": Color(red: 1.00, green: 0.58, blue: 0.38)
        case "gold": Color(red: 0.90, green: 0.64, blue: 0.08)
        case "lime": Color(red: 0.52, green: 0.78, blue: 0.16)
        case "forest": Color(red: 0.10, green: 0.48, blue: 0.30)
        case "turquoise": Color(red: 0.05, green: 0.67, blue: 0.63)
        case "sky": Color(red: 0.18, green: 0.62, blue: 0.91)
        case "navy": Color(red: 0.12, green: 0.25, blue: 0.52)
        case "lavender": Color(red: 0.55, green: 0.40, blue: 0.85)
        case "magenta": Color(red: 0.82, green: 0.16, blue: 0.55)
        case "brown": Color(red: 0.48, green: 0.31, blue: 0.20)
        case "slate": Color(red: 0.30, green: 0.36, blue: 0.45)
        default: .indigo
        }
    }
}
