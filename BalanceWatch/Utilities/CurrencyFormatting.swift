import Foundation

enum SupportedCurrency: String, CaseIterable, Identifiable {
    case RUB
    case EUR
    case USD
    case SEK

    var id: String { rawValue }
}

extension Double {
    func formattedCurrency(code: String) -> String {
        formatted(
            .currency(code: code)
                .precision(.fractionLength(0 ... 2))
                .presentation(.narrow)
        )
    }
}

extension Date {
    var monthTitle: String {
        formatted(.dateTime.month(.wide).year())
    }
}
