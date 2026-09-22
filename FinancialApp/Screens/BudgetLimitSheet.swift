import SwiftData
import SwiftUI

struct BudgetLimitSheet: View {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool
    @Binding var limitText: String
    var month: Date
    var caption: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                VStack(spacing: Metrics.lg) {
                    TextField("1000", text: $limitText)
                        .keyboardType(.decimalPad)
                        .font(Typo.amountHero)
                        .multilineTextAlignment(.center)
                        .padding(Metrics.lg)
                    if let caption {
                        Text(caption)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(Metrics.screenInset)
            }
            .navigationTitle("Бюджет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let value = Money.parse(limitText), value > 0 {
                            let current = FinanceStore.ensureBudget(for: month, in: context)
                            current.limit = value.doubleValue
                            try? context.save()
                        }
                        isPresented = false
                    }
                    .font(Typo.button)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
