import SwiftData
import SwiftUI

struct AnalyticsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseEntity.date, order: .reverse) private var expenses: [ExpenseEntity]
    @Query private var budgets: [BudgetEntity]

    @State private var month = Date().startOfMonth
    @State private var monthFilter: MonthFilter?

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

    private var rows: [(category: CategoryEntity, amount: Decimal)] {
        FinanceStore.topCategories(inMonth: month, limit: 12, context: context)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Metrics.lg) {
                        monthSwitcher

                        Card {
                            VStack(alignment: .leading, spacing: Metrics.md) {
                                Text(DateFormatting.expensesTitle(for: month))
                                    .font(Typo.sectionTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                Text(Money.string(spent))
                                    .font(Typo.amountHero)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                BudgetBar(spent: spent, limit: limit)
                            }
                        }

                        if rows.isEmpty {
                            Text("В этом месяце ещё нет расходов")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            Card(padding: Metrics.lg) {
                                VStack(spacing: Metrics.sm) {
                                    ForEach(Array(rows.enumerated()), id: \.element.category.stableID) { index, item in
                                        Button {
                                            monthFilter = MonthFilter(month: month, categoryID: item.category.stableID)
                                        } label: {
                                            HStack(spacing: Metrics.md) {
                                                IconTile(symbol: item.category.symbol, tint: item.category.tint)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.category.title)
                                                        .font(Typo.rowTitle)
                                                        .foregroundStyle(Palette.textPrimary)
                                                    Text(share(item.amount))
                                                        .font(Typo.rowSubtitle)
                                                        .foregroundStyle(Palette.textSecondary)
                                                }
                                                Spacer()
                                                Text(Money.string(item.amount))
                                                    .font(Typo.amountRow)
                                                    .foregroundStyle(Palette.textPrimary)
                                                Image(systemName: "chevron.right")
                                                    .font(Typo.caption.weight(.semibold))
                                                    .foregroundStyle(Palette.textTertiary)
                                            }
                                            .frame(minHeight: Metrics.rowMinHeight)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        if index < rows.count - 1 {
                                            InsetSeparator()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.screenInset)
                    .padding(.vertical, Metrics.sm)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Аналитика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .navigationDestination(item: $monthFilter) { filter in
                MonthExpensesScreen(month: filter.month, categoryStableID: filter.categoryID)
            }
            .onAppear {
                FinanceStore.ensureBudget(for: month, in: context)
            }
        }
        .tint(Palette.accent)
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                month = month.addingMonths(-1)
                FinanceStore.ensureBudget(for: month, in: context)
            } label: {
                Image(systemName: "chevron.left")
                    .font(Typo.navTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: Metrics.iconTile, height: Metrics.iconTile)
            }
            .accessibilityLabel("Предыдущий месяц")

            Spacer()
            Text(DateFormatting.monthLabel(for: month))
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer()

            Button {
                month = month.addingMonths(1)
                FinanceStore.ensureBudget(for: month, in: context)
            } label: {
                Image(systemName: "chevron.right")
                    .font(Typo.navTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: Metrics.iconTile, height: Metrics.iconTile)
            }
            .accessibilityLabel("Следующий месяц")
        }
    }

    private func share(_ amount: Decimal) -> String {
        guard spent > 0 else { return "0%" }
        let ratio = (amount as NSDecimalNumber).doubleValue / (spent as NSDecimalNumber).doubleValue
        return "\(Int((ratio * 100).rounded()))%"
    }
}

#Preview("Аналитика") {
    AnalyticsScreen()
        .modelContainer(FinanceStore.previewContainer)
}
