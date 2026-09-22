import SwiftData
import SwiftUI

struct ReviewScreen: View {
    @Environment(\.modelContext) private var context
    @State var drafts: [ExpenseDraft]
    var clarificationQuestion: String?
    var onSaved: () -> Void
    var onFix: () -> Void

    @Query private var categories: [CategoryEntity]
    @State private var editor: ReviewEditor?
    @State private var editingIndex = 0

    init(
        draft: ExpenseDraft,
        clarificationQuestion: String? = nil,
        onSaved: @escaping () -> Void,
        onFix: @escaping () -> Void
    ) {
        self.init(drafts: [draft], clarificationQuestion: clarificationQuestion, onSaved: onSaved, onFix: onFix)
    }

    init(
        drafts: [ExpenseDraft],
        clarificationQuestion: String? = nil,
        onSaved: @escaping () -> Void,
        onFix: @escaping () -> Void
    ) {
        _drafts = State(initialValue: drafts)
        self.clarificationQuestion = clarificationQuestion
        self.onSaved = onSaved
        self.onFix = onFix
    }

    private var activeCategories: [CategoryEntity] {
        categories.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var safeIndex: Int {
        min(max(editingIndex, 0), max(drafts.count - 1, 0))
    }

    private var currentDraft: Binding<ExpenseDraft> {
        Binding(
            get: {
                guard drafts.indices.contains(safeIndex) else { return ExpenseDraft() }
                return drafts[safeIndex]
            },
            set: { newValue in
                guard drafts.indices.contains(safeIndex) else { return }
                drafts[safeIndex] = newValue
            }
        )
    }

    private var selectedCategory: CategoryEntity? {
        activeCategories.first { $0.stableID == drafts[safeIndex].categoryStableID } ?? activeCategories.first
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Metrics.lg) {
                    if let clarificationQuestion, !clarificationQuestion.isEmpty {
                        Text(clarificationQuestion)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if drafts[safeIndex].source == .receipt, let data = drafts[safeIndex].receiptPNG, let image = UIImage(data: data) {
                        Card(padding: Metrics.md, elevated: true) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Metrics.fabSize * 3)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous))
                                StatusBadge(text: "Распознано")
                                    .padding(Metrics.sm)
                            }
                        }
                    }

                    if drafts.count > 1 {
                        Card(padding: Metrics.md) {
                            VStack(spacing: Metrics.sm) {
                                ForEach(drafts.indices, id: \.self) { index in
                                    Button {
                                        editingIndex = index
                                    } label: {
                                        HStack(spacing: Metrics.md) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(drafts[index].merchant)
                                                    .font(Typo.rowTitle)
                                                    .foregroundStyle(Palette.textPrimary)
                                                Text(DateFormatting.shortDay(drafts[index].date))
                                                    .font(Typo.caption)
                                                    .foregroundStyle(Palette.textSecondary)
                                            }
                                            Spacer()
                                            Text(Money.string(drafts[index].amount))
                                                .font(Typo.amountRow)
                                                .foregroundStyle(Palette.textPrimary)
                                        }
                                        .padding(.vertical, Metrics.sm)
                                        .padding(.horizontal, Metrics.md)
                                        .background(
                                            index == safeIndex ? Palette.accentSoft : Color.clear,
                                            in: RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    if index < drafts.count - 1 {
                                        InsetSeparator(leadingInset: 0)
                                    }
                                }
                            }
                        }
                    }

                    Card(padding: Metrics.md) {
                        VStack(spacing: Metrics.sm) {
                            field(icon: "storefront", value: drafts[safeIndex].merchant) { editor = .merchant }
                            InsetSeparator(leadingInset: Metrics.iconTileCompact + Metrics.md)
                            field(icon: "eurosign.circle", value: Money.string(drafts[safeIndex].amount), amount: true) { editor = .amount }
                            InsetSeparator(leadingInset: Metrics.iconTileCompact + Metrics.md)
                            field(icon: "calendar", value: DateFormatting.shortDay(drafts[safeIndex].date)) { editor = .date }
                            InsetSeparator(leadingInset: Metrics.iconTileCompact + Metrics.md)
                            Button { editor = .category } label: {
                                DisclosureRow {
                                    HStack(spacing: Metrics.md) {
                                        Image(systemName: "tag")
                                            .font(Typo.caption.weight(.medium))
                                            .foregroundStyle(Palette.textSecondary)
                                            .frame(width: Metrics.xxl)
                                        if let selectedCategory {
                                            CategoryChip(
                                                symbol: selectedCategory.symbol,
                                                tint: selectedCategory.tint,
                                                title: selectedCategory.title
                                            )
                                        } else {
                                            Text("Категория")
                                                .font(Typo.rowTitle)
                                                .foregroundStyle(Palette.textPrimary)
                                        }
                                    }
                                } trailing: {
                                    EmptyView()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: Metrics.md) {
                        Button(drafts.count > 1 ? "Добавить все" : "Сохранить") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Исправить") { onFix() }
                            .buttonStyle(NeutralButtonStyle())
                    }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, Metrics.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Проверить")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .sheet(item: $editor) { item in
            ReviewEditorSheet(item: item, draft: currentDraft, editor: $editor, categories: activeCategories)
        }
        .tint(Palette.accent)
        .onAppear {
            for index in drafts.indices where drafts[index].categoryStableID == nil {
                drafts[index].categoryStableID = selectedCategory?.stableID
            }
        }
    }

    private func field(icon: String, value: String, amount: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DisclosureRow {
                HStack(spacing: Metrics.md) {
                    Image(systemName: icon)
                        .font(Typo.caption.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Metrics.xxl)
                    Text(value)
                        .font(amount ? Typo.amountRow : Typo.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } trailing: {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        for index in drafts.indices {
            guard drafts[index].amount > 0 else { continue }
            if drafts[index].merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drafts[index].merchant = "Без названия"
            }
        }
        let ready = drafts.filter { $0.amount > 0 }
        guard !ready.isEmpty else { return }
        FinanceStore.saveAll(ready, in: context)
        onSaved()
    }
}

enum ReviewEditor: String, Identifiable {
    case merchant, amount, date, category
    var id: String { rawValue }
    var title: String {
        switch self {
        case .merchant: return "Магазин"
        case .amount: return "Сумма"
        case .date: return "Дата"
        case .category: return "Категория"
        }
    }
}

private struct ReviewEditorSheet: View {
    let item: ReviewEditor
    @Binding var draft: ExpenseDraft
    @Binding var editor: ReviewEditor?
    let categories: [CategoryEntity]

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                switch item {
                case .merchant:
                    TextField("Магазин", text: $draft.merchant)
                        .font(Typo.body)
                        .padding(Metrics.lg)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
                        .padding(Metrics.screenInset)
                case .amount:
                    AmountEditor(amount: $draft.amount)
                case .date:
                    DatePicker("Дата", selection: $draft.date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(Metrics.screenInset)
                        .tint(Palette.accent)
                case .category:
                    ScrollView {
                        VStack(spacing: Metrics.md) {
                            ForEach(categories, id: \.stableID) { category in
                                Button {
                                    draft.categoryStableID = category.stableID
                                    editor = nil
                                } label: {
                                    Card(padding: Metrics.md) {
                                        HStack(spacing: Metrics.md) {
                                            IconTile(symbol: category.symbol, tint: category.tint)
                                            Text(category.title)
                                                .font(Typo.rowTitle)
                                                .foregroundStyle(Palette.textPrimary)
                                            Spacer()
                                            if category.stableID == draft.categoryStableID {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Palette.accent)
                                                    .accessibilityAddTraits(.isSelected)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Metrics.screenInset)
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { editor = nil }
                        .font(Typo.button)
                }
            }
        }
        .presentationDetents(item == .date || item == .category ? [.medium, .large] : [.medium])
    }
}

private struct AmountEditor: View {
    @Binding var amount: Decimal
    @State private var text = ""

    var body: some View {
        TextField("0,00", text: $text)
            .keyboardType(.decimalPad)
            .font(Typo.amountHero)
            .multilineTextAlignment(.center)
            .padding(Metrics.lg)
            .onAppear { text = amount.doubleValue == 0 ? "" : "\(amount)" }
            .onChange(of: text) { _, value in
                if let parsed = Money.parse(value) {
                    amount = parsed
                }
            }
    }
}

#Preview("Проверить") {
    NavigationStack {
        ReviewScreen(draft: ExpenseDraft(merchant: "REWE", amount: 27.4, note: "REWE"), onSaved: {}, onFix: {})
    }
    .modelContainer(FinanceStore.previewContainer)
}
