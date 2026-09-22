import Foundation

enum DateFormatting {
    private static let monthPrepositional = [
        "январе", "феврале", "марте", "апреле", "мае", "июне",
        "июле", "августе", "сентябре", "октябре", "ноябре", "декабре"
    ]

    private static let monthNominative = [
        "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
        "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"
    ]

    static func expensesTitle(for date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        return "Расходы в \(monthPrepositional[month - 1])"
    }

    static func monthLabel(for date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: Date())
        if year == currentYear {
            return monthNominative[month - 1]
        }
        return "\(monthNominative[month - 1]) \(year)"
    }

    static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Сегодня, \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Вчера, \(time)"
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func shortDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

extension Date {
    var startOfMonth: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: parts) ?? self
    }

    func addingMonths(_ value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: self) ?? self
    }
}

extension Calendar {
    func isDate(_ date: Date, inMonthOf other: Date) -> Bool {
        isDate(date, equalTo: other, toGranularity: .month)
    }
}
