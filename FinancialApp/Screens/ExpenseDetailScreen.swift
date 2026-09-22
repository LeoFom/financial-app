import SwiftData
import SwiftUI

struct ExpenseDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [ExpenseEntity]

    let stableID: String
    @State private var draft: ExpenseDraft?
    @State private var showingReview = false
    @State private var confirmDelete = false

    private var expense: ExpenseEntity? {
        expenses.first { $0.stableID == stableID }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if let expense {
                ScrollView {
                    VStack(spacing: Metrics.lg) {
                        if let data = expense.receiptPNG, let image = UIImage(data: data) {
                            Card(padding: Metrics.md) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: Metrics.fabSize * 3)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous))
                            }
                        }

                        Card(padding: Metrics.md) {
                            VStack(alignment: .leading, spacing: Metrics.md) {
                                detail(title: expense.merchant, subtitle: "Магазин")
                                InsetSeparator(leadingInset: 0)
                                detail(title: Money.string(expense.decimalAmount), subtitle: "Сумма")
                                InsetSeparator(leadingInset: 0)
                                detail(title: DateFormatting.relative(expense.date), subtitle: "Дата")
                                InsetSeparator(leadingInset: 0)
                                if let category = expense.category {
                                    HStack {
                                        CategoryChip(symbol: category.symbol, tint: category.tint, title: category.title)
                                        Spacer()
                                    }
                                }
                            }
                        }

                        VStack(spacing: Metrics.md) {
                            Button("Изменить") {
                                draft = ExpenseDraft.from(expense)
                                showingReview = true
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button("Удалить") {
                                confirmDelete = true
                            }
                            .font(Typo.button)
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                        }
                    }
                    .padding(.horizontal, Metrics.screenInset)
                    .padding(.vertical, Metrics.sm)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("Операция удалена")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .navigationTitle("Операция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .navigationDestination(isPresented: $showingReview) {
            if let draft {
                ReviewScreen(draft: draft) {
                    showingReview = false
                } onFix: {
                    showingReview = false
                }
            }
        }
        .confirmationDialog("Удалить расход?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let expense {
                    FinanceStore.delete(expense, in: context)
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func detail(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typo.rowTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(Typo.rowSubtitle)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
