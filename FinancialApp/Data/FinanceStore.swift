import Foundation
import SwiftData

enum SeedIDs {
    static let groceries = "cat.groceries"
    static let transport = "cat.transport"
    static let housing = "cat.housing"
    static let fun = "cat.fun"
    static let health = "cat.health"
}

enum FinanceStore {
    static let cloudKitContainer = "iCloud.app.financial.FinancialApp"
    static let defaultMonthlyLimit = Decimal(1000)

    static let schema = Schema([
        CategoryEntity.self,
        ExpenseEntity.self,
        BudgetEntity.self,
        AppSettings.self
    ])

    static func makeContainer() -> ModelContainer {
        // Personal (free) Apple ID cannot sign iCloud/CloudKit entitlements.
        // Local SwiftData works now; switch to .private(cloudKitContainer) with a paid team.
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [local])
    }

    @MainActor
    static var previewContainer: ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        seedIfNeeded(in: container.mainContext)
        return container
    }

    static func seedIfNeeded(in context: ModelContext) {
        let categories = fetchCategories(in: context)
        if categories.isEmpty {
            insertDefaultCategories(in: context)
        }
        ensureBudget(for: Date(), in: context)
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if settings.isEmpty {
            context.insert(AppSettings(didSeed: true))
        }
        try? context.save()
    }

    static func insertDefaultCategories(in context: ModelContext) {
        let defaults: [(String, String, String, CategoryTint, Int)] = [
            (SeedIDs.groceries, "Продукты", "cart.fill", .green, 0),
            (SeedIDs.transport, "Транспорт", "bus.fill", .blue, 1),
            (SeedIDs.housing, "Жильё", "house.fill", .purple, 2),
            (SeedIDs.fun, "Развлечения", "gamecontroller.fill", .coral, 3),
            (SeedIDs.health, "Здоровье", "heart.fill", .amber, 4)
        ]
        for item in defaults {
            context.insert(
                CategoryEntity(
                    stableID: item.0,
                    title: item.1,
                    symbol: item.2,
                    tint: item.3,
                    sortOrder: item.4
                )
            )
        }
    }

    static func fetchCategories(in context: ModelContext, includeArchived: Bool = false) -> [CategoryEntity] {
        let items = (try? context.fetch(FetchDescriptor<CategoryEntity>())) ?? []
        return items
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    static func category(stableID: String?, in context: ModelContext) -> CategoryEntity? {
        guard let stableID else { return nil }
        return fetchCategories(in: context, includeArchived: true).first { $0.stableID == stableID }
    }

    static func expenses(in context: ModelContext) -> [ExpenseEntity] {
        let descriptor = FetchDescriptor<ExpenseEntity>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func expenses(inMonth month: Date, categoryID: String? = nil, context: ModelContext) -> [ExpenseEntity] {
        expenses(in: context).filter { expense in
            Calendar.current.isDate(expense.date, inMonthOf: month)
                && (categoryID == nil || expense.category?.stableID == categoryID)
        }
    }

    static func spent(inMonth month: Date, categoryID: String? = nil, context: ModelContext) -> Decimal {
        expenses(inMonth: month, categoryID: categoryID, context: context)
            .reduce(Decimal(0)) { $0 + $1.decimalAmount }
    }

    static func topCategories(inMonth month: Date, limit: Int = 4, context: ModelContext) -> [(category: CategoryEntity, amount: Decimal)] {
        let monthExpenses = expenses(inMonth: month, context: context)
        var totals: [String: Decimal] = [:]
        var map: [String: CategoryEntity] = [:]
        for expense in monthExpenses {
            guard let category = expense.category else { continue }
            totals[category.stableID, default: 0] += expense.decimalAmount
            map[category.stableID] = category
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { key, value in
                guard let category = map[key] else { return nil }
                return (category, value)
            }
    }

    @discardableResult
    static func ensureBudget(for date: Date, in context: ModelContext) -> BudgetEntity {
        let start = date.startOfMonth
        let all = (try? context.fetch(FetchDescriptor<BudgetEntity>())) ?? []
        if let existing = all.first(where: { Calendar.current.isDate($0.monthStart, inMonthOf: start) }) {
            return existing
        }
        let previous = all
            .sorted { $0.monthStart > $1.monthStart }
            .first
        let limit = previous.map { Decimal($0.limit) } ?? defaultMonthlyLimit
        let budget = BudgetEntity(monthStart: start, limit: limit)
        context.insert(budget)
        try? context.save()
        return budget
    }

    static func save(_ draft: ExpenseDraft, in context: ModelContext) {
        let category = category(stableID: draft.categoryStableID, in: context)
        if let existingID = draft.existingStableID,
           let expense = expenses(in: context).first(where: { $0.stableID == existingID }) {
            expense.merchant = draft.merchant
            expense.amount = draft.amount.doubleValue
            expense.date = draft.date
            expense.note = draft.note
            expense.sourceRaw = draft.source.rawValue
            expense.receiptPNG = draft.receiptPNG
            expense.category = category
        } else {
            context.insert(
                ExpenseEntity(
                    merchant: draft.merchant,
                    amount: draft.amount,
                    date: draft.date,
                    note: draft.note,
                    source: draft.source,
                    category: category,
                    receiptPNG: draft.receiptPNG
                )
            )
        }
        try? context.save()
    }

    static func saveAll(_ drafts: [ExpenseDraft], in context: ModelContext) {
        for draft in drafts {
            save(draft, in: context)
        }
    }

    static func delete(_ expense: ExpenseEntity, in context: ModelContext) {
        context.delete(expense)
        try? context.save()
    }

    static func delete(_ category: CategoryEntity, in context: ModelContext) {
        context.delete(category)
        try? context.save()
    }

    static func nextSortOrder(in context: ModelContext) -> Int {
        (fetchCategories(in: context, includeArchived: true).map(\.sortOrder).max() ?? -1) + 1
    }

    static func nextTint(in context: ModelContext) -> CategoryTint {
        let used = Set(fetchCategories(in: context).map(\.tintRaw))
        return CategoryTint.allCases.first { !used.contains($0.rawValue) } ?? .teal
    }
}
