import SwiftData
import SwiftUI

struct SettingsScreen: View {
    var embedded: Bool = false

    @Environment(\.modelContext) private var context
    @Query private var budgets: [BudgetEntity]

    @State private var showingBudget = false
    @State private var limitText = ""

    private var month: Date { Date().startOfMonth }
    private var budget: BudgetEntity? {
        budgets.first { Calendar.current.isDate($0.monthStart, inMonthOf: month) }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Metrics.md) {
                    Button {
                        limitText = "\(budget?.limit ?? FinanceStore.defaultMonthlyLimit.doubleValue)"
                        showingBudget = true
                    } label: {
                        Card(padding: Metrics.md) {
                            DisclosureRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Бюджет на этот месяц")
                                        .font(Typo.rowTitle)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(Money.string(budget?.decimalLimit ?? FinanceStore.defaultMonthlyLimit))
                                        .font(Typo.rowSubtitle)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CategoriesScreen()
                    } label: {
                        Card(padding: Metrics.md) {
                            DisclosureRow {
                                Text("Категории")
                                    .font(Typo.rowTitle)
                                    .foregroundStyle(Palette.textPrimary)
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Card(padding: Metrics.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Валюта")
                                .font(Typo.rowTitle)
                                .foregroundStyle(Palette.textPrimary)
                            Text("Евро (€)")
                                .font(Typo.rowSubtitle)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }

                    Text("Расходы хранятся на этом iPhone. Синхронизация iCloud появится с платным Apple Developer.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, Metrics.xs)
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, Metrics.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Palette.background, for: .navigationBar)
        .onAppear { FinanceStore.ensureBudget(for: month, in: context) }
        .sheet(isPresented: $showingBudget) {
            BudgetLimitSheet(isPresented: $showingBudget, limitText: $limitText, month: month)
        }
    }
}

#Preview("Профиль") {
    SettingsScreen()
        .modelContainer(FinanceStore.previewContainer)
}
