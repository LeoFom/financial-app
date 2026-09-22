import SwiftData
import SwiftUI

struct OverviewScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseEntity.date, order: .reverse) private var expenses: [ExpenseEntity]
    @Query private var categories: [CategoryEntity]
    @Query private var budgets: [BudgetEntity]

    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var monthFilter: MonthFilter?
    @State private var selectedExpenseID: String?

    private var month: Date { Date().startOfMonth }
    private var monthExpenses: [ExpenseEntity] {
        expenses.filter { Calendar.current.isDate($0.date, inMonthOf: month) }
    }
    private var spent: Decimal {
        monthExpenses.reduce(0) { $0 + $1.decimalAmount }
    }
    private var limit: Decimal {
        budgets.first { Calendar.current.isDate($0.monthStart, inMonthOf: month) }?.decimalLimit
            ?? FinanceStore.defaultMonthlyLimit
    }
    private var tiles: [(category: CategoryEntity, amount: Decimal)] {
        FinanceStore.topCategories(inMonth: month, limit: 4, context: context)
    }
    private var recent: [ExpenseEntity] {
        Array(monthExpenses.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Metrics.lg) {
                        budgetCard
                        if tiles.isEmpty {
                            emptyCategories
                        } else {
                            categoriesCard
                        }
                        transactionsCard
                    }
                    .padding(.horizontal, Metrics.screenInset)
                    .padding(.top, Metrics.sm)
                    .padding(.bottom, Metrics.fabSize + Metrics.xxl)
                }
                .scrollIndicators(.hidden)

                FloatingAddButton { showingAdd = true }
                    .padding(.bottom, Metrics.xl)
            }
            .navigationTitle("Финансы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(Typo.navTitle)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .toolbarBackground(Palette.background, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                SettingsScreen(embedded: true)
            }
            .navigationDestination(item: $monthFilter) { filter in
                MonthExpensesScreen(month: filter.month, categoryStableID: filter.categoryID)
            }
            .navigationDestination(item: $selectedExpenseID) { id in
                ExpenseDetailScreen(stableID: id)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("autoParseTest") {
                    showingAdd = true
                }
                #endif
            }
            .fullScreenCover(isPresented: $showingAdd) {
                AddExpenseScreen()
            }
            .onAppear {
                FinanceStore.seedIfNeeded(in: context)
            }
        }
        .tint(Palette.accent)
    }

    private var budgetCard: some View {
        Button {
            monthFilter = MonthFilter(month: month, categoryID: nil)
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Metrics.md) {
                    HStack {
                        Text(DateFormatting.expensesTitle(for: month))
                            .font(Typo.sectionTitle)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Typo.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    Text(Money.string(spent))
                        .font(Typo.amountHero)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    BudgetBar(spent: spent, limit: limit)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var categoriesCard: some View {
        Card(padding: Metrics.md) {
            HStack(spacing: 0) {
                ForEach(tiles, id: \.category.stableID) { item in
                    Button {
                        monthFilter = MonthFilter(month: month, categoryID: item.category.stableID)
                    } label: {
                        CategorySummaryTile(
                            symbol: item.category.symbol,
                            tint: item.category.tint,
                            title: item.category.title,
                            amount: item.amount
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyCategories: some View {
        Card {
            Text("Категории появятся, когда появится первая трата")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var transactionsCard: some View {
        Card(padding: Metrics.lg) {
            VStack(spacing: Metrics.sm) {
                SectionHeader(title: "Последние операции") {
                    monthFilter = MonthFilter(month: month, categoryID: nil)
                }
                .padding(.bottom, Metrics.xs)

                if recent.isEmpty {
                    Text("Ещё нет расходов. Добавьте первую — можно просто написать текстом или продиктовать голосом")
                        .font(Typo.rowSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.vertical, Metrics.sm)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.stableID) { index, item in
                        Button {
                            selectedExpenseID = item.stableID
                        } label: {
                            TransactionRow(
                                symbol: item.category?.symbol ?? "tag.fill",
                                tint: item.category?.tint ?? .green,
                                title: item.merchant,
                                subtitle: DateFormatting.relative(item.date),
                                amount: item.decimalAmount,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        if index < recent.count - 1 {
                            InsetSeparator()
                        }
                    }
                }
            }
        }
    }
}

struct MonthFilter: Hashable, Identifiable {
    var month: Date
    var categoryID: String?
    var id: String { "\(month.timeIntervalSince1970)-\(categoryID ?? "all")" }
}

#Preview("Финансы") {
    OverviewScreen()
        .modelContainer(FinanceStore.previewContainer)
}
