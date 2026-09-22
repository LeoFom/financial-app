import Foundation

enum AIParserError: LocalizedError {
    case invalidResponse
    case emptyItems(String?)
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер вернул неполный ответ"
        case .emptyItems(let question):
            return question ?? "Не удалось понять сумму"
        case .server(let message):
            return Self.shorten(message)
        case .network(let message):
            return message
        }
    }

    static func from(_ error: Error) -> AIParserError {
        if let parser = error as? AIParserError { return parser }
        if let url = error as? URLError {
            switch url.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return .network("Нет связи с сервером распознавания. Проверьте интернет.")
            case .timedOut:
                return .network("Сервер распознавания не ответил вовремя. На бесплатном плане Render первый запрос может занять до минуты.")
            case .notConnectedToInternet, .dataNotAllowed:
                return .network("Нет сети. Нужен интернет, чтобы распознать расход.")
            case .appTransportSecurityRequiresSecureConnection:
                return .network("iOS заблокировал HTTP. Нужно разрешение локальной сети.")
            default:
                return .network(url.localizedDescription)
            }
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .network(error.localizedDescription)
    }

    private static func shorten(_ message: String) -> String {
        if message.contains("insufficient_quota") || message.contains("no credits") {
            return "У OpenAI закончились кредиты"
        }
        if message.contains("high demand") || message.contains("UNAVAILABLE") {
            return "Gemini сейчас перегружен, попробуйте ещё раз"
        }
        if let firstLine = message.split(whereSeparator: \.isNewline).first {
            let text = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count > 160 ? String(text.prefix(160)) + "…" : text
        }
        return message
    }
}

struct AIParseResult: Sendable {
    var drafts: [ExpenseDraft]
    var needsConfirmation: Bool
    var clarificationQuestion: String?
    var provider: String
}

struct ParserCategory: Sendable {
    var title: String
    var stableID: String
    var isArchived: Bool

    init(_ category: CategoryEntity) {
        title = category.title
        stableID = category.stableID
        isArchived = category.isArchived
    }
}

enum AIParserClient {
    /// After the Render service is live, put its HTTPS URL here.
    static let productionURL = URL(string: "https://financial-parser-8hfj.onrender.com")

    static var candidateBases: [URL] {
        var urls: [URL] = []
        if let productionURL { urls.append(productionURL) }
        #if targetEnvironment(simulator)
        urls.append(URL(string: "http://127.0.0.1:3001")!)
        #else
        urls.append(contentsOf: [
            URL(string: "http://192.168.0.6:3001")!,
            URL(string: "http://169.254.172.74:3001")!,
            URL(string: "http://MacBook-Pro-leo.local:3001")!
        ])
        #endif
        return urls
    }

    static func parse(
        text: String,
        categories: [ParserCategory],
        source: ExpenseSource,
        now: Date = Date()
    ) async throws -> AIParseResult {
        let body = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "currentDate": dayString(from: now),
            "timezone": TimeZone.current.identifier,
            "defaultCurrency": "EUR",
            "categories": categories.filter { !$0.isArchived }.map(\.title)
        ])

        guard let base = await firstReachableBase() else {
            throw AIParserError.network("Сервер распознавания недоступен. Подождите 20–30 секунд, если Render только просыпается, и попробуйте снова.")
        }
        return try await parse(base: base, body: body, text: text, categories: categories, source: source)
    }

    private static func firstReachableBase() async -> URL? {
        for base in candidateBases {
            var request = URLRequest(url: base.appendingPathComponent("health"))
            request.timeoutInterval = base.host?.contains("onrender.com") == true ? 45 : 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return base
            }
        }
        return nil
    }

    private static func parse(
        base: URL,
        body: Data,
        text: String,
        categories: [ParserCategory],
        source: ExpenseSource
    ) async throws -> AIParseResult {
        var request = URLRequest(url: base.appendingPathComponent("transactions/parse"))
        request.httpMethod = "POST"
        request.timeoutInterval = base.host?.contains("onrender.com") == true ? 60 : 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIParserError.from(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIParserError.invalidResponse
        }

        let decoded: ParsedPayload
        do {
            decoded = try JSONDecoder().decode(ParsedPayload.self, from: data)
        } catch {
            throw AIParserError.from(error)
        }
        guard http.statusCode == 200 else {
            throw AIParserError.server(decoded.error ?? "Сервер распознавания недоступен")
        }

        let drafts = decoded.items.compactMap { $0.draft(source: source, fallbackNote: text, categories: categories) }
        if drafts.isEmpty {
            throw AIParserError.emptyItems(decoded.clarificationQuestion)
        }

        return AIParseResult(
            drafts: drafts,
            needsConfirmation: decoded.needsConfirmation ?? true,
            clarificationQuestion: decoded.clarificationQuestion,
            provider: decoded.provider ?? "unknown"
        )
    }

    private static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct ParsedPayload: Decodable {
    var type: String?
    var items: [ParsedItem]
    var needsConfirmation: Bool?
    var clarificationQuestion: String?
    var provider: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case type, items, needsConfirmation, clarificationQuestion, provider, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        items = try container.decodeIfPresent([ParsedItem].self, forKey: .items) ?? []
        needsConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needsConfirmation)
        clarificationQuestion = try container.decodeIfPresent(String.self, forKey: .clarificationQuestion)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ParsedItem: Decodable {
    var amount: Double
    var currency: String?
    var category: String?
    var description: String?
    var merchant: String?
    var date: String?
    var paymentMethod: String?

    func draft(source: ExpenseSource, fallbackNote: String, categories: [ParserCategory]) -> ExpenseDraft? {
        guard amount > 0 else { return nil }
        let merchantName = cleaned(merchant) ?? cleaned(description) ?? "Без названия"
        return ExpenseDraft(
            merchant: merchantName,
            amount: Decimal(amount),
            date: Self.parseDate(date) ?? Date(),
            note: cleaned(description) ?? fallbackNote,
            source: source,
            categoryStableID: Self.resolveCategory(category, in: categories)
        )
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }

    private static func resolveCategory(_ raw: String?, in categories: [ParserCategory]) -> String? {
        let active = categories.filter { !$0.isArchived }
        guard let raw else { return active.first?.stableID }
        let needle = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if let exact = active.first(where: {
            $0.title.caseInsensitiveCompare(raw) == .orderedSame || $0.stableID.caseInsensitiveCompare(raw) == .orderedSame
        }) {
            return exact.stableID
        }

        if let fuzzy = active.first(where: {
            let title = $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return title.contains(needle) || needle.contains(title)
        }) {
            return fuzzy.stableID
        }

        let slugs: [String: String] = [
            "food": SeedIDs.groceries,
            "groceries": SeedIDs.groceries,
            "shopping": SeedIDs.groceries,
            "transport": SeedIDs.transport,
            "housing": SeedIDs.housing,
            "health": SeedIDs.health,
            "entertainment": SeedIDs.fun,
            "fun": SeedIDs.fun,
            "subscriptions": SeedIDs.fun,
            "education": SeedIDs.fun,
            "salary": SeedIDs.groceries,
            "other": SeedIDs.groceries
        ]
        if let mapped = slugs[needle], active.contains(where: { $0.stableID == mapped }) {
            return mapped
        }
        return active.first?.stableID
    }
}
