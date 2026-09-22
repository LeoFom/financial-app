import Foundation

struct ExpenseDraft: Hashable, Sendable {
    var merchant: String = ""
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String = ""
    var source: ExpenseSource = .text
    var categoryStableID: String?
    var existingStableID: String?
    var receiptPNG: Data?

    static func from(_ expense: ExpenseEntity) -> ExpenseDraft {
        ExpenseDraft(
            merchant: expense.merchant,
            amount: expense.decimalAmount,
            date: expense.date,
            note: expense.note,
            source: expense.source,
            categoryStableID: expense.category?.stableID,
            existingStableID: expense.stableID,
            receiptPNG: expense.receiptPNG
        )
    }
}
