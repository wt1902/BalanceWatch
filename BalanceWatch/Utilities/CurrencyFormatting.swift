import Foundation

enum SupportedCurrency: String, CaseIterable, Identifiable {
    case RUB
    case EUR
    case USD
    case SEK

    var id: String { rawValue }
}

extension Double {
    /// Целые суммы без копеек, остальные — ровно с двумя знаками («8 480,50 ₽»),
    /// как во Flutter-клиенте.
    func formattedCurrency(code: String) -> String {
        let whole = (self * 100).rounded().truncatingRemainder(dividingBy: 100) == 0
        return formatted(
            .currency(code: code)
                .precision(.fractionLength(whole ? 0 : 2))
                .presentation(.narrow)
        )
    }
}

extension Date {
    var monthTitle: String {
        formatted(.dateTime.month(.wide).year())
    }
}
