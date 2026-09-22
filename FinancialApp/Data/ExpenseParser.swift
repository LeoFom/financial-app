import Foundation

enum ParserError: LocalizedError {
    case missingAmount

    var errorDescription: String? {
        switch self {
        case .missingAmount:
            return "Не удалось понять сумму. Напишите, например: Потратил 12,50 € в REWE"
        }
    }
}

enum ExpenseParser {
    static func parse(
        _ text: String,
        categories: [CategoryEntity],
        now: Date = Date(),
        source: ExpenseSource = .text
    ) -> Result<ExpenseDraft, ParserError> {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return .failure(.missingAmount) }

        let spoken = SpokenNumber.expand(in: original)
        let folded = spoken.folded
        let date = extractDate(from: folded, now: now)
        let withoutDate = mask(folded, ranges: date.masked + timeRanges(in: folded))
        let amount = extractAmount(from: withoutDate, source: source)
        guard let amount else { return .failure(.missingAmount) }

        let merchant = extractMerchant(from: spoken, foldedWithoutDate: withoutDate)
        let category = matchCategory(
            text: folded,
            merchant: merchant,
            categories: categories
        )

        var draft = ExpenseDraft(
            merchant: merchant,
            amount: amount,
            date: date.value,
            note: original,
            source: source,
            categoryStableID: category?.stableID
        )
        if draft.categoryStableID == nil {
            draft.categoryStableID = categories.sorted { $0.sortOrder < $1.sortOrder }.first?.stableID
        }
        return .success(draft)
    }

    static func preview(
        _ text: String,
        categories: [CategoryEntity],
        now: Date = Date(),
        source: ExpenseSource = .text
    ) -> String? {
        guard case .success(let draft) = parse(text, categories: categories, now: now, source: source) else {
            return nil
        }
        let category = categories.first { $0.stableID == draft.categoryStableID }?.title
        return [Money.string(draft.amount), draft.merchant, DateFormatting.shortDay(draft.date), category]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Amount

    static func extractAmount(from text: String, source: ExpenseSource = .text) -> Decimal? {
        var scored: [(Decimal, Int)] = []

        let combo = #"(?i)(\d{1,6}(?:[.,]\d{1,2})?)\s*(?:€|eur|euro|евро)\s+(\d{1,2})\b"#
        if let regex = try? NSRegularExpression(pattern: combo) {
            for match in regex.matches(in: text, range: text.nsRange) {
                let euros = Money.parse(text.substring(match.range(at: 1)))
                let cents = Int(text.substring(match.range(at: 2))) ?? 0
                if let euros, cents < 100 {
                    let value = euros + Decimal(cents) / 100
                    scored.append((value, 80))
                }
            }
        }

        let currency = #"(?i)(?:(?:€|eur|euro|евро)\s*)(\d{1,3}(?:[ \u{00A0}]\d{3})*|\d+)(?:[.,]\d{1,2})?|(\d{1,3}(?:[ \u{00A0}]\d{3})*|\d+)(?:[.,]\d{1,2})?\s*(?:€|eur|euro|евро)"#
        if let regex = try? NSRegularExpression(pattern: currency) {
            for match in regex.matches(in: text, range: text.nsRange) {
                if let value = Money.parse(text.substring(match.range)) {
                    scored.append((value, 70))
                }
            }
        }

        let afterVerb = #"(?i)(?:потратил[аи]?|заплатил[аи]?|списал[аи]?|вышло|стоило|купил[аи]? за|на сумму|summe|gesamt|total|итого)\s+(\d{1,3}(?:[ \u{00A0}]\d{3})*|\d+)(?:[.,]\d{1,2})?"#
        if let regex = try? NSRegularExpression(pattern: afterVerb) {
            for match in regex.matches(in: text, range: text.nsRange) {
                if match.numberOfRanges > 1, let value = Money.parse(text.substring(match.range(at: 1))) {
                    scored.append((value, 65))
                }
            }
        }

        let plain = #"\d{1,3}(?:[ \u{00A0}]\d{3})*(?:[.,]\d{1,2})?|\d+[.,]\d{1,2}"#
        if let regex = try? NSRegularExpression(pattern: plain) {
            for match in regex.matches(in: text, range: text.nsRange) {
                let raw = text.substring(match.range)
                guard let value = Money.parse(raw) else { continue }
                if isYear(value) { continue }
                var score = 20
                if raw.contains(",") || raw.contains(".") { score += 25 }
                if value >= 1 { score += 5 }
                scored.append((value, score))
            }
        }

        guard !scored.isEmpty else { return nil }
        if source == .receipt {
            return scored.map(\.0).max()
        }
        return scored.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }?.0
    }

    private static func isYear(_ value: Decimal) -> Bool {
        let number = value.doubleValue
        return number == floor(number) && (1900...2100).contains(Int(number))
    }

    // MARK: - Date

    struct Dated {
        var value: Date
        var masked: [NSRange]
    }

    static func extractDate(from text: String, now: Date) -> Dated {
        let calendar = Calendar.current
        let lower = text

        if let match = firstMatch(#"\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b"#, in: lower) {
            let day = Int(lower.substring(match.range(at: 1))) ?? 0
            let month = Int(lower.substring(match.range(at: 2))) ?? 0
            var year = match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound
                ? Int(lower.substring(match.range(at: 3))) ?? calendar.component(.year, from: now)
                : calendar.component(.year, from: now)
            if year < 100 { year += 2000 }
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                return Dated(value: clampFuture(date, now: now, calendar: calendar), masked: [match.range])
            }
        }

        if let match = firstMatch(#"\b(\d{1,2})\s+(января|янв\.?|февраля|фев\.?|марта|мар\.?|апреля|апр\.?|мая|июня|июн\.?|июля|июл\.?|августа|авг\.?|сентября|сент?\.?|октября|окт\.?|ноября|нояб?\.?|декабря|дек\.?|januar|jan\.?|februar|feb\.?|marz|märz|mär\.?|april|apr\.?|mai|juni|jun\.?|juli|jul\.?|august|aug\.?|september|sep\.?|oktober|okt\.?|november|nov\.?|dezember|dez\.?)\s*(\d{4})?"#, in: lower) {
            let day = Int(lower.substring(match.range(at: 1))) ?? 1
            let month = monthIndex(lower.substring(match.range(at: 2)))
            var year = calendar.component(.year, from: now)
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                year = Int(lower.substring(match.range(at: 3))) ?? year
            }
            if let month, let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                return Dated(value: clampFuture(date, now: now, calendar: calendar), masked: [match.range])
            }
        }

        let relatives: [(String, Int)] = [
            ("позавчера", -2), ("vorgestern", -2),
            ("вчера", -1), ("учора", -1), ("gestern", -1),
            ("сегодня", 0), ("сьогодні", 0), ("heute", 0),
            ("завтра", 1)
        ]
        for (word, offset) in relatives {
            if let range = lower.range(of: word) {
                let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
                return Dated(value: date, masked: [NSRange(range, in: lower)])
            }
        }

        let weekdays: [(String, Int)] = [
            ("понедельник", 2), ("montag", 2),
            ("вторник", 3), ("dienstag", 3),
            ("среду", 4), ("среды", 4), ("среда", 4), ("mittwoch", 4),
            ("четверг", 5), ("donnerstag", 5),
            ("пятницу", 6), ("пятницы", 6), ("пятница", 6), ("freitag", 6),
            ("субботу", 7), ("субботы", 7), ("суббота", 7), ("samstag", 7),
            ("воскресенье", 1), ("воскресенья", 1), ("sonntag", 1)
        ]
        for (word, weekday) in weekdays {
            if let range = lower.range(of: word) {
                return Dated(value: mostRecent(weekday: weekday, from: now, calendar: calendar), masked: [NSRange(range, in: lower)])
            }
        }

        return Dated(value: now, masked: [])
    }

    private static func timeRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d{1,2}:\d{2}\b"#) else { return [] }
        return regex.matches(in: text, range: text.nsRange).map(\.range)
    }

    private static func clampFuture(_ date: Date, now: Date, calendar: Calendar) -> Date {
        if date > now.addingTimeInterval(36 * 3600) {
            return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
        return date
    }

    private static func mostRecent(weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let today = calendar.component(.weekday, from: now)
        var delta = today - weekday
        if delta < 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: -delta, to: now) ?? now
    }

    private static func monthIndex(_ raw: String) -> Int? {
        let token = raw.folded.replacingOccurrences(of: ".", with: "")
        let map: [Int: [String]] = [
            1: ["январ", "янв", "januar", "jan"],
            2: ["феврал", "фев", "februar", "feb"],
            3: ["март", "мар", "marz", "marz", "mar"],
            4: ["апрел", "апр", "april", "apr"],
            5: ["мая", "май", "mai"],
            6: ["июн", "juni", "jun"],
            7: ["июл", "juli", "jul"],
            8: ["август", "авг", "august", "aug"],
            9: ["сентябр", "сент", "сен", "september", "sep"],
            10: ["октябр", "окт", "oktober", "okt"],
            11: ["ноябр", "ноя", "november", "nov"],
            12: ["декабр", "дек", "dezember", "dez"]
        ]
        for (index, keys) in map where keys.contains(where: { token.hasPrefix($0) || $0.hasPrefix(token) }) {
            return index
        }
        return nil
    }

    // MARK: - Merchant

    static func extractMerchant(from original: String, foldedWithoutDate: String) -> String {
        if let known = knownMerchant(in: original) {
            return known
        }

        let preposition = #"(?i)(?:^|\s)(?:в|во|у|in|at|im)\s+([^\n,.;]+)$"#
        if let match = firstMatch(preposition, in: foldedWithoutDate) {
            let tail = foldedWithoutDate.substring(match.range(at: 1))
            let cleaned = stripNoise(tail)
            if cleaned.count >= 2 { return preserveCasing(cleaned, from: original) }
        }

        let leftover = stripNoise(foldedWithoutDate)
        if leftover.count >= 2, leftover.split(separator: " ").count <= 4 {
            return preserveCasing(leftover, from: original)
        }
        return "Без названия"
    }

    private static func knownMerchant(in text: String) -> String? {
        let aliases: [(String, String)] = [
            ("реве", "REWE"), ("rewe", "REWE"),
            ("лидль", "Lidl"), ("лидл", "Lidl"), ("lidl", "Lidl"),
            ("альди", "Aldi"), ("aldi", "Aldi"),
            ("эдека", "Edeka"), ("edeka", "Edeka"),
            ("пенни", "Penny"), ("penny", "Penny"),
            ("нетто", "Netto"), ("netto", "Netto"),
            ("кауфланд", "Kaufland"), ("kaufland", "Kaufland"),
            ("rossmann", "Rossmann"), ("россман", "Rossmann"),
            ("ikea", "IKEA"), ("икеа", "IKEA"),
            ("uber", "Uber"), ("убер", "Uber"),
            ("starbucks", "Starbucks"), ("старбакс", "Starbucks"),
            ("apotheke", "Apotheke"), ("аптека", "Аптека"),
            ("bvg", "BVG"), ("flixbus", "FlixBus")
        ]
        let folded = text.folded
        for (needle, label) in aliases {
            if folded.range(of: "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b", options: .regularExpression) != nil {
                return label
            }
        }
        return nil
    }

    private static func stripNoise(_ text: String) -> String {
        var result = text
        let noise = [
            "сегодня", "вчера", "позавчера", "завтра", "сегодняшний",
            "heute", "gestern", "vorgestern",
            "потратил", "потратила", "потратили", "заплатил", "заплатила",
            "купил", "купила", "списал", "вышло", "стоило",
            "евро", "eur", "euro", "центов", "цента", "сумма", "сумму",
            "на сумму", "за", "и", "я", "мы", "на", "по", "к", "с",
            "понедельник", "вторник", "среду", "среды", "четверг",
            "пятницу", "пятница", "субботу", "воскресенье"
        ]
        for word in noise {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(of: #"\d+(?:[.,]\d{1,2})?"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[€]"#, with: " ", options: .regularExpression)
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func preserveCasing(_ needle: String, from original: String) -> String {
        let foldedOrig = original.folded
        let foldedNeedle = needle.folded
        if let range = foldedOrig.range(of: foldedNeedle),
           let originalRange = Range(NSRange(range, in: original), in: original) {
            return String(original[originalRange])
        }
        return needle.capitalized
    }

    // MARK: - Category

    static func matchCategory(
        text: String,
        merchant: String,
        categories: [CategoryEntity]
    ) -> CategoryEntity? {
        let haystack = (text + " " + merchant).folded
        let active = categories.filter { !$0.isArchived }

        if let byStore = category(forMerchant: merchant.folded, in: active) {
            return byStore
        }

        for category in active {
            let title = category.title.folded
            if title.count >= 3, haystack.contains(title) {
                return category
            }
            let stem = String(title.prefix(max(4, title.count - 2)))
            if stem.count >= 4, haystack.contains(stem) {
                return category
            }
        }

        let keywords: [(String, [String])] = [
            (SeedIDs.groceries, [
                "rewe", "lidl", "aldi", "edeka", "penny", "netto", "kaufland", "tesco",
                "магазин", "продукт", "еда", "еду", "супермаркет", "grocery", "хлеб",
                "молоко", "кофе", "чай", "овощ", "фрукт", "пицца", "бургер"
            ]),
            (SeedIDs.transport, [
                "uber", "bolt", "taxi", "такси", "ticket", "bahn", "bvg", "flixbus",
                "автобус", "метро", "транспорт", "билет", "бензин", "заправк",
                "парковк", "deutschlandticket", "u-bahn", "sbahn", "tram"
            ]),
            (SeedIDs.housing, [
                "ikea", "obi", "hornbach", "rent", "квартир", "жиль", "дом",
                "wohn", "коммунал", "электричеств", "аренда"
            ]),
            (SeedIDs.fun, [
                "кино", "cinema", "netflix", "steam", "игр", "развлеч",
                "концерт", "театр", "spotify", "youtube"
            ]),
            (SeedIDs.health, [
                "аптек", "apotheke", "pharmacy", "doctor", "здоров", "clinic",
                "врач", "лекарств", "dm", "rossmann", "витамин"
            ])
        ]

        for (seed, words) in keywords where words.contains(where: { haystack.contains($0) }) {
            if let match = active.first(where: { $0.stableID == seed }) {
                return match
            }
        }
        return nil
    }

    private static func category(forMerchant merchant: String, in categories: [CategoryEntity]) -> CategoryEntity? {
        let map: [(String, String)] = [
            ("rewe", SeedIDs.groceries), ("lidl", SeedIDs.groceries), ("aldi", SeedIDs.groceries),
            ("edeka", SeedIDs.groceries), ("penny", SeedIDs.groceries), ("netto", SeedIDs.groceries),
            ("kaufland", SeedIDs.groceries), ("starbucks", SeedIDs.groceries),
            ("uber", SeedIDs.transport), ("bolt", SeedIDs.transport), ("bvg", SeedIDs.transport),
            ("flixbus", SeedIDs.transport), ("deutschlandticket", SeedIDs.transport),
            ("ikea", SeedIDs.housing), ("obi", SeedIDs.housing),
            ("apotheke", SeedIDs.health), ("rossmann", SeedIDs.health), ("dm", SeedIDs.health)
        ]
        for (store, seed) in map where merchant.contains(store) {
            if let match = categories.first(where: { $0.stableID == seed }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func mask(_ text: String, ranges: [NSRange]) -> String {
        let ns = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { continue }
            ns.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return ns as String
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.firstMatch(in: text, range: text.nsRange)
    }
}

// MARK: - Spoken numbers

private enum SpokenNumber {
    static func expand(in text: String) -> String {
        let tokens = text
            .replacingOccurrences(of: #"[,.!?;:]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return text }

        var result: [String] = []
        var index = 0
        while index < tokens.count {
            if let parsed = parsePhrase(tokens, from: index) {
                result.append(Self.format(parsed.value))
                index += parsed.consumed
            } else {
                result.append(tokens[index])
                index += 1
            }
        }
        return result.joined(separator: " ")
    }

    private static func parsePhrase(_ tokens: [String], from start: Int) -> (value: Decimal, consumed: Int)? {
        var index = start
        var total = 0
        var current = 0
        var consumed = 0

        while index < tokens.count {
            let word = tokens[index].folded
            if word == "запятая" {
                guard consumed > 0, index + 1 < tokens.count, let cents = ones[tokens[index + 1].folded] ?? teens[tokens[index + 1].folded] else { break }
                let euros = Decimal(total + current)
                return (euros + Decimal(cents) / 100, consumed + 2)
            }
            if let thousandFactor = thousand[word] {
                current = max(current, 1) * thousandFactor
                total += current
                current = 0
                consumed += 1
                index += 1
                continue
            }
            if let value = hundreds[word] ?? tens[word] ?? teens[word] ?? ones[word] {
                current += value
                consumed += 1
                index += 1
                continue
            }
            break
        }

        guard consumed > 0 else { return nil }
        return (Decimal(total + current), consumed)
    }

    private static func format(_ value: Decimal) -> String {
        if value == Decimal(value.doubleValue.rounded()) {
            return "\(Int(value.doubleValue))"
        }
        return "\(value)"
    }

    private static let ones: [String: Int] = [
        "ноль": 0, "один": 1, "одна": 1, "одно": 1, "первого": 1, "первое": 1,
        "два": 2, "две": 2, "второго": 2, "второе": 2,
        "три": 3, "третьего": 3, "третье": 3,
        "четыре": 4, "четвертого": 4, "четвертое": 4,
        "пять": 5, "пятого": 5, "пятое": 5,
        "шесть": 6, "шестого": 6, "шестое": 6,
        "семь": 7, "седьмого": 7, "седьмое": 7,
        "восемь": 8, "восьмого": 8, "восьмое": 8,
        "девять": 9, "девятого": 9, "девятое": 9
    ]
    private static let teens: [String: Int] = [
        "десять": 10, "десятого": 10, "десятое": 10,
        "одиннадцать": 11, "одиннадцатого": 11,
        "двенадцать": 12, "двенадцатого": 12, "двенадцатое": 12,
        "тринадцать": 13, "тринадцатого": 13,
        "четырнадцать": 14, "четырнадцатого": 14,
        "пятнадцать": 15, "пятнадцатого": 15,
        "шестнадцать": 16, "шестнадцатого": 16,
        "семнадцать": 17, "семнадцатого": 17,
        "восемнадцать": 18, "восемнадцатого": 18,
        "девятнадцать": 19, "девятнадцатого": 19
    ]
    private static let tens: [String: Int] = [
        "двадцать": 20, "двадцатого": 20, "двадцатое": 20,
        "тридцать": 30, "тридцатого": 30, "тридцатое": 30,
        "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
        "семьдесят": 70, "восемьдесят": 80, "девяносто": 90
    ]
    private static let hundreds: [String: Int] = [
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400,
        "пятьсот": 500, "шестьсот": 600, "семьсот": 700, "восемьсот": 800, "девятьсот": 900
    ]
    private static let thousand: [String: Int] = [
        "тысяча": 1000, "тысячи": 1000, "тысяч": 1000
    ]
}

// MARK: - String helpers

private extension String {
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
    }

    var nsRange: NSRange { NSRange(startIndex..., in: self) }

    func substring(_ range: NSRange) -> String {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: self) else { return "" }
        return String(self[swiftRange])
    }
}
