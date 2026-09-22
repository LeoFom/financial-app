import SwiftData
import SwiftUI

struct CategoryEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var category: CategoryEntity?

    @State private var title = ""
    @State private var symbol = "tag.fill"
    @State private var tint: CategoryTint = .green
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private let symbols = [
        "cart.fill", "bus.fill", "house.fill", "gamecontroller.fill", "heart.fill",
        "fork.knife", "cup.and.saucer.fill", "car.fill", "tram.fill", "bag.fill",
        "book.fill", "film.fill", "cross.case.fill", "gift.fill", "tag.fill"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Metrics.lg) {
                        Card {
                            TextField("Название", text: $title)
                                .font(Typo.body)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: Metrics.md) {
                                Text("Цвет")
                                    .font(Typo.sectionTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                HStack(spacing: Metrics.sm) {
                                    ForEach(CategoryTint.allCases) { item in
                                        Button {
                                            tint = item
                                        } label: {
                                            Circle()
                                                .fill(item.foreground)
                                                .frame(width: Metrics.iconTileCompact, height: Metrics.iconTileCompact)
                                                .overlay {
                                                    if tint == item {
                                                        Circle().stroke(Palette.textPrimary, lineWidth: 2)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(item.rawValue)
                                        .accessibilityAddTraits(tint == item ? .isSelected : [])
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: Metrics.md) {
                                Text("Иконка")
                                    .font(Typo.sectionTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: Metrics.md) {
                                    ForEach(symbols, id: \.self) { item in
                                        Button {
                                            symbol = item
                                        } label: {
                                            IconTile(symbol: item, tint: tint)
                                                .overlay {
                                                    if symbol == item {
                                                        RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                                                            .stroke(Palette.accent.opacity(0.45), lineWidth: 2)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(symbol == item ? .isSelected : [])
                                    }
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Typo.caption)
                                .foregroundStyle(Palette.danger)
                        }

                        Button("Сохранить") { save() }
                            .buttonStyle(PrimaryButtonStyle())

                        if category != nil {
                            Button("Удалить") { confirmDelete = true }
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
            }
            .navigationTitle(category == nil ? "Новая категория" : "Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                if let category {
                    title = category.title
                    symbol = category.symbol
                    tint = category.tint
                } else {
                    tint = FinanceStore.nextTint(in: context)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                if let category, !category.activeExpenses.isEmpty {
                    Button("Оставить") { confirmDelete = false }
                } else {
                    Button("Удалить", role: .destructive) { deleteCategory() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                if let category, !category.activeExpenses.isEmpty {
                    Text("Сначала перенесите или удалите расходы в этой категории.")
                }
            }
        }
    }

    private var deleteTitle: String {
        if let category, !category.activeExpenses.isEmpty {
            return "Нельзя удалить категорию с расходами"
        }
        return "Удалить категорию?"
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Введите название категории"
            return
        }
        if let category {
            category.title = name
            category.symbol = symbol
            category.tintRaw = tint.rawValue
        } else {
            context.insert(
                CategoryEntity(
                    title: name,
                    symbol: symbol,
                    tint: tint,
                    sortOrder: FinanceStore.nextSortOrder(in: context)
                )
            )
        }
        try? context.save()
        dismiss()
    }

    private func deleteCategory() {
        guard let category else { return }
        guard category.activeExpenses.isEmpty else {
            errorMessage = "Нельзя удалить категорию, пока в ней есть расходы"
            return
        }
        FinanceStore.delete(category, in: context)
        dismiss()
    }
}
