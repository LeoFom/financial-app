import SwiftData
import SwiftUI

struct MonthExpensesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseEntity.date, order: .reverse) private var expenses: [ExpenseEntity]
    @Query private var budgets: [BudgetEntity]
    @Query private var categories: [CategoryEntity]

    var month: Date
    var categoryStableID: String?

    @State private var selectedExpenseID: String?
    @State private var showingBudgetEditor = false
    @State private var limitText = ""

    private var filtered: [ExpenseEntity] {
        expenses.filter { expense in
            Calendar.current.isDate(expense.date, inMonthOf: month)
                && (categoryStableID == nil || expense.category?.stableID == categoryStableID)
        }
    }

    private var spent: Decimal {
        filtered.reduce(0) { $0 + $1.decimalAmount }
    }

    private var budget: BudgetEntity? {
        budgets.first { Calendar.current.isDate($0.monthStart, inMonthOf: month) }
    }

    private var categoryTitle: String? {
        categories.first { $0.stableID == categoryStableID }?.title
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Metrics.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Metrics.md) {
                            Text(categoryTitle ?? DateFormatting.expensesTitle(for: month))
                                .font(Typo.sectionTitle)
                                .foregroundStyle(Palette.textPrimary)
                            Text(Money.string(spent))
                                .font(Typo.amountHero)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if categoryStableID == nil {
                                BudgetBar(spent: spent, limit: budget?.decimalLimit ?? FinanceStore.defaultMonthlyLimit)
                                Button("Изменить бюджет") {
                                    limitText = "\(budget?.limit ?? FinanceStore.defaultMonthlyLimit.doubleValue)"
                                    showingBudgetEditor = true
                                }
                                .font(Typo.caption.weight(.medium))
                                .foregroundStyle(Palette.onAccentSoft)
                            }
                        }
                    }

                    if filtered.isEmpty {
                        Card {
                            Text("В этом месяце ещё нет расходов")
                                .font(Typo.rowSubtitle)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    } else {
                        Card(padding: Metrics.lg) {
                            VStack(spacing: Metrics.sm) {
                                ForEach(Array(filtered.enumerated()), id: \.element.stableID) { index, item in
                                    Button {
                                        selectedExpenseID = item.stableID
                                    } label: {
                                        TransactionRow(
                                            symbol: item.category?.symbol ?? "tag.fill",
                                            tint: item.category?.tint ?? .green,
                                            title: item.merchant,
                                            subtitle: DateFormatting.relative(item.date),
                                            amount: item.decimalAmount
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    if index < filtered.count - 1 {
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
        .navigationTitle(DateFormatting.monthLabel(for: month))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .navigationDestination(item: $selectedExpenseID) { id in
            ExpenseDetailScreen(stableID: id)
        }
        .onAppear { FinanceStore.ensureBudget(for: month, in: context) }
        .sheet(isPresented: $showingBudgetEditor) {
            BudgetLimitSheet(
                isPresented: $showingBudgetEditor,
                limitText: $limitText,
                month: month,
                caption: "Лимит на \(DateFormatting.monthLabel(for: month).lowercased())"
            )
        }
    }
}
