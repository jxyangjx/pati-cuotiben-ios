import SwiftUI
import UIKit

enum Theme {
    static let paper = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.09, green: 0.11, blue: 0.12, alpha: 1)
        }
        return UIColor(red: 0.965, green: 0.949, blue: 0.914, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1)
        }
        return UIColor.white
    })

    static let accent = Color(red: 0.05, green: 0.45, blue: 0.48)
    static let correct = Color(red: 0.16, green: 0.46, blue: 0.32)
    static let wrong = Color(red: 0.70, green: 0.22, blue: 0.18)
    static let pending = Color(red: 0.62, green: 0.42, blue: 0.12)

    static func color(for result: VerdictResult) -> Color {
        switch result {
        case .correct: correct
        case .wrong: wrong
        case .pending: pending
        }
    }
}

struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func cardChrome() -> some View { modifier(CardChrome()) }

    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

extension Date {
    var chineseStamp: String {
        formatted(
            .dateTime
                .month()
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "zh_CN"))
        )
    }
}
