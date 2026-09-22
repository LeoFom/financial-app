import Foundation
import SwiftData

enum ExpenseSource: String, CaseIterable, Sendable {
    case text, voice, receipt
}

@Model
final class CategoryEntity {
    var stableID: String = UUID().uuidString
    var title: String = ""
    var symbol: String = "tag.fill"
    var tintRaw: String = CategoryTint.green.rawValue
    var sortOrder: Int = 0
    var isArchived: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \ExpenseEntity.category)
    var expenses: [ExpenseEntity]? = []

    init(
        stableID: String = UUID().uuidString,
        title: String,
        symbol: String,
        tint: CategoryTint,
        sortOrder: Int
    ) {
        self.stableID = stableID
        self.title = title
        self.symbol = symbol
        self.tintRaw = tint.rawValue
        self.sortOrder = sortOrder
    }

    var tint: CategoryTint {
        CategoryTint(rawValue: tintRaw) ?? .green
    }

    var activeExpenses: [ExpenseEntity] {
        expenses ?? []
    }
}

@Model
final class ExpenseEntity {
    var stableID: String = UUID().uuidString
    var merchant: String = ""
    var amount: Double = 0
    var date: Date = Date()
    var note: String = ""
    var sourceRaw: String = ExpenseSource.text.rawValue
    var receiptPNG: Data?
    var category: CategoryEntity?

    init(
        merchant: String,
        amount: Decimal,
        date: Date,
        note: String = "",
        source: ExpenseSource,
        category: CategoryEntity?,
        receiptPNG: Data? = nil
    ) {
        self.stableID = UUID().uuidString
        self.merchant = merchant
        self.amount = amount.doubleValue
        self.date = date
        self.note = note
        self.sourceRaw = source.rawValue
        self.category = category
        self.receiptPNG = receiptPNG
    }

    var decimalAmount: Decimal { Decimal(amount) }

    var source: ExpenseSource {
        ExpenseSource(rawValue: sourceRaw) ?? .text
    }
}

@Model
final class BudgetEntity {
    var monthStart: Date = Date()
    var limit: Double = 1000

    init(monthStart: Date, limit: Decimal) {
        self.monthStart = monthStart
        self.limit = limit.doubleValue
    }

    var decimalLimit: Decimal { Decimal(limit) }
}

@Model
final class AppSettings {
    var didSeed: Bool = false

    init(didSeed: Bool = false) {
        self.didSeed = didSeed
    }
}
