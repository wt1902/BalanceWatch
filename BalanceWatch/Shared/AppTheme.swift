import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Палитра «Лес» — та же, что у пресета по умолчанию во Flutter-клиенте и у
/// иконки приложения.
enum BalancePalette {
    /// Акцент интерфейса (кнопки, ссылки, выбор) — мятный, читается на чёрном.
    static let accent = Color(red: 0x7f / 255, green: 0xd6 / 255, blue: 0xb9 / 255)
    /// Основной цвет пресета «Лес».
    static let forest = Color(red: 0x35 / 255, green: 0x68 / 255, blue: 0x59 / 255)
    /// Градиент карточки общего баланса (как фон иконки).
    static let cardTop = Color(red: 0x3f / 255, green: 0x7d / 255, blue: 0x6b / 255)
    static let cardBottom = Color(red: 0x1a / 255, green: 0x4a / 255, blue: 0x3e / 255)
    /// Текст на карточке баланса.
    static let mint = Color(red: 0xbd / 255, green: 0xf7 / 255, blue: 0xe3 / 255)
    /// Доходы — teal, расходы — deep orange, как во Flutter.
    static let income = Color(red: 0x26 / 255, green: 0xb3 / 255, blue: 0xa3 / 255)
    static let expense = Color(red: 0xff / 255, green: 0x6e / 255, blue: 0x40 / 255)
}
